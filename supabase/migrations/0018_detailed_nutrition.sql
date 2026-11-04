-- =====================================================================
-- 0018_detailed_nutrition.sql
--
-- Full nutrition-label fields per serving (FDA label set): fat breakdown,
-- cholesterol, added sugars, potassium, calcium, iron, vitamins A/C/D and
-- a free-text serving size. All optional and range-checked. fork_recipe
-- copies them.
-- =====================================================================

alter table public.recipes
  add column if not exists serving_size text,
  add column if not exists sat_fat_g numeric(6,1),
  add column if not exists trans_fat_g numeric(6,1),
  add column if not exists poly_fat_g numeric(6,1),
  add column if not exists mono_fat_g numeric(6,1),
  add column if not exists cholesterol_mg integer,
  add column if not exists added_sugar_g numeric(6,1),
  add column if not exists potassium_mg integer,
  add column if not exists calcium_mg integer,
  add column if not exists iron_mg numeric(6,1),
  add column if not exists vitamin_d_mcg numeric(6,1),
  add column if not exists vitamin_a_mcg integer,
  add column if not exists vitamin_c_mg numeric(6,1),
  add column if not exists micros jsonb not null default '{}'::jsonb;

alter table public.recipes drop constraint if exists recipes_micros_check;
alter table public.recipes add constraint recipes_micros_check
  check (jsonb_typeof(micros) = 'object' and pg_column_size(micros) <= 2000);

alter table public.recipes drop constraint if exists recipes_nutrition_extra_check;
alter table public.recipes add constraint recipes_nutrition_extra_check
  check (
    (serving_size is null or char_length(serving_size) <= 80)
    and (sat_fat_g    is null or sat_fat_g    between 0 and 500)
    and (trans_fat_g  is null or trans_fat_g  between 0 and 500)
    and (poly_fat_g   is null or poly_fat_g   between 0 and 500)
    and (mono_fat_g   is null or mono_fat_g   between 0 and 500)
    and (cholesterol_mg is null or cholesterol_mg between 0 and 20000)
    and (added_sugar_g  is null or added_sugar_g  between 0 and 500)
    and (potassium_mg   is null or potassium_mg   between 0 and 20000)
    and (calcium_mg     is null or calcium_mg     between 0 and 20000)
    and (iron_mg        is null or iron_mg        between 0 and 500)
    and (vitamin_d_mcg  is null or vitamin_d_mcg  between 0 and 5000)
    and (vitamin_a_mcg  is null or vitamin_a_mcg  between 0 and 50000)
    and (vitamin_c_mg   is null or vitamin_c_mg   between 0 and 5000));

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
    diets, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    serving_size, sat_fat_g, trans_fat_g, poly_fat_g, mono_fat_g,
    cholesterol_mg, added_sugar_g, potassium_mg, calcium_mg, iron_mg,
    vitamin_d_mcg, vitamin_a_mcg, vitamin_c_mg, micros
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
         src.sodium_mg,
         src.serving_size, src.sat_fat_g, src.trans_fat_g, src.poly_fat_g,
         src.mono_fat_g, src.cholesterol_mg, src.added_sugar_g,
         src.potassium_mg, src.calcium_mg, src.iron_mg,
         src.vitamin_d_mcg, src.vitamin_a_mcg, src.vitamin_c_mg, src.micros
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

-- ---------------------------------------------------------------------
-- Personal nutrition goals and food diary. Strictly per user: nobody,
-- including cookbook co-members, can read another person's diary.
-- ---------------------------------------------------------------------
create table if not exists public.nutrition_goals (
  user_id uuid primary key references auth.users(id) on delete cascade,
  calories integer not null default 2000 check (calories between 500 and 10000),
  protein_g numeric(6,1) not null default 100 check (protein_g between 0 and 1000),
  carbs_g numeric(6,1) not null default 250 check (carbs_g between 0 and 1500),
  fat_g numeric(6,1) not null default 67 check (fat_g between 0 and 600),
  fiber_g numeric(6,1) not null default 28 check (fiber_g between 0 and 300),
  sugar_g numeric(6,1) not null default 50 check (sugar_g between 0 and 1000),
  sodium_mg integer not null default 2300 check (sodium_mg between 0 and 20000),
  updated_at timestamptz not null default now()
);
alter table public.nutrition_goals enable row level security;

drop policy if exists nutrition_goals_own on public.nutrition_goals;
create policy nutrition_goals_own on public.nutrition_goals
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create table if not exists public.food_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  logged_on date not null default current_date,
  meal text not null default 'snack'
    check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
  title text not null check (char_length(title) between 1 and 160),
  recipe_id uuid references public.recipes(id) on delete set null,
  servings numeric(5,1) not null default 1 check (servings > 0 and servings <= 100),
  nutrition jsonb not null default '{}'::jsonb
    check (jsonb_typeof(nutrition) = 'object' and pg_column_size(nutrition) <= 3000),
  created_at timestamptz not null default now()
);
create index if not exists food_log_user_day_idx
  on public.food_log (user_id, logged_on);
alter table public.food_log enable row level security;

drop policy if exists food_log_own on public.food_log;
create policy food_log_own on public.food_log
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
