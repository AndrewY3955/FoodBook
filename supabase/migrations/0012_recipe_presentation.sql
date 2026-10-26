-- =====================================================================
-- 0012_recipe_presentation.sql
-- Pictures, backgrounds and a public discovery feed.
--
--   * recipes.theme / accent_color / background_image_path: how a recipe
--     is dressed up on its detail page.
--   * recipe_images: extra photos beyond the cover.
--   * is_valid_cover_path accepts three object names under the same
--     <library>/<recipe>/ prefix: cover, background, photo-<uuid>.
--     Every storage policy already calls this function, so widening it
--     here widens all of them without touching the tenancy checks.
--   * An index for the feed query.
-- =====================================================================

create or replace function public.is_valid_cover_path(p_path text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_path is not null
     and p_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(cover|background|photo-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.(jpg|jpeg|png|webp)$';
$$;

comment on function public.is_valid_cover_path(text) is
  'Enforces the <library_id>/<recipe_id>/(cover|background|photo-<uuid>).<ext> object layout that storage policies depend on.';

-- ---------------------------------------------------------------------
-- Presentation columns
-- ---------------------------------------------------------------------
alter table public.recipes
  add column if not exists theme text not null default 'plain',
  add column if not exists accent_color text,
  add column if not exists background_image_path text;

alter table public.recipes drop constraint if exists recipes_theme_check;
alter table public.recipes add constraint recipes_theme_check
  check (theme in ('plain', 'cream', 'herb', 'tomato', 'ocean', 'night'));

alter table public.recipes drop constraint if exists recipes_accent_color_check;
alter table public.recipes add constraint recipes_accent_color_check
  check (accent_color is null or accent_color ~ '^#[0-9a-fA-F]{6}$');

alter table public.recipes drop constraint if exists recipes_background_image_path_check;
alter table public.recipes add constraint recipes_background_image_path_check
  check (background_image_path is null
         or (public.is_valid_cover_path(background_image_path)
             and background_image_path like '%/background.%'));

-- Cuisine is a closed list rather than free-form tags: tags live behind
-- library-member RLS and cannot be browsed across libraries, and a
-- fixed list gives the discovery slider stable categories.
alter table public.recipes
  add column if not exists cuisine text;

alter table public.recipes drop constraint if exists recipes_cuisine_check;
alter table public.recipes add constraint recipes_cuisine_check
  check (cuisine is null or cuisine in (
    'american', 'italian', 'mexican', 'french', 'mediterranean',
    'middle_eastern', 'indian', 'chinese', 'japanese', 'thai',
    'vegetarian', 'vegan', 'seafood', 'baking'));

create index if not exists recipes_feed_idx
  on public.recipes (created_at desc) where is_public;
create index if not exists recipes_feed_cuisine_idx
  on public.recipes (cuisine, created_at desc) where is_public;

-- ---------------------------------------------------------------------
-- Extra photos
-- ---------------------------------------------------------------------
create table if not exists public.recipe_images (
  id           uuid primary key default gen_random_uuid(),
  recipe_id    uuid not null references public.recipes(id) on delete cascade,
  library_id   uuid not null references public.libraries(id) on delete cascade,
  storage_path text not null
               check (public.is_valid_cover_path(storage_path)
                      and storage_path like '%/photo-%'),
  caption      text check (caption is null or char_length(caption) <= 200),
  sort_order   integer not null default 0 check (sort_order between 0 and 100),
  created_at   timestamptz not null default now(),
  unique (storage_path)
);

create index if not exists recipe_images_recipe_idx on public.recipe_images (recipe_id, sort_order);
create index if not exists recipe_images_library_idx on public.recipe_images (library_id);

drop trigger if exists sync_library on public.recipe_images;
create trigger sync_library
  before insert or update on public.recipe_images
  for each row execute function public.tg_sync_library_from_recipe();

-- A recipe carries at most 12 extra photos.
create or replace function public.tg_limit_recipe_images()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.recipe_images where recipe_id = new.recipe_id) >= 12 then
    raise exception 'a recipe can have at most 12 photos'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists limit_images on public.recipe_images;
create trigger limit_images
  before insert on public.recipe_images
  for each row execute function public.tg_limit_recipe_images();

alter table public.recipe_images enable row level security;
alter table public.recipe_images force row level security;

drop policy if exists recipe_images_select_public_anon on public.recipe_images;
create policy recipe_images_select_public_anon
  on public.recipe_images for select
  to anon
  using (public.recipe_is_public(recipe_id));

drop policy if exists recipe_images_select on public.recipe_images;
create policy recipe_images_select
  on public.recipe_images for select
  to authenticated
  using (public.is_library_member(library_id) or public.recipe_is_public(recipe_id));

drop policy if exists recipe_images_insert on public.recipe_images;
create policy recipe_images_insert
  on public.recipe_images for insert
  to authenticated
  with check (public.is_library_member(library_id));

drop policy if exists recipe_images_update on public.recipe_images;
create policy recipe_images_update
  on public.recipe_images for update
  to authenticated
  using (public.is_library_member(library_id))
  with check (public.is_library_member(library_id));

drop policy if exists recipe_images_delete on public.recipe_images;
create policy recipe_images_delete
  on public.recipe_images for delete
  to authenticated
  using (public.is_library_member(library_id));

grant select on public.recipe_images to anon, authenticated;
grant insert, update, delete on public.recipe_images to authenticated;
