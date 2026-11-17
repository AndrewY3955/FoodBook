-- Run against the fresh seeded test database only. All fixtures roll back.
\set ON_ERROR_STOP on
begin;

insert into public.ingredients (id, library_id, name, grocery_category, default_unit)
select 'aaaaaaa1-0000-4000-8000-000000000101', id, 'Public test seasoning', 'spices', 'tsp'
  from public.libraries where name = 'Rivera Family Cookbook';
insert into public.ingredients (id, library_id, name, grocery_category, default_unit)
select 'aaaaaaa1-0000-4000-8000-000000000102', id, 'Private test seasoning', 'spices', 'tsp'
  from public.libraries where name = 'Rivera Family Cookbook';
insert into public.recipe_ingredients
  (recipe_id, library_id, ingredient_id, quantity, unit, note, is_optional, sort_order)
select 'aaaaaaa1-0000-4000-8000-000000000001', id,
       'aaaaaaa1-0000-4000-8000-000000000101', 0.5, 'tsp', 'ground', false, 99
  from public.libraries where name = 'Rivera Family Cookbook';

set role anon;
do $$
begin
  if not exists (select 1 from public.ingredients where name = 'Ground Cinnamon' and library_id is null) then
    raise exception 'anonymous users cannot read the shared seasoning catalog';
  end if;
  if not exists (select 1 from public.ingredients where name = 'Public test seasoning') then
    raise exception 'anonymous users cannot read a public recipe ingredient';
  end if;
  if exists (select 1 from public.ingredients where name = 'Private test seasoning') then
    raise exception 'anonymous users can read an unrelated private ingredient';
  end if;
end;
$$;
reset role;

select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', false);
set role authenticated;
do $$
declare
  v_library uuid;
  v_fork uuid;
begin
  if not exists (select 1 from public.ingredients where name = 'Public test seasoning') then
    raise exception 'other users cannot read a public recipe ingredient';
  end if;
  if exists (select 1 from public.ingredients where name = 'Private test seasoning') then
    raise exception 'other users can read an unrelated private ingredient';
  end if;

  select id into strict v_library from public.libraries where name = 'Cara''s Cookbook';
  perform public.add_recipe_to_shopping_list(
    'aaaaaaa1-0000-4000-8000-000000000001', v_library, 2, false
  );
  if not exists (
    select 1
      from public.shopping_list_items sli
      join public.ingredients i on i.id = sli.ingredient_id
     where sli.library_id = v_library and i.library_id = v_library
       and i.name = 'Public test seasoning' and sli.quantity = 0.25
       and sli.unit = 'tsp'
  ) then
    raise exception 'shopping list did not include the scaled custom seasoning';
  end if;

  v_fork := public.fork_recipe('aaaaaaa1-0000-4000-8000-000000000001', v_library);
  if not exists (
    select 1
      from public.recipe_ingredients ri
      join public.ingredients i on i.id = ri.ingredient_id
     where ri.recipe_id = v_fork and i.name = 'Public test seasoning'
       and i.library_id = v_library and ri.quantity = 0.5 and ri.unit = 'tsp'
       and ri.note = 'ground' and not ri.is_optional and ri.sort_order = 99
  ) then
    raise exception 'fork did not copy the custom ingredient into the destination library';
  end if;

  perform public.fork_recipe('aaaaaaa1-0000-4000-8000-000000000001', v_library);
  if (select count(*) from public.ingredients
       where library_id = v_library and name = 'Public test seasoning') <> 1 then
    raise exception 'repeated forks did not reuse the destination ingredient';
  end if;

end;
$$;
reset role;

update public.recipes set is_public = false
 where id = 'aaaaaaa1-0000-4000-8000-000000000001';
set role anon;
do $$
begin
  if exists (select 1 from public.ingredients where name = 'Public test seasoning') then
    raise exception 'unpublished recipe still exposes its custom ingredient';
  end if;
end;
$$;
reset role;
rollback;
\echo 'PASS  shared seasonings visibility and fork'
