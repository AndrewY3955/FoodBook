-- =====================================================================
-- seed.sql
-- Deterministic test data.
--
-- Two halves:
--   PART A  global ingredient catalog — safe to run in production, it
--           is reference data the app needs to function at all.
--   PART B  demo users and their content — local/staging only.
--
-- PART B inserts directly into auth.users. That is supported for local
-- `supabase db reset` and for staging. On a hosted project the
-- supported path is the Admin API (auth.admin.createUser), because
-- direct inserts skip identity-row creation and the seeded accounts
-- cannot then sign in with a password.
--
-- The script is idempotent: re-running it is a no-op, not a duplicate.
-- =====================================================================

-- =====================================================================
-- PART A — global ingredient catalog (library_id IS NULL)
-- =====================================================================
insert into public.ingredients (library_id, name, grocery_category, default_unit) values
  (null, 'Yellow Onion',        'veggies',        'piece'),
  (null, 'Red Onion',           'veggies',        'piece'),
  (null, 'Garlic',              'veggies',        'clove'),
  (null, 'Red Bell Pepper',     'veggies',        'piece'),
  (null, 'Carrot',              'veggies',        'piece'),
  (null, 'Parsnip',             'veggies',        'piece'),
  (null, 'Potato',              'veggies',        'piece'),
  (null, 'Cucumber',            'veggies',        'piece'),
  (null, 'Vine Tomato',         'veggies',        'piece'),
  (null, 'Flat-Leaf Parsley',   'veggies',        'bunch'),
  (null, 'Basil',               'veggies',        'bunch'),
  (null, 'Rosemary',            'veggies',        'bunch'),
  (null, 'Lemon',               'fruits',         'piece'),
  (null, 'Ground Beef',         'meat',           'g'),
  (null, 'Chicken Thigh',       'meat',           'g'),
  (null, 'Large Egg',           'dairy',          'piece'),
  (null, 'Feta',                'dairy',          'g'),
  (null, 'Greek Yoghurt',       'dairy',          'g'),
  (null, 'Unsalted Butter',     'dairy',          'g'),
  (null, 'Sourdough Loaf',      'bakery',         'piece'),
  (null, 'Pita Bread',          'bakery',         'piece'),
  (null, 'Chopped Tomatoes',    'pantry_staples', 'can'),
  (null, 'Kidney Beans',        'pantry_staples', 'can'),
  (null, 'Olive Oil',           'pantry_staples', 'tbsp'),
  (null, 'Red Wine Vinegar',    'pantry_staples', 'tbsp'),
  (null, 'Chickpeas',           'pantry_staples', 'can'),
  (null, 'Long Grain Rice',     'pantry_staples', 'g'),
  (null, 'Sea Salt',            'spices',         'tsp'),
  (null, 'Black Pepper',        'spices',         'tsp'),
  (null, 'Ground Cumin',        'spices',         'tsp'),
  (null, 'Smoked Paprika',      'spices',         'tsp'),
  (null, 'Chilli Powder',       'spices',         'tsp'),
  (null, 'Bay Leaf',            'spices',         'piece')
on conflict do nothing;

-- =====================================================================
-- PART B — demo tenants and content
--
-- Cast of three, chosen so the isolation tests have something to prove:
--   Ana  — owner of the Rivera Family Cookbook
--   Ben  — member of Rivera, and owner of his own separate library
--   Cara — owner of an unrelated library, no link to Rivera at all
-- =====================================================================
do $$
declare
  v_ana        uuid := '11111111-1111-4111-8111-111111111111';
  v_ben        uuid := '22222222-2222-4222-8222-222222222222';
  v_cara       uuid := '33333333-3333-4333-8333-333333333333';

  v_rivera     uuid;
  v_ben_stove  uuid;
  v_cara_hob   uuid;

  v_shakshuka  uuid := 'aaaaaaa1-0000-4000-8000-000000000001';
  v_panzanella uuid := 'aaaaaaa1-0000-4000-8000-000000000002';
  v_traybake   uuid := 'aaaaaaa1-0000-4000-8000-000000000003';
  v_chili      uuid := 'bbbbbbb2-0000-4000-8000-000000000001';

  v_tag_quick  uuid;
  v_tag_veg    uuid;
  v_tag_batch  uuid;

  v_sugg       uuid;
  v_monday     date := date_trunc('week', current_date)::date;
begin
  -- Short-circuit if the demo set is already present.
  if exists (select 1 from auth.users where id = v_ana) then
    raise notice 'demo data already seeded; nothing to do';
    return;
  end if;

  -- --- accounts ------------------------------------------------------
  -- The on_auth_user_created trigger creates a profile, a personal
  -- library and an owner membership for each of these automatically.
  insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
  values
    (v_ana,  'ana@example.test',  now(), jsonb_build_object('display_name', 'Ana')),
    (v_ben,  'ben@example.test',  now(), jsonb_build_object('display_name', 'Ben')),
    (v_cara, 'cara@example.test', now(), jsonb_build_object('display_name', 'Cara'));

  select km.library_id into v_rivera
    from public.library_members km where km.user_id = v_ana limit 1;
  select km.library_id into v_ben_stove
    from public.library_members km where km.user_id = v_ben limit 1;
  select km.library_id into v_cara_hob
    from public.library_members km where km.user_id = v_cara limit 1;

  update public.libraries set name = 'Rivera Family Cookbook' where id = v_rivera;
  update public.libraries set name = 'Ben''s Studio Cookbook'  where id = v_ben_stove;
  update public.libraries set name = 'Cara''s Cookbook'        where id = v_cara_hob;

  -- Ben joins Rivera as a second member of the same tenant. This is the
  -- shared-library case the whole CookbookProfile model exists for.
  insert into public.library_members (library_id, user_id, member_role, invited_by)
  values (v_rivera, v_ben, 'member', v_ana);

  -- --- tags ----------------------------------------------------------
  insert into public.tags (library_id, name) values
    (v_rivera, 'Weeknight'), (v_rivera, 'Vegetarian'), (v_rivera, 'Batch Cook');

  select id into v_tag_quick from public.tags where library_id = v_rivera and lower(name) = 'weeknight';
  select id into v_tag_veg   from public.tags where library_id = v_rivera and lower(name) = 'vegetarian';
  select id into v_tag_batch from public.tags where library_id = v_rivera and lower(name) = 'batch cook';

  -- --- recipe 1: Shakshuka (public, spring) --------------------------
  insert into public.recipes (
    id, library_id, created_by, title, description, meal_type, season,
    base_servings, prep_minutes, cook_minutes, cover_image_path,
    external_video_url, import_source, is_public
  ) values (
    v_shakshuka, v_rivera, v_ana,
    'Weekend Shakshuka',
    'Eggs poached in a smoky pepper and tomato base. Cooked in one pan, eaten straight out of it.',
    'breakfast', 'spring', 4, 10, 25,
    v_rivera::text || '/' || v_shakshuka::text || '/cover.jpg',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'manual', true
  );

  insert into public.recipe_ingredients (recipe_id, library_id, ingredient_id, quantity, unit, is_optional, sort_order, note)
  select v_shakshuka, v_rivera, i.id, x.qty, x.unit, x.opt, x.ord, x.note
    from (values
      ('Olive Oil',        2::numeric, 'tbsp'::public.measure_unit, false, 1, null::text),
      ('Yellow Onion',     1,          'piece',                     false, 2, 'finely diced'),
      ('Red Bell Pepper',  2,          'piece',                     false, 3, 'sliced'),
      ('Chopped Tomatoes', 1,          'can',                       false, 4, null),
      ('Large Egg',        4,          'piece',                     false, 5, null),
      ('Smoked Paprika',   1,          'tsp',                       false, 6, null),
      ('Feta',             60,         'g',                         true,  7, 'crumbled over at the end'),
      ('Flat-Leaf Parsley',1,          'bunch',                     true,  8, null)
    ) as x(nm, qty, unit, opt, ord, note)
    join public.ingredients i on lower(i.name) = lower(x.nm) and i.library_id is null;

  insert into public.recipe_steps (recipe_id, library_id, step_number, instruction, timer_seconds) values
    (v_shakshuka, v_rivera, 1, 'Warm the olive oil in a wide pan over medium heat.', null),
    (v_shakshuka, v_rivera, 2, 'Add the onion and peppers. Cook until soft and beginning to colour.', 600),
    (v_shakshuka, v_rivera, 3, 'Stir in the smoked paprika, then the chopped tomatoes. Simmer until thickened.', 720),
    (v_shakshuka, v_rivera, 4, 'Make four wells in the sauce and crack an egg into each.', null),
    (v_shakshuka, v_rivera, 5, 'Cover and cook until the whites are set but the yolks still move.', 420),
    (v_shakshuka, v_rivera, 6, 'Scatter over the feta and parsley if using. Serve from the pan.', null);

  insert into public.recipe_tags (recipe_id, tag_id, library_id) values
    (v_shakshuka, v_tag_veg, v_rivera);

  -- --- recipe 2: Panzanella (private, summer) ------------------------
  insert into public.recipes (
    id, library_id, created_by, title, description, meal_type, season,
    base_servings, prep_minutes, cook_minutes, source_url, import_source, is_public
  ) values (
    v_panzanella, v_rivera, v_ben,
    'Summer Panzanella',
    'Stale sourdough, ripe tomatoes, and enough vinegar to wake it all up.',
    'lunch', 'summer', 2, 20, 0,
    'https://www.instagram.com/reel/C0000000000/',
    'instagram', false
  );

  insert into public.recipe_ingredients (recipe_id, library_id, ingredient_id, quantity, unit, is_optional, sort_order, note)
  select v_panzanella, v_rivera, i.id, x.qty, x.unit, x.opt, x.ord, x.note
    from (values
      ('Sourdough Loaf',    0.5::numeric, 'piece'::public.measure_unit, false, 1, 'torn, day-old'),
      ('Vine Tomato',       4,            'piece',                      false, 2, null::text),
      ('Cucumber',          1,            'piece',                      false, 3, null),
      ('Red Onion',         0.5,          'piece',                      false, 4, 'sliced paper thin'),
      ('Red Wine Vinegar',  2,            'tbsp',                       false, 5, null),
      ('Olive Oil',         3,            'tbsp',                       false, 6, null),
      ('Basil',             1,            'bunch',                      true,  7, null)
    ) as x(nm, qty, unit, opt, ord, note)
    join public.ingredients i on lower(i.name) = lower(x.nm) and i.library_id is null;

  insert into public.recipe_steps (recipe_id, library_id, step_number, instruction, timer_seconds) values
    (v_panzanella, v_rivera, 1, 'Tear the bread into rough chunks and spread on a tray to dry further.', null),
    (v_panzanella, v_rivera, 2, 'Salt the chopped tomatoes and leave them to release their juice.', 900),
    (v_panzanella, v_rivera, 3, 'Whisk the vinegar and oil into the collected tomato juice.', null),
    (v_panzanella, v_rivera, 4, 'Toss everything together and leave to sit before serving.', 600);

  insert into public.recipe_tags (recipe_id, tag_id, library_id) values
    (v_panzanella, v_tag_veg,   v_rivera),
    (v_panzanella, v_tag_quick, v_rivera);

  -- --- recipe 3: Winter tray bake (private, winter) ------------------
  insert into public.recipes (
    id, library_id, created_by, title, description, meal_type, season,
    base_servings, prep_minutes, cook_minutes, import_source, is_public
  ) values (
    v_traybake, v_rivera, v_ana,
    'Winter Root Vegetable Tray Bake',
    'One tray, one hour, no attention required after the first fifteen minutes.',
    'dinner', 'winter', 6, 15, 55,
    'manual', false
  );

  insert into public.recipe_ingredients (recipe_id, library_id, ingredient_id, quantity, unit, is_optional, sort_order, note)
  select v_traybake, v_rivera, i.id, x.qty, x.unit, x.opt, x.ord, x.note
    from (values
      ('Carrot',     4::numeric, 'piece'::public.measure_unit, false, 1, 'halved lengthways'),
      ('Parsnip',    3,          'piece',                      false, 2, null::text),
      ('Potato',     6,          'piece',                      false, 3, 'quartered'),
      ('Garlic',     6,          'clove',                      false, 4, 'skin on'),
      ('Olive Oil',  4,          'tbsp',                       false, 5, null),
      ('Rosemary',   1,          'bunch',                      true,  6, null)
    ) as x(nm, qty, unit, opt, ord, note)
    join public.ingredients i on lower(i.name) = lower(x.nm) and i.library_id is null;

  insert into public.recipe_steps (recipe_id, library_id, step_number, instruction, timer_seconds) values
    (v_traybake, v_rivera, 1, 'Heat the oven to 200C fan.', null),
    (v_traybake, v_rivera, 2, 'Toss all the vegetables with the oil and plenty of salt.', null),
    (v_traybake, v_rivera, 3, 'Roast, turning once halfway, until the edges are dark and crisp.', 3300);

  insert into public.recipe_tags (recipe_id, tag_id, library_id) values
    (v_traybake, v_tag_batch, v_rivera),
    (v_traybake, v_tag_veg,   v_rivera);

  -- --- Cara's unrelated private recipe (isolation fixture) -----------
  insert into public.recipes (
    id, library_id, created_by, title, description, meal_type, season,
    base_servings, import_source, is_public
  ) values (
    v_chili, v_cara_hob, v_cara,
    'Cara''s Private Chilli',
    'Should never be visible to anyone in the Rivera library.',
    'dinner', 'all_year', 4, 'manual', false
  );

  insert into public.recipe_ingredients (recipe_id, library_id, ingredient_id, quantity, unit, is_optional, sort_order)
  select v_chili, v_cara_hob, i.id, x.qty, x.unit, false, x.ord
    from (values
      ('Ground Beef',      500::numeric, 'g'::public.measure_unit,  1),
      ('Kidney Beans',     1,            'can',                     2),
      ('Chopped Tomatoes', 1,            'can',                     3),
      ('Yellow Onion',     1,            'piece',                   4),
      ('Chilli Powder',    2,            'tsp',                     5)
    ) as x(nm, qty, unit, ord)
    join public.ingredients i on lower(i.name) = lower(x.nm) and i.library_id is null;

  insert into public.recipe_steps (recipe_id, library_id, step_number, instruction) values
    (v_chili, v_cara_hob, 1, 'Brown the beef, add everything else, simmer for an hour.');

  -- --- Rivera pantry -------------------------------------------------
  -- Deliberately stocked so Shakshuka lands at exactly 5 of 6 required
  -- ingredients. The RLS/engine test suite asserts 83%.
  insert into public.pantry_items (library_id, ingredient_id, quantity, unit)
  select v_rivera, i.id, x.qty, x.unit
    from (values
      ('Olive Oil',       500::numeric, 'ml'::public.measure_unit),
      ('Yellow Onion',    3,            'piece'),
      ('Red Bell Pepper', 2,            'piece'),
      ('Large Egg',       10,           'piece'),
      ('Smoked Paprika',  1,            'tsp'),
      ('Sea Salt',        1,            'tsp'),
      ('Black Pepper',    1,            'tsp'),
      ('Carrot',          6,            'piece'),
      ('Potato',          8,            'piece'),
      ('Garlic',          12,           'clove')
    ) as x(nm, qty, unit)
    join public.ingredients i on lower(i.name) = lower(x.nm) and i.library_id is null;

  -- Cara's pantry, so cross-tenant reads have something to fail to find.
  insert into public.pantry_items (library_id, ingredient_id, quantity, unit)
  select v_cara_hob, i.id, 1, 'can'
    from public.ingredients i
   where i.library_id is null and lower(i.name) = 'kidney beans';

  -- --- Rivera shopping list ------------------------------------------
  insert into public.shopping_list_items (library_id, ingredient_id, grocery_category, quantity, unit, is_checked, added_by)
  select v_rivera, i.id, i.grocery_category, x.qty, x.unit, x.done, v_ana
    from (values
      ('Chopped Tomatoes', 2::numeric, 'can'::public.measure_unit,   false),
      ('Vine Tomato',      6,          'piece',                      false),
      ('Sourdough Loaf',   1,          'piece',                      false),
      ('Feta',             200,        'g',                          false),
      ('Parsnip',          3,          'piece',                      true),
      ('Greek Yoghurt',    500,        'g',                          false)
    ) as x(nm, qty, unit, done)
    join public.ingredients i on lower(i.name) = lower(x.nm) and i.library_id is null;

  -- A free-text row: the sorter must still place it under a header.
  insert into public.shopping_list_items (library_id, custom_name, grocery_category, quantity, unit, added_by)
  values (v_rivera, 'Baking parchment', 'other', 1, 'package', v_ben);

  -- --- Rivera meal plan, current week --------------------------------
  insert into public.meal_plan_entries (library_id, recipe_id, plan_date, meal_type, created_by, note) values
    (v_rivera, v_shakshuka,  v_monday + 5, 'breakfast', v_ana, 'Saturday, no rush'),
    (v_rivera, v_panzanella, v_monday + 2, 'lunch',     v_ben, null),
    (v_rivera, v_traybake,   v_monday + 3, 'dinner',    v_ana, 'Double it, freeze half'),
    (v_rivera, v_traybake,   v_monday + 6, 'dinner',    v_ana, null);

  -- --- community layer on the one public recipe ----------------------
  insert into public.substitution_suggestions (recipe_id, ingredient_id, suggestion, created_by)
  select v_shakshuka, i.id, 'Harissa paste works if you want it hotter and deeper.', v_ben
    from public.ingredients i
   where i.library_id is null and lower(i.name) = 'smoked paprika'
  returning id into v_sugg;

  insert into public.substitution_votes (suggestion_id, user_id, vote) values
    (v_sugg, v_ana,  1),
    (v_sugg, v_cara, 1);

  insert into public.cook_logs (recipe_id, cook_minutes) values
    (v_shakshuka, 38), (v_shakshuka, 45), (v_shakshuka, 31), (v_shakshuka, 41);

  raise notice 'seeded: rivera=% ben=% cara=%', v_rivera, v_ben_stove, v_cara_hob;
end
$$;
