-- Public recipes may expose the ingredient entries they reference, but not
-- other custom entries in their owner's library.
create policy ingredients_select_public_recipe
  on public.ingredients for select
  to anon, authenticated
  using (
    exists (
      select 1
        from public.recipe_ingredients ri
        join public.recipes r on r.id = ri.recipe_id
       where ri.ingredient_id = ingredients.id
         and r.is_public
    )
  );

-- Catalog entries are read-only to app users; conflicts leave existing
-- canonical entries and their IDs untouched.
insert into public.ingredients (library_id, name, grocery_category, default_unit)
select null, name, 'spices'::public.grocery_category, unit::public.measure_unit
from (values
  ('Allspice', 'tsp'),
  ('Ancho Chilli Powder', 'tsp'),
  ('Black Cardamom', 'tsp'),
  ('Cajun Seasoning', 'tsp'),
  ('Caraway Seeds', 'tsp'),
  ('Cardamom', 'tsp'),
  ('Cayenne Pepper', 'tsp'),
  ('Celery Salt', 'tsp'),
  ('Celery Seed', 'tsp'),
  ('Chinese Five Spice', 'tsp'),
  ('Chilli Flakes', 'tsp'),
  ('Chipotle Powder', 'tsp'),
  ('Cinnamon', 'tsp'),
  ('Cloves', 'tsp'),
  ('Coriander Seeds', 'tsp'),
  ('Crushed Red Pepper', 'tsp'),
  ('Curry Powder', 'tsp'),
  ('Dill', 'tsp'),
  ('Dried Basil', 'tsp'),
  ('Dried Chives', 'tsp'),
  ('Dried Cilantro', 'tsp'),
  ('Dried Mint', 'tsp'),
  ('Dried Oregano', 'tsp'),
  ('Dried Parsley', 'tsp'),
  ('Dried Rosemary', 'tsp'),
  ('Dried Sage', 'tsp'),
  ('Dried Thyme', 'tsp'),
  ('Fennel Seeds', 'tsp'),
  ('Fenugreek', 'tsp'),
  ('Garam Masala', 'tsp'),
  ('Garlic Powder', 'tsp'),
  ('Ginger Powder', 'tsp'),
  ('Ground Allspice', 'tsp'),
  ('Ground Cardamom', 'tsp'),
  ('Ground Cinnamon', 'tsp'),
  ('Ground Cloves', 'tsp'),
  ('Ground Coriander', 'tsp'),
  ('Ground Ginger', 'tsp'),
  ('Ground Mustard', 'tsp'),
  ('Italian Seasoning', 'tsp'),
  ('Kosher Salt', 'tsp'),
  ('Lemon Pepper', 'tsp'),
  ('Mustard Seeds', 'tsp'),
  ('Nutmeg', 'tsp'),
  ('Onion Powder', 'tsp'),
  ('Paprika', 'tsp'),
  ('Pumpkin Pie Spice', 'tsp'),
  ('Ras el Hanout', 'tsp'),
  ('Red Pepper Flakes', 'tsp'),
  ('Saffron', 'pinch'),
  ('Seasoned Salt', 'tsp'),
  ('Star Anise', 'piece'),
  ('Sumac', 'tsp'),
  ('Table Salt', 'tsp'),
  ('Taco Seasoning', 'tsp'),
  ('Tandoori Masala', 'tsp'),
  ('Tikka Masala Spice Mix', 'tsp'),
  ('Turmeric', 'tsp'),
  ('White Pepper', 'tsp'),
  ('Za''atar', 'tsp')
) as seasoning(name, unit)
on conflict do nothing;

-- Keep public-recipe copies independent of the source library. Custom
-- ingredients are copied into the destination library rather than linked
-- across library boundaries.
create or replace function public.fork_recipe(p_recipe_id uuid, p_library_id uuid)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_new_id uuid;
  v_ingredient_id uuid;
  v_line record;
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
  select p_library_id, (select auth.uid()), left(src.title || ' (fork)', 160),
         src.description, src.meal_type, src.season, src.base_servings,
         src.prep_minutes, src.cook_minutes, src.source_url,
         src.external_video_url, 'fork', false, src.id,
         src.cuisine, src.theme, src.accent_color,
         src.diets, src.calories, src.protein_g, src.carbs_g, src.fat_g,
         src.fiber_g, src.sugar_g, src.sodium_mg, src.serving_size,
         src.sat_fat_g, src.trans_fat_g, src.poly_fat_g, src.mono_fat_g,
         src.cholesterol_mg, src.added_sugar_g, src.potassium_mg,
         src.calcium_mg, src.iron_mg, src.vitamin_d_mcg, src.vitamin_a_mcg,
         src.vitamin_c_mg, src.micros
    from public.recipes src
   where src.id = p_recipe_id
  returning id into v_new_id;

  if v_new_id is null then
    raise exception 'recipe % is not visible to the caller', p_recipe_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_line in
    select ri.quantity, ri.unit, ri.note, ri.is_optional, ri.sort_order,
           i.id, i.library_id, i.name, i.grocery_category, i.default_unit
      from public.recipe_ingredients ri
      join public.ingredients i on i.id = ri.ingredient_id
     where ri.recipe_id = p_recipe_id
     order by ri.sort_order, ri.id
  loop
    if v_line.library_id is null or v_line.library_id = p_library_id then
      v_ingredient_id := v_line.id;
    else
      insert into public.ingredients (library_id, name, grocery_category, default_unit)
      values (p_library_id, v_line.name, v_line.grocery_category, v_line.default_unit)
      on conflict (library_id, lower(name)) where library_id is not null
      do update set name = ingredients.name
      returning id into v_ingredient_id;
    end if;

    insert into public.recipe_ingredients (
      recipe_id, library_id, ingredient_id, quantity, unit, note, is_optional, sort_order
    ) values (
      v_new_id, p_library_id, v_ingredient_id, v_line.quantity, v_line.unit,
      v_line.note, v_line.is_optional, v_line.sort_order
    );
  end loop;

  insert into public.recipe_steps (recipe_id, library_id, step_number, instruction, timer_seconds)
  select v_new_id, p_library_id, rs.step_number, rs.instruction, rs.timer_seconds
    from public.recipe_steps rs
   where rs.recipe_id = p_recipe_id;

  return v_new_id;
end;
$$;

-- A public recipe can also be added directly to another library's list.
-- Resolve private source ingredients into that library before aggregation.
create or replace function public.add_recipe_to_shopping_list(
  p_recipe_id uuid,
  p_library_id uuid,
  p_servings integer default null,
  p_skip_pantry boolean default true
)
returns integer
language plpgsql
volatile
set search_path = public, pg_temp
as $$
declare
  v_base integer;
  v_scale numeric;
  v_added integer := 0;
begin
  if not public.is_library_member(p_library_id) then
    raise exception 'not a member of library %', p_library_id
      using errcode = 'insufficient_privilege';
  end if;

  select base_servings into v_base
    from public.recipes
   where id = p_recipe_id;
  if v_base is null then
    raise exception 'recipe % is not visible to the caller', p_recipe_id
      using errcode = 'insufficient_privilege';
  end if;

  v_scale := coalesce(p_servings, v_base)::numeric / v_base::numeric;

  insert into public.ingredients (library_id, name, grocery_category, default_unit)
  select p_library_id, i.name, i.grocery_category, i.default_unit
    from public.recipe_ingredients ri
    join public.ingredients i on i.id = ri.ingredient_id
   where ri.recipe_id = p_recipe_id
     and not ri.is_optional
     and i.library_id is not null
     and i.library_id <> p_library_id
  on conflict do nothing;

  with resolved as (
    select case
             when i.library_id is null or i.library_id = p_library_id then i.id
             else local_i.id
           end as ingredient_id,
           ri.quantity, ri.unit, i.grocery_category
      from public.recipe_ingredients ri
      join public.ingredients i on i.id = ri.ingredient_id
      left join public.ingredients local_i
        on local_i.library_id = p_library_id
       and lower(local_i.name) = lower(i.name)
     where ri.recipe_id = p_recipe_id and not ri.is_optional
  ),
  needed as (
    select r.ingredient_id, round(r.quantity * v_scale, 3) as quantity,
           r.unit, r.grocery_category
      from resolved r
     where not p_skip_pantry
        or not exists (
          select 1 from public.pantry_items pi
           where pi.library_id = p_library_id
             and pi.ingredient_id = r.ingredient_id
             and pi.quantity > 0
        )
  ),
  merged as (
    update public.shopping_list_items sli
       set quantity = sli.quantity + n.quantity,
           is_checked = false
      from needed n
     where sli.library_id = p_library_id
       and sli.ingredient_id = n.ingredient_id
       and sli.unit = n.unit
    returning n.ingredient_id
  ),
  inserted as (
    insert into public.shopping_list_items (
      library_id, ingredient_id, grocery_category, quantity, unit, added_by
    )
    select p_library_id, n.ingredient_id, n.grocery_category, n.quantity,
           n.unit, (select auth.uid())
      from needed n
     where n.ingredient_id not in (select ingredient_id from merged)
    returning 1
  )
  select (select count(*) from merged) + (select count(*) from inserted)
    into v_added;

  return v_added;
end;
$$;
