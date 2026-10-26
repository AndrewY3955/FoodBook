-- =====================================================================
-- 0014_diets_nutrition.sql
--
--   * recipes.diets: dietary labels (vegetarian, gluten free, high
--     protein, ...) from a closed list, so Discover and the recipe box
--     can filter on stable values. Closed and length-capped by CHECK
--     constraints, because the column is writable by any library member.
--   * recipes.calories .. sodium_mg: optional nutrition facts PER
--     SERVING, range-checked so a typo cannot store nonsense.
--   * fork_recipe copies both.
-- =====================================================================

alter table public.recipes
  add column if not exists diets text[] not null default '{}',
  add column if not exists calories integer,
  add column if not exists protein_g numeric(6,1),
  add column if not exists carbs_g numeric(6,1),
  add column if not exists fat_g numeric(6,1),
  add column if not exists fiber_g numeric(6,1),
  add column if not exists sugar_g numeric(6,1),
  add column if not exists sodium_mg integer;

alter table public.recipes drop constraint if exists recipes_diets_check;
alter table public.recipes add constraint recipes_diets_check
  check (
    cardinality(diets) <= 16
    and diets <@ array[
      'vegetarian', 'vegan', 'pescatarian', 'gluten_free', 'dairy_free',
      'nut_free', 'egg_free', 'low_carb', 'keto', 'paleo', 'high_protein',
      'low_fat', 'low_sodium', 'high_fiber', 'halal', 'kosher'
    ]::text[]);

alter table public.recipes drop constraint if exists recipes_nutrition_check;
alter table public.recipes add constraint recipes_nutrition_check
  check (
    (calories  is null or calories  between 0 and 5000)
    and (protein_g is null or protein_g between 0 and 500)
    and (carbs_g   is null or carbs_g   between 0 and 500)
    and (fat_g     is null or fat_g     between 0 and 500)
    and (fiber_g   is null or fiber_g   between 0 and 500)
    and (sugar_g   is null or sugar_g   between 0 and 500)
    and (sodium_mg is null or sodium_mg between 0 and 20000));

create index if not exists recipes_diets_idx
  on public.recipes using gin (diets) where is_public;

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
    cuisine, theme, accent_color,
    diets, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg
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
         src.accent_color,
         src.diets,
         src.calories,
         src.protein_g,
         src.carbs_g,
         src.fat_g,
         src.fiber_g,
         src.sugar_g,
         src.sodium_mg
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
