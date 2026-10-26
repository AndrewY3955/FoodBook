-- =====================================================================
-- rls_negative_control.sql
--
-- Run with:  ./tests/run_tests.sh
--
-- Do NOT invoke this file directly against a used database. Section 8c
-- commits rows, so the section 1 counts only hold against a fresh seed.
-- run_tests.sh rebuilds first for exactly that reason.
-- Every line of output begins PASS or FAIL. Any FAIL is a real hole.
--
-- The suite is built around the idea that a policy which has only ever
-- been tested with the legitimate user is untested. For each gate there
-- is a positive control (the right user gets the row) AND a negative
-- control (the wrong user does not). Section 3 goes further and turns a
-- gate off on purpose to confirm the test can actually observe a breach
-- — a test that passes with the lock removed is measuring nothing.
--
-- Identities (fixed by seed.sql):
--   Ana  11111111-1111-4111-8111-111111111111  owner,  Rivera
--   Ben  22222222-2222-4222-8222-222222222222  member, Rivera + own
--   Cara 33333333-3333-4333-8333-333333333333  owner,  unrelated
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off
\pset tuples_only on
\pset format unaligned

create schema if not exists test;

-- --- assertion helpers -----------------------------------------------
create or replace function test.eq(p_label text, p_actual anyelement, p_expected anyelement)
returns text language plpgsql as $$
begin
  if p_actual is not distinct from p_expected then
    return 'PASS  ' || p_label;
  end if;
  return 'FAIL  ' || p_label || '   expected=' || coalesce(p_expected::text, 'NULL')
         || ' actual=' || coalesce(p_actual::text, 'NULL');
end $$;

-- Asserts a statement is REFUSED by the database (policy or constraint).
-- If the statement is allowed, its effect is rolled back before reporting.
create or replace function test.denied(p_label text, p_sql text)
returns text language plpgsql as $$
begin
  begin
    execute p_sql;
    raise exception 'TEST_UNDO';
  exception
    when others then
      if sqlerrm = 'TEST_UNDO' then
        return 'FAIL  ' || p_label || '   statement was ALLOWED';
      end if;
      return 'PASS  ' || p_label || '   blocked [' || sqlstate || ']';
  end;
end $$;

-- Asserts a statement is allowed and touches exactly N rows.
create or replace function test.affects(p_label text, p_sql text, p_expected bigint)
returns text language plpgsql as $$
declare v_n bigint;
begin
  begin
    execute p_sql;
    get diagnostics v_n = row_count;
    raise exception 'TEST_UNDO_%', v_n;
  exception
    when others then
      if sqlerrm like 'TEST_UNDO_%' then
        v_n := substring(sqlerrm from 'TEST_UNDO_(.*)')::bigint;
        if v_n = p_expected then
          return 'PASS  ' || p_label || '   rows=' || v_n;
        end if;
        return 'FAIL  ' || p_label || '   expected rows=' || p_expected || ' actual=' || v_n;
      end if;
      return 'FAIL  ' || p_label || '   unexpected error [' || sqlstate || '] ' || sqlerrm;
  end;
end $$;

create or replace function test.library(p_name text)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.libraries where name = p_name;
$$;

create or replace function test.recipe(p_title text)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.recipes where title = p_title;
$$;

grant usage on schema test to anon, authenticated;
grant execute on all functions in schema test to anon, authenticated;

\echo ''
\echo '================ 1. POSITIVE CONTROLS (Ana, Rivera) ================'

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

select test.eq('1.1  Ana sees her own library',
  (select count(*) from public.libraries), 1::bigint);

select test.eq('1.2  Ana sees both Rivera members',
  (select count(*) from public.library_members), 2::bigint);

select test.eq('1.3  Ana sees 3 Rivera recipes',
  (select count(*) from public.recipes where library_id = test.library('Rivera Family Cookbook')), 3::bigint);

select test.eq('1.4  Ana sees the full Rivera pantry',
  (select count(*) from public.pantry_items), 10::bigint);

select test.eq('1.5  Ana sees the Rivera shopping list',
  (select count(*) from public.shopping_list_items), 7::bigint);

select test.eq('1.6  Ana sees 4 meal plan entries',
  (select count(*) from public.meal_plan_entries), 4::bigint);

select test.eq('1.7  Ana sees Rivera tags only',
  (select count(*) from public.tags), 3::bigint);

select test.eq('1.8  Ana can read the global ingredient catalog',
  (select count(*) from public.ingredients where library_id is null), 33::bigint);

select test.eq('1.9  Ana sees Ben''s profile (shared library)',
  (select count(*) from public.profiles), 2::bigint);

\echo ''
\echo '================ 2. NEGATIVE CONTROLS (cross-tenant) ================'
\echo '---- 2a. Cara must not reach anything belonging to Rivera ----'

reset role;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

select test.eq('2.1  Cara sees ZERO Rivera pantry rows',
  (select count(*) from public.pantry_items
    where library_id = test.library('Rivera Family Cookbook')), 0::bigint);

select test.eq('2.2  Cara sees ZERO Rivera shopping rows',
  (select count(*) from public.shopping_list_items
    where library_id = test.library('Rivera Family Cookbook')), 0::bigint);

select test.eq('2.3  Cara sees ZERO Rivera meal plan rows',
  (select count(*) from public.meal_plan_entries
    where library_id = test.library('Rivera Family Cookbook')), 0::bigint);

select test.eq('2.4  Cara sees ZERO Rivera tags',
  (select count(*) from public.tags
    where library_id = test.library('Rivera Family Cookbook')), 0::bigint);

select test.eq('2.5  Cara cannot see the PRIVATE Rivera recipes',
  (select count(*) from public.recipes
    where library_id = test.library('Rivera Family Cookbook') and not is_public), 0::bigint);

select test.eq('2.6  Cara CAN see the one PUBLIC Rivera recipe',
  (select count(*) from public.recipes
    where library_id = test.library('Rivera Family Cookbook') and is_public), 1::bigint);

select test.eq('2.7  Cara cannot see steps of a private Rivera recipe',
  (select count(*) from public.recipe_steps
    where recipe_id = test.recipe('Winter Root Vegetable Tray Bake')), 0::bigint);

select test.eq('2.8  Cara cannot see Ana''s profile',
  (select count(*) from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'), 0::bigint);

select test.eq('2.9  Cara cannot enumerate Rivera membership',
  (select count(*) from public.library_members
    where library_id = test.library('Rivera Family Cookbook')), 0::bigint);

\echo '---- 2b. Cara must not WRITE into Rivera ----'

select test.denied('2.10 INSERT pantry row into Rivera',
  format($q$insert into public.pantry_items (library_id, ingredient_id, quantity, unit)
           values (%L, (select id from public.ingredients where library_id is null limit 1), 1, 'unit')$q$,
         test.library('Rivera Family Cookbook')));

select test.denied('2.11 INSERT recipe into Rivera',
  format($q$insert into public.recipes (library_id, created_by, title)
           values (%L, '33333333-3333-4333-8333-333333333333', 'Trojan Recipe')$q$,
         test.library('Rivera Family Cookbook')));

select test.denied('2.12 INSERT shopping row into Rivera',
  format($q$insert into public.shopping_list_items (library_id, custom_name, grocery_category)
           values (%L, 'Injected', 'other')$q$,
         test.library('Rivera Family Cookbook')));

select test.denied('2.13 INSERT membership for self into Rivera',
  format($q$insert into public.library_members (library_id, user_id, member_role)
           values (%L, '33333333-3333-4333-8333-333333333333', 'owner')$q$,
         test.library('Rivera Family Cookbook')));

-- UPDATE and DELETE are filtered by USING rather than refused, so the
-- correct assertion is "touched zero rows", not "raised an error".
select test.affects('2.14 UPDATE of Rivera pantry touches nothing',
  format($q$update public.pantry_items set quantity = 999
             where library_id = %L$q$, test.library('Rivera Family Cookbook')), 0::bigint);

select test.affects('2.15 DELETE of Rivera recipes touches nothing',
  format($q$delete from public.recipes where library_id = %L$q$,
         test.library('Rivera Family Cookbook')), 0::bigint);

select test.affects('2.16 UPDATE of public recipe by non-member touches nothing',
  format($q$update public.recipes set title = 'Defaced' where id = %L$q$,
         test.recipe('Weekend Shakshuka')), 0::bigint);

\echo '---- 2d. library-claim bootstrap (the path that failed first time) ----'

-- Fixture: an empty library created by Ana, with no members at all.
reset role;
insert into public.libraries (id, name, created_by)
values ('99999999-9999-4999-8999-999999999999', 'Ana Orphan Cookbook',
        '11111111-1111-4111-8111-111111111111')
on conflict (id) do nothing;

select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

select test.denied('2.19 Cara cannot claim an empty library she did not create',
  $q$insert into public.library_members (library_id, user_id, member_role)
     values ('99999999-9999-4999-8999-999999999999',
             '33333333-3333-4333-8333-333333333333', 'owner')$q$);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

select test.affects('2.20 Ana CAN claim the empty library she created',
  $q$insert into public.library_members (library_id, user_id, member_role)
     values ('99999999-9999-4999-8999-999999999999',
             '11111111-1111-4111-8111-111111111111', 'owner')$q$, 1::bigint);

select test.denied('2.21 Ana cannot claim a library that already has members',
  format($q$insert into public.library_members (library_id, user_id, member_role)
           values (%L, '11111111-1111-4111-8111-111111111111', 'owner')$q$,
         test.library('Cara''s Cookbook')));

select test.denied('2.22 bootstrap refuses any role other than owner',
  format($q$insert into public.library_members (library_id, user_id, member_role)
           values (%L, '11111111-1111-4111-8111-111111111111', 'member')$q$,
         '99999999-9999-4999-8999-999999999999'));

\echo '---- 2c. Tenant-hopping: rewriting a row into another library ----'

reset role;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

-- Ana owns this row, so USING passes. WITH CHECK must still stop her
-- from moving it into Cara's library. A policy written with USING only
-- would let this through.
select test.denied('2.17 Ana cannot move her recipe into Cara''s library',
  format($q$update public.recipes set library_id = %L where id = %L$q$,
         test.library('Cara''s Cookbook'), test.recipe('Weekend Shakshuka')));

select test.denied('2.18 Ana cannot create a recipe attributed to Cara',
  format($q$insert into public.recipes (library_id, created_by, title)
           values (%L, '33333333-3333-4333-8333-333333333333', 'Forged Author')$q$,
         test.library('Rivera Family Cookbook')));

\echo ''
\echo '================ 3. GATE-BREAK CONTROL ================'
\echo 'Turn RLS off on pantry_items on purpose. Cara must then succeed.'
\echo 'If she still sees nothing, the tests above prove nothing.'

reset role;
alter table public.pantry_items disable row level security;

select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

select test.eq('3.1  WITH GATE REMOVED Cara reaches Rivera pantry (breach is observable)',
  (select count(*) > 0 from public.pantry_items
    where library_id = test.library('Rivera Family Cookbook')), true);

reset role;
alter table public.pantry_items enable row level security;
alter table public.pantry_items force row level security;

select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

select test.eq('3.2  GATE RESTORED Cara reaches nothing again',
  (select count(*) from public.pantry_items
    where library_id = test.library('Rivera Family Cookbook')), 0::bigint);

\echo ''
\echo '================ 4. ANONYMOUS ROLE ================'

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;

select test.eq('4.1  anon sees only public recipes',
  (select count(*) from public.recipes), 1::bigint);

select test.eq('4.2  anon sees zero pantry rows',
  (select count(*) from public.pantry_items), 0::bigint);

select test.eq('4.3  anon sees zero shopping rows',
  (select count(*) from public.shopping_list_items), 0::bigint);

select test.eq('4.4  anon sees zero meal plan rows',
  (select count(*) from public.meal_plan_entries), 0::bigint);

select test.eq('4.5  anon sees zero profiles',
  (select count(*) from public.profiles), 0::bigint);

select test.eq('4.6  anon sees zero libraries',
  (select count(*) from public.libraries), 0::bigint);

select test.eq('4.7  anon sees zero tags',
  (select count(*) from public.tags), 0::bigint);

select test.eq('4.8  anon CAN read the global ingredient catalog',
  (select count(*) > 0 from public.ingredients), true);

select test.eq('4.9  anon sees zero library-private ingredients',
  (select count(*) from public.ingredients where library_id is not null), 0::bigint);

select test.denied('4.10 anon cannot insert a recipe',
  $q$insert into public.recipes (library_id, title) values (gen_random_uuid(), 'anon write')$q$);

select test.denied('4.11 anon cannot insert an ingredient',
  $q$insert into public.ingredients (name) values ('anon ingredient')$q$);

\echo ''
\echo '================ 5. DENORMALISATION INTEGRITY ================'
\echo 'Child rows carry their own library id. Prove it cannot be forged.'

reset role;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

-- Cara stamps her OWN library id on a step pointing at a Rivera recipe.
-- The WITH CHECK on recipe_steps would pass on the forged column alone;
-- the sync trigger overwrites it with the parent's library, after which
-- the policy rejects the row.
select test.denied('5.1  Cara cannot attach a step to a Rivera recipe',
  format($q$insert into public.recipe_steps (recipe_id, library_id, step_number, instruction)
           values (%L, %L, 99, 'Injected step')$q$,
         test.recipe('Weekend Shakshuka'), test.library('Cara''s Cookbook')));

select test.denied('5.2  Cara cannot attach an ingredient to a Rivera recipe',
  format($q$insert into public.recipe_ingredients (recipe_id, library_id, ingredient_id, quantity, unit)
           values (%L, %L, (select id from public.ingredients where library_id is null limit 1), 1, 'unit')$q$,
         test.recipe('Weekend Shakshuka'), test.library('Cara''s Cookbook')));

reset role;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

select test.denied('5.3  Ana cannot plan a meal against Cara''s private recipe',
  format($q$insert into public.meal_plan_entries (library_id, recipe_id, plan_date, meal_type)
           values (%L, %L, current_date, 'dinner')$q$,
         test.library('Rivera Family Cookbook'), test.recipe('Cara''s Private Chilli')));

select test.denied('5.4  Ana cannot use a private ingredient from another library',
  format($q$insert into public.ingredients (library_id, name) values (%L, 'Sneaky')$q$,
         test.library('Cara''s Cookbook')));

\echo ''
\echo '================ 6. URL / XSS BOUNDARY ================'
\echo 'Frontend sanitising is bypassable. These run at the database.'

select test.denied('6.1  javascript: URL rejected',
  format($q$update public.recipes set external_video_url = 'javascript:alert(1)' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

select test.denied('6.2  data: URL rejected',
  format($q$update public.recipes set external_video_url = 'data:text/html;base64,PHNjcmlwdD4=' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

select test.denied('6.3  plain http rejected',
  format($q$update public.recipes set external_video_url = 'http://example.com/v' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

select test.denied('6.4  protocol-relative URL rejected',
  format($q$update public.recipes set external_video_url = '//evil.example/v' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

select test.denied('6.5  quote-breakout payload rejected',
  format($q$update public.recipes set external_video_url = 'https://a.test/"><script>alert(1)</script>' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

select test.denied('6.6  whitespace-smuggled URL rejected',
  format($q$update public.recipes set external_video_url = 'https://a.test/ onerror=alert(1)' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

select test.denied('6.7  credentials-in-authority URL rejected',
  format($q$update public.recipes set external_video_url = 'https://user:pass@evil.test/v' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

select test.affects('6.8  legitimate https URL accepted',
  format($q$update public.recipes set external_video_url = 'https://www.youtube.com/watch?v=abc123' where id = %L$q$,
         test.recipe('Weekend Shakshuka')), 1::bigint);

select test.denied('6.9  cover path outside the pinned layout rejected',
  format($q$update public.recipes set cover_image_path = '../../etc/passwd' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

select test.denied('6.10 cover path in another library''s prefix is still a valid SHAPE',
  format($q$update public.recipes set cover_image_path = 'not-a-uuid/also-not/cover.jpg' where id = %L$q$,
         test.recipe('Weekend Shakshuka')));

\echo ''
\echo '================ 7. STORAGE OBJECT POLICIES ================'

-- Fixtures. seed.sql sets recipes.cover_image_path but cannot create
-- storage objects (uploads go through the storage service, not SQL), so
-- the objects are planted here as the platform would have created them:
-- one under a PUBLIC recipe, one under a PRIVATE recipe.
reset role;
insert into storage.objects (bucket_id, name, owner)
values
  ('recipe-covers',
   test.library('Rivera Family Cookbook')::text || '/' || test.recipe('Weekend Shakshuka')::text || '/cover.jpg',
   '11111111-1111-4111-8111-111111111111'),
  ('recipe-covers',
   test.library('Rivera Family Cookbook')::text || '/' || test.recipe('Summer Panzanella')::text || '/cover.jpg',
   '22222222-2222-4222-8222-222222222222')
on conflict do nothing;

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

select test.eq('7.0  Ana sees both Rivera cover objects',
  (select count(*) from storage.objects), 2::bigint);

select test.affects('7.1  Ana can upload a cover under Rivera''s prefix',
  format($q$insert into storage.objects (bucket_id, name, owner)
           values ('recipe-covers', %L, '11111111-1111-4111-8111-111111111111')$q$,
         test.library('Rivera Family Cookbook')::text || '/' || test.recipe('Winter Root Vegetable Tray Bake')::text || '/cover.jpg'),
  1::bigint);

select test.denied('7.2  Ana cannot upload under Cara''s prefix',
  format($q$insert into storage.objects (bucket_id, name, owner)
           values ('recipe-covers', %L, '11111111-1111-4111-8111-111111111111')$q$,
         test.library('Cara''s Cookbook')::text || '/' || test.recipe('Cara''s Private Chilli')::text || '/cover.jpg'));

select test.denied('7.3  Ana cannot upload at an unstructured key',
  $q$insert into storage.objects (bucket_id, name, owner)
     values ('recipe-covers', 'anything.jpg', '11111111-1111-4111-8111-111111111111')$q$);

select test.denied('7.4  Ana cannot forge another user as object owner',
  format($q$insert into storage.objects (bucket_id, name, owner)
           values ('recipe-covers', %L, '33333333-3333-4333-8333-333333333333')$q$,
         test.library('Rivera Family Cookbook')::text || '/' || gen_random_uuid()::text || '/cover.jpg'));

reset role;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

select test.eq('7.5  Cara CAN see the public recipe''s cover object',
  (select count(*) from storage.objects
    where name like '%' || test.recipe('Weekend Shakshuka')::text || '%'), 1::bigint);

select test.eq('7.6  Cara CANNOT see a private Rivera cover object',
  (select count(*) from storage.objects
    where name like '%' || test.recipe('Summer Panzanella')::text || '%'), 0::bigint);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;

select test.eq('7.7  anon sees only the public cover',
  (select count(*) from storage.objects), 1::bigint);

\echo ''
\echo '================ 8. ENGINES ================'

reset role;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

select test.eq('8.1  Shakshuka pantry match = 83% (5 of 6 required)',
  (select match_pct from public.pantry_match(test.library('Rivera Family Cookbook')) where title = 'Weekend Shakshuka'),
  83::numeric);

select test.eq('8.2  Tray bake pantry match = 80% (4 of 5 required)',
  (select match_pct from public.pantry_match(test.library('Rivera Family Cookbook')) where title = 'Winter Root Vegetable Tray Bake'),
  80::numeric);

select test.eq('8.3  optional ingredients excluded from the denominator',
  (select required_count from public.pantry_match(test.library('Rivera Family Cookbook')) where title = 'Weekend Shakshuka'),
  6);

select test.eq('8.4  pantry_match never leaks another library''s recipe',
  (select count(*) from public.pantry_match(test.library('Rivera Family Cookbook')) where title = 'Cara''s Private Chilli'),
  0::bigint);

select test.eq('8.5  pantry_match honours the meal_type filter',
  (select count(*) from public.pantry_match(test.library('Rivera Family Cookbook'), 0, 'dinner')),
  1::bigint);

select test.eq('8.6  pantry_match honours the minimum-percentage floor',
  (select count(*) from public.pantry_match(test.library('Rivera Family Cookbook'), 80)),
  2::bigint);

select test.eq('8.7  anonymous cook-time average over 4 logs',
  (select avg_cook_minutes from public.recipe_cook_time_stats where recipe_id = test.recipe('Weekend Shakshuka')),
  39);

\echo '---- 8b. fork (text-only) ----'

reset role;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

select test.eq('8.8  Cara can fork the PUBLIC recipe into her own library',
  (select count(*) from public.fork_recipe(test.recipe('Weekend Shakshuka'), test.library('Cara''s Cookbook'))),
  1::bigint);

select test.eq('8.9  the fork carried its steps across',
  (select count(*) from public.recipe_steps rs
     join public.recipes r on r.id = rs.recipe_id
    where r.library_id = test.library('Cara''s Cookbook') and r.import_source = 'fork'),
  6::bigint);

select test.eq('8.10 the fork is private by default',
  (select bool_and(not is_public) from public.recipes
    where library_id = test.library('Cara''s Cookbook') and import_source = 'fork'),
  true);

select test.eq('8.11 the fork carries NO cover image (text-only)',
  (select bool_and(cover_image_path is null) from public.recipes
    where library_id = test.library('Cara''s Cookbook') and import_source = 'fork'),
  true);

select test.denied('8.12 Cara cannot fork a PRIVATE Rivera recipe',
  format($q$select public.fork_recipe(%L, %L)$q$,
         test.recipe('Summer Panzanella'), test.library('Cara''s Cookbook')));

select test.denied('8.13 Cara cannot fork INTO a library she does not belong to',
  format($q$select public.fork_recipe(%L, %L)$q$,
         test.recipe('Weekend Shakshuka'), test.library('Rivera Family Cookbook')));

\echo '---- 8c. shopping list aggregation ----'

reset role;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

-- Panzanella needs 6; the pantry covers only olive oil, so 5 are missing.
select test.eq('8.14 aggregation touches the 5 ingredients the pantry lacks',
  (select public.add_recipe_to_shopping_list(test.recipe('Summer Panzanella'), test.library('Rivera Family Cookbook'), 4)),
  5);

select test.eq('8.15 quantities scaled 2 -> 4 servings (tomatoes 4 -> 8)',
  (select sli.quantity from public.shopping_list_items sli
     join public.ingredients i on i.id = sli.ingredient_id
    where sli.library_id = test.library('Rivera Family Cookbook')
      and i.name = 'Vine Tomato'),
  14.000::numeric);   -- 6 already on the list + 8 from the scaled recipe

select test.denied('8.16 aggregation refuses a library the caller is not in',
  format($q$select public.add_recipe_to_shopping_list(%L, %L)$q$,
         test.recipe('Weekend Shakshuka'), test.library('Cara''s Cookbook')));

\echo ''
\echo '================ 9. COVERAGE AUDIT ================'
\echo 'Any public table without RLS, or with RLS but no policy, is listed.'

reset role;

select coalesce(
  (select string_agg('FAIL  9.1  RLS NOT ENABLED on ' || c.relname, E'\n')
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  'PASS  9.1  every public table has RLS enabled');

select coalesce(
  (select string_agg('FAIL  9.2  RLS NOT FORCED on ' || c.relname, E'\n')
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity and not c.relforcerowsecurity),
  'PASS  9.2  every public table forces RLS for its owner too');

select coalesce(
  (select string_agg('FAIL  9.3  ZERO policies on ' || c.relname, E'\n')
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
      and not exists (select 1 from pg_policy p where p.polrelid = c.oid)),
  'PASS  9.3  every RLS-enabled table carries at least one policy');

select coalesce(
  (select string_agg('FAIL  9.4  unqualified policy (applies to PUBLIC role): '
                     || c.relname || '.' || p.polname, E'\n')
     from pg_policy p
     join pg_class c on c.oid = p.polrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'storage') and p.polroles = '{0}'),
  'PASS  9.4  every policy names its role explicitly');

select coalesce(
  (select string_agg('FAIL  9.5  SECURITY DEFINER without pinned search_path: ' || p.proname, E'\n')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%')),
  'PASS  9.5  every SECURITY DEFINER function pins search_path');

select coalesce(
  (select string_agg('FAIL  9.6  anon holds write grant on ' || table_name || ' (' || privilege_type || ')', E'\n')
     from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  'PASS  9.6  anon holds no write grant anywhere in public');


\echo ''
\echo '================ 10. FILTER-INJECTION BACKSTOP ================'
\echo 'Simulate a widened WHERE clause, as an attacker who succeeded in'
\echo 'injecting one. RLS is applied after the filter, so it must hold.'

reset role;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

-- An injected `or true` is the strongest possible widening: it removes
-- the tenant predicate entirely. If RLS is the real control, the result
-- is still zero foreign rows.
select test.eq('10.1 injected OR TRUE cannot reach Rivera pantry',
  (select count(*) from public.pantry_items
    where library_id = test.library('Rivera Family Cookbook') or true), 1::bigint);

select test.eq('10.2 injected OR TRUE cannot reach Rivera shopping list',
  (select count(*) from public.shopping_list_items where true), 0::bigint);

select test.eq('10.3 injected OR TRUE cannot reach Rivera meal plan',
  (select count(*) from public.meal_plan_entries where true), 0::bigint);

-- Stated as the security property rather than as a row count: no
-- foreign PRIVATE recipe is reachable, however the filter is widened.
-- (A raw count here would be 3 at this point in the run -- Cara's own
-- recipe, the fork section 8b committed into her library, and the one
-- public recipe -- all of which she is entitled to see.)
select test.eq('10.4 injected OR TRUE reaches no foreign private recipe',
  (select count(*) from public.recipes
    where true
      and not is_public
      and library_id <> test.library('Cara''s Cookbook')), 0::bigint);

select test.eq('10.5 injected OR TRUE reaches no foreign recipe steps',
  (select count(*) from public.recipe_steps rs
    where true
      and rs.library_id <> test.library('Cara''s Cookbook')
      and not public.recipe_is_public(rs.recipe_id)), 0::bigint);

select test.eq('10.6 injected OR TRUE cannot enumerate profiles',
  (select count(*) from public.profiles where true), 1::bigint);

-- A wildcard smuggled into a LIKE pattern widens the match but still
-- cannot cross the tenant boundary.
select test.eq('10.7 smuggled % wildcard stays inside the tenant',
  (select count(*) from public.recipes
    where title ilike '%' and library_id = test.library('Rivera Family Cookbook')),
  1::bigint);

\echo ''
\echo '================ 11. INVITATIONS ================'

reset role;
create table if not exists test.tok (k text primary key, v text);
grant all on test.tok to anon, authenticated;

reset role;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","email":"ana@example.com"}', false);
set role authenticated;

insert into test.tok
  select 'open', token from public.create_library_invitation(test.library('Rivera Family Cookbook'), 'member');
insert into test.tok
  select 'bound', token from public.create_library_invitation(
    test.library('Rivera Family Cookbook'), 'member', 'Dana@Example.com');
insert into test.tok
  select 'revoked', token from public.create_library_invitation(test.library('Rivera Family Cookbook'));

select test.eq('11.1 admin can create an invitation',
  (select count(*) from public.library_invitations), 3::bigint);
select test.eq('11.2 only the hash is stored (token column does not exist)',
  (select count(*) from information_schema.columns
    where table_name = 'library_invitations' and column_name = 'token'), 0::bigint);
select test.denied('11.3 direct INSERT into invitations is refused',
  format($q$insert into public.library_invitations (library_id, token_hash, expires_at)
            values (%L, '\x00', now() + interval '1 day')$q$, test.library('Rivera Family Cookbook')));
select test.denied('11.4 owner role cannot be invited',
  format($q$select public.create_library_invitation(%L, 'owner')$q$, test.library('Rivera Family Cookbook')));
select test.denied('11.5 excessive expiry is refused',
  format($q$select public.create_library_invitation(%L, 'member', null, 100000)$q$,
         test.library('Rivera Family Cookbook')));
select test.denied('11.6 token_hash is not readable',
  $q$select token_hash from public.library_invitations$q$);

select public.revoke_library_invitation(
  (select i.id from public.library_invitations i
    where i.accepted_at is null and i.revoked_at is null and i.invited_email is null
    order by i.created_at desc, i.id limit 1));

reset role;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated","email":"cara@example.com"}', false);
set role authenticated;

select test.denied('11.7 non-member cannot create an invitation',
  format($q$select public.create_library_invitation(%L)$q$, test.library('Rivera Family Cookbook')));
select test.eq('11.8 non-member cannot list invitations',
  (select count(*) from public.library_invitations
    where library_id = test.library('Rivera Family Cookbook')), 0::bigint);
select test.denied('11.9 garbage token is refused',
  $q$select public.accept_library_invitation('nope')$q$);
select test.denied('11.10 revoked token is refused',
  $q$select public.accept_library_invitation((select v from test.tok where k = 'revoked'))$q$);
select test.denied('11.11 email-bound token refused for a different email',
  $q$select public.accept_library_invitation((select v from test.tok where k = 'bound'))$q$);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
select test.denied('11.12 anon cannot accept an invitation',
  $q$select public.accept_library_invitation((select v from test.tok where k = 'open'))$q$);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated","email":"cara@example.com"}', false);
set role authenticated;
select public.accept_library_invitation((select v from test.tok where k = 'open'));
select test.eq('11.13 valid token makes Cara a member',
  (select count(*) from public.library_members
    where library_id = test.library('Rivera Family Cookbook')
      and user_id = '33333333-3333-4333-8333-333333333333' and revoked_at is null), 1::bigint);
select test.denied('11.14 token is single-use',
  $q$select public.accept_library_invitation((select v from test.tok where k = 'open'))$q$);
select test.eq('11.15 invited member got the invited role',
  (select member_role::text from public.library_members
    where library_id = test.library('Rivera Family Cookbook')
      and user_id = '33333333-3333-4333-8333-333333333333'), 'member');
select test.denied('11.16 plain member cannot create invitations',
  format($q$select public.create_library_invitation(%L)$q$, test.library('Rivera Family Cookbook')));

reset role;

\echo ''
\echo '================ 12. LIBRARY CREATION (INSERT ... RETURNING) ================'

select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;

select test.affects('12.1 creator can insert a library and read it back (RETURNING)',
  $q$with ins as (
       insert into public.libraries (name, created_by)
       values ('Returning Test', '33333333-3333-4333-8333-333333333333') returning id)
     select id from ins$q$, 1);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

select test.eq('12.2 a stranger cannot read an unclaimed library',
  (select count(*) from public.libraries where name = 'Cara''s Cookbook'), 0::bigint);

reset role;

\echo ''
\echo '================ 13. RECIPE PRESENTATION (themes, photos, feed) ================'

create table if not exists test.r13 (k text primary key, v uuid);
grant all on test.r13 to public;

insert into test.r13
select 'pub', gen_random_uuid() union all select 'priv', gen_random_uuid();

insert into public.recipes (id, library_id, created_by, title, is_public, cuisine)
select v, test.library('Rivera Family Cookbook'), '11111111-1111-4111-8111-111111111111',
       case k when 'pub' then 'Feed Public' else 'Feed Private' end,
       k = 'pub', case k when 'pub' then 'italian' end
  from test.r13;

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;

select test.denied('13.1 unknown theme is rejected',
  format($q$update public.recipes set theme = 'neon' where id = %L$q$, (select v from test.r13 where k='pub')));
select test.denied('13.2 malformed accent colour is rejected',
  format($q$update public.recipes set accent_color = 'red' where id = %L$q$, (select v from test.r13 where k='pub')));
select test.denied('13.3 unknown cuisine is rejected',
  format($q$update public.recipes set cuisine = 'martian' where id = %L$q$, (select v from test.r13 where k='pub')));
select test.affects('13.4 member can set theme, accent and cuisine',
  format($q$update public.recipes set theme = 'night', accent_color = '#C0392B', cuisine = 'thai' where id = %L$q$,
         (select v from test.r13 where k='pub')), 1);
select test.denied('13.5 background must live at background.<ext>',
  format($q$update public.recipes set background_image_path = %L where id = %L$q$,
         test.library('Rivera Family Cookbook') || '/' || (select v from test.r13 where k='pub') || '/cover.jpg',
         (select v from test.r13 where k='pub')));
select test.affects('13.6 member can add a photo',
  format($q$insert into public.recipe_images (recipe_id, library_id, storage_path)
            values (%L, %L, %L)$q$,
         (select v from test.r13 where k='pub'), test.library('Rivera Family Cookbook'),
         test.library('Rivera Family Cookbook') || '/' || (select v from test.r13 where k='pub')
           || '/photo-' || gen_random_uuid() || '.jpg'), 1);
select test.denied('13.7 photo path must match the pinned layout',
  format($q$insert into public.recipe_images (recipe_id, library_id, storage_path)
            values (%L, %L, 'somewhere/else.jpg')$q$,
         (select v from test.r13 where k='pub'), test.library('Rivera Family Cookbook')));

reset role;
insert into public.recipe_images (recipe_id, library_id, storage_path)
select (select v from test.r13 where k='priv'), test.library('Rivera Family Cookbook'),
       test.library('Rivera Family Cookbook') || '/' || (select v from test.r13 where k='priv')
         || '/photo-' || gen_random_uuid() || '.jpg';
insert into public.recipe_images (recipe_id, library_id, storage_path)
select (select v from test.r13 where k='pub'), test.library('Rivera Family Cookbook'),
       test.library('Rivera Family Cookbook') || '/' || (select v from test.r13 where k='pub')
         || '/photo-' || gen_random_uuid() || '.jpg'
  from generate_series(1, 12);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', false);
set role authenticated;
select test.denied('13.8 a recipe holds at most 12 photos',
  format($q$insert into public.recipe_images (recipe_id, library_id, storage_path)
            values (%L, %L, %L)$q$,
         (select v from test.r13 where k='pub'), test.library('Rivera Family Cookbook'),
         test.library('Rivera Family Cookbook') || '/' || (select v from test.r13 where k='pub')
           || '/photo-' || gen_random_uuid() || '.jpg'));

reset role;
select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-4999-8999-999999999999","role":"authenticated"}', false);
set role authenticated;
select test.eq('13.9 stranger sees photos of a public recipe',
  (select count(*) > 0 from public.recipe_images where recipe_id = (select v from test.r13 where k='pub')), true);
select test.eq('13.10 stranger does not see photos of a private recipe',
  (select count(*) from public.recipe_images where recipe_id = (select v from test.r13 where k='priv')), 0::bigint);
select test.denied('13.11 stranger cannot add photos to someone else''s recipe',
  format($q$insert into public.recipe_images (recipe_id, library_id, storage_path)
            values (%L, %L, %L)$q$,
         (select v from test.r13 where k='pub'), test.library('Rivera Family Cookbook'),
         test.library('Rivera Family Cookbook') || '/' || (select v from test.r13 where k='pub')
           || '/photo-' || gen_random_uuid() || '.jpg'));
select test.eq('13.12 feed shows the public recipe to a stranger',
  (select count(*) from public.recipes where is_public and cuisine = 'italian'
     and id = (select v from test.r13 where k='pub')), 1::bigint);
select test.eq('13.13 feed hides the private recipe from a stranger',
  (select count(*) from public.recipes where id = (select v from test.r13 where k='priv')), 0::bigint);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
select test.eq('13.14 anon sees photos of a public recipe',
  (select count(*) > 0 from public.recipe_images where recipe_id = (select v from test.r13 where k='pub')), true);
select test.eq('13.15 anon sees no photos of a private recipe',
  (select count(*) from public.recipe_images where recipe_id = (select v from test.r13 where k='priv')), 0::bigint);
select test.denied('13.16 anon cannot add photos',
  format($q$insert into public.recipe_images (recipe_id, library_id, storage_path)
            values (%L, %L, %L)$q$,
         (select v from test.r13 where k='pub'), test.library('Rivera Family Cookbook'),
         test.library('Rivera Family Cookbook') || '/' || (select v from test.r13 where k='pub')
           || '/photo-' || gen_random_uuid() || '.jpg'));

reset role;

\echo ''
\echo '================ END ================'
