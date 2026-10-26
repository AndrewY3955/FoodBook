-- =====================================================================
-- 0013_fork_everything_account_delete.sql
--
--   * fork_recipe also copies cuisine, theme and accent colour. The
--     client copies the image files into the fork's own storage prefix
--     (SQL cannot copy storage objects) and then sets the fork's cover,
--     background and recipe_images rows.
--   * Deleting an account removes everything the user owns: libraries in
--     which they are the only active member (cascading recipes, images,
--     pantry, plans, ...) and recipes they created in shared libraries.
--     Forks and saved copies in other people's libraries are separate
--     rows with forked_from_recipe_id ON DELETE SET NULL, so they
--     survive. Their image files live under the forker's own prefix.
--   * account_storage_paths() tells the client which storage objects
--     belong to that deletion, because storage.objects cannot be deleted
--     from SQL (protect_delete trigger).
--   * delete_my_account() performs the deletion for the caller.
-- =====================================================================

create or replace function public.fork_recipe(p_recipe_id uuid, p_library_id uuid)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_new_id uuid;
begin
  if not public.is_library_member(p_library_id) then
    raise exception 'not a member of library %', p_library_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.recipes (
    library_id, created_by, title, description, meal_type, season,
    base_servings, prep_minutes, cook_minutes, source_url, external_video_url,
    import_source, is_public, forked_from_recipe_id,
    cuisine, theme, accent_color
  )
  select p_library_id,
         (select auth.uid()),
         left(src.title || ' (fork)', 160),
         src.description,
         src.meal_type,
         src.season,
         src.base_servings,
         src.prep_minutes,
         src.cook_minutes,
         src.source_url,
         src.external_video_url,
         'fork',
         false,
         src.id,
         src.cuisine,
         src.theme,
         src.accent_color
    from public.recipes src
   where src.id = p_recipe_id
  returning id into v_new_id;

  if v_new_id is null then
    raise exception 'recipe % is not visible to the caller', p_recipe_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.recipe_ingredients (
    recipe_id, library_id, ingredient_id, quantity, unit, note, is_optional, sort_order
  )
  select v_new_id, p_library_id, ri.ingredient_id, ri.quantity, ri.unit,
         ri.note, ri.is_optional, ri.sort_order
    from public.recipe_ingredients ri
    join public.ingredients i on i.id = ri.ingredient_id
   where ri.recipe_id = p_recipe_id
     and i.library_id is null;

  insert into public.recipe_steps (recipe_id, library_id, step_number, instruction, timer_seconds)
  select v_new_id, p_library_id, rs.step_number, rs.instruction, rs.timer_seconds
    from public.recipe_steps rs
   where rs.recipe_id = p_recipe_id;

  return v_new_id;
end;
$$;

-- Libraries the user is the only active member of.
create or replace function public._sole_member_libraries(p_user uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.library_id
    from public.library_members m
   where m.user_id = p_user
     and m.revoked_at is null
     and not exists (
       select 1 from public.library_members o
        where o.library_id = m.library_id
          and o.user_id <> p_user
          and o.revoked_at is null);
$$;
revoke all on function public._sole_member_libraries(uuid) from public, anon, authenticated;

create or replace function public.account_storage_paths()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct o.name), '{}')
    from storage.objects o
   where o.bucket_id = 'recipe-covers'
     and (
       split_part(o.name, '/', 1)::text in (
         select l::text from public._sole_member_libraries((select auth.uid())) l)
       or exists (
         select 1 from public.recipes r
          where r.created_by = (select auth.uid())
            and r.library_id::text = split_part(o.name, '/', 1)
            and r.id::text = split_part(o.name, '/', 2))
     );
$$;
revoke all on function public.account_storage_paths() from public, anon;
grant execute on function public.account_storage_paths() to authenticated;

create or replace function public._purge_user_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.recipes
   where created_by = old.id
     and library_id not in (select public._sole_member_libraries(old.id));
  delete from public.libraries
   where id in (select public._sole_member_libraries(old.id));
  return old;
end;
$$;
revoke all on function public._purge_user_content() from public, anon, authenticated;

drop trigger if exists purge_user_content on auth.users;
create trigger purge_user_content
  before delete on auth.users
  for each row execute function public._purge_user_content();

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in' using errcode = 'insufficient_privilege';
  end if;
  delete from auth.users where id = (select auth.uid());
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
