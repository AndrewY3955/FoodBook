-- =====================================================================
-- 0017_recipe_albums.sql
--
-- Albums are categories inside a library's recipes.
--   * Every library has at least one album. Existing recipes move into a
--     "General" album that can be renamed like any other.
--   * A recipe with no album is placed in the library's first album.
--   * Albums are created, renamed and reordered by members who can edit
--     recipes. Deleting goes through delete_recipe_album(), which moves
--     the recipes to another album and refuses to remove the last one.
-- =====================================================================

begin;

create table public.recipe_albums (
  id          uuid primary key default gen_random_uuid(),
  library_id  uuid not null references public.libraries(id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);
create index recipe_albums_library_idx on public.recipe_albums (library_id, sort_order, created_at);

alter table public.recipes
  add column album_id uuid references public.recipe_albums(id) on delete set null;
create index recipes_album_idx on public.recipes (album_id);

alter table public.recipe_albums enable row level security;

create policy recipe_albums_select_member
  on public.recipe_albums for select to authenticated
  using (public.is_library_member(library_id));

create policy recipe_albums_insert_member
  on public.recipe_albums for insert to authenticated
  with check (public.is_library_member(library_id));

create policy recipe_albums_update_member
  on public.recipe_albums for update to authenticated
  using (public.is_library_member(library_id))
  with check (public.is_library_member(library_id));

-- Backfill: a General album per library, and every recipe goes into it.
insert into public.recipe_albums (library_id, name)
select id, 'General' from public.libraries;

update public.recipes r
   set album_id = (
     select a.id from public.recipe_albums a
      where a.library_id = r.library_id
      order by a.sort_order, a.created_at limit 1
   );

-- New libraries start with a General album.
create or replace function public.tg_library_default_album()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.recipe_albums (library_id, name) values (new.id, 'General');
  return new;
end;
$$;

create trigger libraries_default_album
  after insert on public.libraries
  for each row execute function public.tg_library_default_album();

-- A recipe always has an album, and always one from its own library.
create or replace function public.tg_recipe_album()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.album_id is not null and not exists (
    select 1 from public.recipe_albums a
     where a.id = new.album_id and a.library_id = new.library_id
  ) then
    raise exception 'Album belongs to a different cookbook.';
  end if;

  if new.album_id is null then
    select a.id into new.album_id
      from public.recipe_albums a
     where a.library_id = new.library_id
     order by a.sort_order, a.created_at limit 1;
  end if;
  return new;
end;
$$;

create trigger recipes_album
  before insert or update of album_id, library_id on public.recipes
  for each row execute function public.tg_recipe_album();

create or replace function public.delete_recipe_album(p_album_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lib uuid;
  v_target uuid;
begin
  select library_id into v_lib from public.recipe_albums where id = p_album_id;
  if v_lib is null or not public.is_library_member(v_lib) then
    raise exception 'Album not found.';
  end if;

  select a.id into v_target
    from public.recipe_albums a
   where a.library_id = v_lib and a.id <> p_album_id
   order by a.sort_order, a.created_at limit 1;
  if v_target is null then
    raise exception 'A cookbook needs at least one album.';
  end if;

  update public.recipes set album_id = v_target where album_id = p_album_id;
  delete from public.recipe_albums where id = p_album_id;
end;
$$;
revoke all on function public.delete_recipe_album(uuid) from public, anon;
grant execute on function public.delete_recipe_album(uuid) to authenticated;

commit;
