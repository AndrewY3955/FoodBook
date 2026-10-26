-- =====================================================================
-- 0003_functions_triggers.sql
-- Security helpers, integrity triggers, and the server-side engines
-- (pantry matching, forking, shopping-list aggregation).
--
-- Every function pins `search_path` explicitly. An unpinned search_path
-- on a SECURITY DEFINER function is a privilege-escalation primitive:
-- a caller who can create objects in a schema earlier in the path can
-- shadow a table or operator the function depends on.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Generic updated_at maintenance
-- ---------------------------------------------------------------------
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists set_updated_at on public.profiles;
create trigger set_updated_at before update on public.profiles
  for each row execute function public.tg_set_updated_at();

drop trigger if exists set_updated_at on public.kitchen_profiles;
create trigger set_updated_at before update on public.kitchen_profiles
  for each row execute function public.tg_set_updated_at();

drop trigger if exists set_updated_at on public.recipes;
create trigger set_updated_at before update on public.recipes
  for each row execute function public.tg_set_updated_at();

drop trigger if exists set_updated_at on public.pantry_items;
create trigger set_updated_at before update on public.pantry_items
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Membership predicates
--
-- SECURITY DEFINER is required here, not a convenience. The RLS policy
-- on kitchen_members itself needs to ask "is this user a member?", and
-- a policy that queries its own table through the invoker's rights
-- recurses until PostgreSQL aborts with 42P17. A definer-rights
-- function reads the table with RLS bypassed and breaks the cycle.
--
-- These functions are STABLE and take the kitchen id as a parameter, so
-- the planner can hoist them out of row loops.
-- ---------------------------------------------------------------------
create or replace function public.is_kitchen_member(p_kitchen_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.kitchen_members km
     where km.kitchen_profile_id = p_kitchen_profile_id
       and km.user_id = (select auth.uid())
       and km.revoked_at is null
  );
$$;

create or replace function public.is_kitchen_admin(p_kitchen_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.kitchen_members km
     where km.kitchen_profile_id = p_kitchen_profile_id
       and km.user_id = (select auth.uid())
       and km.revoked_at is null
       and km.member_role in ('owner', 'admin')
  );
$$;

comment on function public.is_kitchen_member(uuid) is
  'Authoritative tenancy predicate for RLS. SECURITY DEFINER to avoid policy recursion on kitchen_members.';

-- ---------------------------------------------------------------------
-- Kitchen claim check.
--
-- A user who creates a kitchen must be able to insert their own owner
-- row, at a moment when they are not yet a member and so cannot pass
-- is_kitchen_admin. That bootstrap has to be narrow.
--
-- It MUST be SECURITY DEFINER. Written inline in the policy as
-- `not exists (select 1 from kitchen_members ...)`, the subquery is
-- itself filtered by the caller's RLS: a stranger cannot see the
-- existing members of someone else's kitchen, so the emptiness test
-- returns true for them and the bootstrap becomes a way to join any
-- kitchen as owner. Definer rights make the test see the real table.
--
-- Three conditions, all required: the kitchen exists, it has no members
-- at all, and the caller is the recorded creator.
-- ---------------------------------------------------------------------
create or replace function public.can_claim_kitchen(p_kitchen_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.kitchen_profiles kp
     where kp.id = p_kitchen_profile_id
       and kp.created_by = (select auth.uid())
       and not exists (
         select 1 from public.kitchen_members km
          where km.kitchen_profile_id = kp.id
       )
  );
$$;

grant execute on function public.can_claim_kitchen(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Active kitchen, read from the JWT.
--
-- This is a UX convenience for clients that belong to more than one
-- kitchen: it says which kitchen the session is currently pointed at.
-- It is deliberately NOT the security gate in 0004 — see 0006 for the
-- stricter variant and the trade-off.
-- ---------------------------------------------------------------------
create or replace function public.active_kitchen_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(
    ((select auth.jwt()) -> 'app_metadata' ->> 'active_kitchen_profile_id'),
    ''
  )::uuid;
$$;

-- ---------------------------------------------------------------------
-- Child-row tenancy integrity
--
-- recipe_ingredients, recipe_steps and recipe_tags each carry their own
-- kitchen_profile_id so RLS can filter on a single indexed column. That
-- denormalisation opens a hole: a member of kitchen A could insert a
-- child row with kitchen_profile_id = A while recipe_id points at a
-- recipe in kitchen B. The row would satisfy the child policy and
-- corrupt B's recipe.
--
-- This trigger overwrites the client-supplied value with the parent
-- recipe's kitchen, unconditionally. The client cannot choose it.
-- ---------------------------------------------------------------------
create or replace function public.tg_sync_kitchen_from_recipe()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kitchen uuid;
begin
  select r.kitchen_profile_id into v_kitchen
    from public.recipes r
   where r.id = new.recipe_id;

  if v_kitchen is null then
    raise exception 'recipe % does not exist', new.recipe_id
      using errcode = 'foreign_key_violation';
  end if;

  new.kitchen_profile_id := v_kitchen;
  return new;
end;
$$;

drop trigger if exists sync_kitchen on public.recipe_ingredients;
create trigger sync_kitchen before insert or update on public.recipe_ingredients
  for each row execute function public.tg_sync_kitchen_from_recipe();

drop trigger if exists sync_kitchen on public.recipe_steps;
create trigger sync_kitchen before insert or update on public.recipe_steps
  for each row execute function public.tg_sync_kitchen_from_recipe();

drop trigger if exists sync_kitchen on public.recipe_tags;
create trigger sync_kitchen before insert or update on public.recipe_tags
  for each row execute function public.tg_sync_kitchen_from_recipe();

-- ---------------------------------------------------------------------
-- A tag may only be attached to a recipe in the same kitchen.
-- ---------------------------------------------------------------------
create or replace function public.tg_check_tag_kitchen()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tag_kitchen uuid;
begin
  select t.kitchen_profile_id into v_tag_kitchen
    from public.tags t
   where t.id = new.tag_id;

  if v_tag_kitchen is distinct from new.kitchen_profile_id then
    raise exception 'tag % belongs to a different kitchen than recipe %', new.tag_id, new.recipe_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists check_tag_kitchen on public.recipe_tags;
create trigger check_tag_kitchen after insert or update on public.recipe_tags
  for each row execute function public.tg_check_tag_kitchen();

-- ---------------------------------------------------------------------
-- Ingredient tenancy: a recipe or pantry row may only reference a
-- global catalog ingredient or one owned by the same kitchen.
-- ---------------------------------------------------------------------
create or replace function public.tg_check_ingredient_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  if new.ingredient_id is null then
    return new;
  end if;

  select i.kitchen_profile_id into v_owner
    from public.ingredients i
   where i.id = new.ingredient_id;

  if v_owner is not null and v_owner <> new.kitchen_profile_id then
    raise exception 'ingredient % is private to another kitchen', new.ingredient_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists check_ingredient_scope on public.recipe_ingredients;
create trigger check_ingredient_scope before insert or update on public.recipe_ingredients
  for each row execute function public.tg_check_ingredient_scope();

drop trigger if exists check_ingredient_scope on public.pantry_items;
create trigger check_ingredient_scope before insert or update on public.pantry_items
  for each row execute function public.tg_check_ingredient_scope();

drop trigger if exists check_ingredient_scope on public.shopping_list_items;
create trigger check_ingredient_scope before insert or update on public.shopping_list_items
  for each row execute function public.tg_check_ingredient_scope();

-- ---------------------------------------------------------------------
-- A meal plan entry may only point at a recipe the kitchen can see.
-- ---------------------------------------------------------------------
create or replace function public.tg_check_plan_recipe_visible()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kitchen uuid;
  v_public  boolean;
begin
  select r.kitchen_profile_id, r.is_public into v_kitchen, v_public
    from public.recipes r
   where r.id = new.recipe_id;

  if v_kitchen is null then
    raise exception 'recipe % does not exist', new.recipe_id
      using errcode = 'foreign_key_violation';
  end if;

  if v_kitchen <> new.kitchen_profile_id and not v_public then
    raise exception 'recipe % is not visible to kitchen %', new.recipe_id, new.kitchen_profile_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists check_plan_recipe on public.meal_plan_entries;
create trigger check_plan_recipe before insert or update on public.meal_plan_entries
  for each row execute function public.tg_check_plan_recipe_visible();

-- ---------------------------------------------------------------------
-- New user bootstrap: profile + personal kitchen + owner membership.
-- Runs as definer because the row is created before any session exists.
-- ---------------------------------------------------------------------
create or replace function public.tg_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kitchen uuid;
  v_name    text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    split_part(new.email, '@', 1),
    'Cook'
  );

  insert into public.profiles (id, display_name)
  values (new.id, left(v_name, 64))
  on conflict (id) do nothing;

  insert into public.kitchen_profiles (name, created_by)
  values (left(v_name, 70) || '''s Kitchen', new.id)
  returning id into v_kitchen;

  insert into public.kitchen_members (kitchen_profile_id, user_id, member_role)
  values (v_kitchen, new.id, 'owner');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.tg_handle_new_user();

-- ---------------------------------------------------------------------
-- PANTRY MATCHER
--
-- SECURITY INVOKER (the default) on purpose: the function inherits the
-- caller's RLS, so it can never surface a recipe or pantry row the
-- caller could not have selected directly.
--
-- Optional ingredients are excluded from the denominator — a recipe is
-- not 60% cookable because you are missing the garnish.
-- ---------------------------------------------------------------------
create or replace function public.pantry_match(
  p_kitchen_profile_id uuid,
  p_min_pct            numeric default 0,
  p_meal_type          public.meal_type default null,
  p_season             public.season default null,
  p_limit              integer default 50
)
returns table (
  recipe_id       uuid,
  title           text,
  meal_type       public.meal_type,
  season          public.season,
  required_count  integer,
  matched_count   integer,
  match_pct       numeric
)
language sql
stable
set search_path = public, pg_temp
as $$
  with pantry as (
    select pi.ingredient_id
      from public.pantry_items pi
     where pi.kitchen_profile_id = p_kitchen_profile_id
       and pi.quantity > 0
  )
  select r.id,
         r.title,
         r.meal_type,
         r.season,
         count(*) filter (where not ri.is_optional)::integer as required_count,
         count(*) filter (where not ri.is_optional and p.ingredient_id is not null)::integer as matched_count,
         round(
           100.0 * count(*) filter (where not ri.is_optional and p.ingredient_id is not null)
                 / nullif(count(*) filter (where not ri.is_optional), 0),
           0
         ) as match_pct
    from public.recipes r
    join public.recipe_ingredients ri on ri.recipe_id = r.id
    left join pantry p on p.ingredient_id = ri.ingredient_id
   where (p_meal_type is null or r.meal_type = p_meal_type)
     and (p_season   is null or r.season in (p_season, 'all_year'))
   group by r.id, r.title, r.meal_type, r.season
  having coalesce(
           round(
             100.0 * count(*) filter (where not ri.is_optional and p.ingredient_id is not null)
                   / nullif(count(*) filter (where not ri.is_optional), 0),
             0
           ), 0) >= p_min_pct
   order by match_pct desc nulls last, r.title asc
   limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

comment on function public.pantry_match(uuid, numeric, public.meal_type, public.season, integer) is
  'Cross-references pantry inventory against recipe requirements. SECURITY INVOKER so RLS still applies.';

-- ---------------------------------------------------------------------
-- Anonymous cook-time statistics
-- ---------------------------------------------------------------------
create or replace view public.recipe_cook_time_stats
with (security_invoker = true)
as
  select r.id                                   as recipe_id,
         r.kitchen_profile_id,
         count(cl.id)::integer                  as sample_count,
         round(avg(cl.cook_minutes))::integer   as avg_cook_minutes,
         min(cl.cook_minutes)                   as min_cook_minutes,
         max(cl.cook_minutes)                   as max_cook_minutes
    from public.recipes r
    left join public.cook_logs cl on cl.recipe_id = r.id
   group by r.id, r.kitchen_profile_id;

comment on view public.recipe_cook_time_stats is
  'security_invoker=true — the view is filtered by the caller''s RLS, not the view owner''s.';

-- ---------------------------------------------------------------------
-- TEXT-ONLY FORK
--
-- Copies title, description, ingredients and steps into the caller's
-- kitchen. Deliberately does not copy cover_image_path: forks are
-- text-only per the brief, and copying the path would let a fork
-- reference an object in the source kitchen's storage prefix.
-- ---------------------------------------------------------------------
create or replace function public.fork_recipe(
  p_recipe_id          uuid,
  p_kitchen_profile_id uuid
)
returns uuid
language plpgsql
volatile
set search_path = public, pg_temp
as $$
declare
  v_new_id uuid;
begin
  if not public.is_kitchen_member(p_kitchen_profile_id) then
    raise exception 'not a member of kitchen %', p_kitchen_profile_id
      using errcode = 'insufficient_privilege';
  end if;

  -- The SELECT below is invoker-rights, so a recipe the caller cannot
  -- read simply yields no row and the fork fails closed.
  insert into public.recipes (
    kitchen_profile_id, created_by, title, description, meal_type, season,
    base_servings, prep_minutes, cook_minutes, source_url, external_video_url,
    import_source, is_public, forked_from_recipe_id
  )
  select p_kitchen_profile_id,
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
         src.id
    from public.recipes src
   where src.id = p_recipe_id
  returning id into v_new_id;

  if v_new_id is null then
    raise exception 'recipe % is not visible to the caller', p_recipe_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.recipe_ingredients (
    recipe_id, kitchen_profile_id, ingredient_id, quantity, unit, note, is_optional, sort_order
  )
  select v_new_id, p_kitchen_profile_id, ri.ingredient_id, ri.quantity, ri.unit,
         ri.note, ri.is_optional, ri.sort_order
    from public.recipe_ingredients ri
    join public.ingredients i on i.id = ri.ingredient_id
   where ri.recipe_id = p_recipe_id
     and i.kitchen_profile_id is null;  -- only globally-catalogued ingredients survive a fork

  insert into public.recipe_steps (recipe_id, kitchen_profile_id, step_number, instruction, timer_seconds)
  select v_new_id, p_kitchen_profile_id, rs.step_number, rs.instruction, rs.timer_seconds
    from public.recipe_steps rs
   where rs.recipe_id = p_recipe_id;

  return v_new_id;
end;
$$;

-- ---------------------------------------------------------------------
-- SHOPPING LIST AGGREGATION
--
-- Adds a recipe's missing ingredients to the list, scaled to the
-- requested serving count, merging quantities where the same ingredient
-- and unit already sit on the list.
-- ---------------------------------------------------------------------
create or replace function public.add_recipe_to_shopping_list(
  p_recipe_id          uuid,
  p_kitchen_profile_id uuid,
  p_servings           integer default null,
  p_skip_pantry        boolean default true
)
returns integer
language plpgsql
volatile
set search_path = public, pg_temp
as $$
declare
  v_base    integer;
  v_scale   numeric;
  v_added   integer := 0;
begin
  if not public.is_kitchen_member(p_kitchen_profile_id) then
    raise exception 'not a member of kitchen %', p_kitchen_profile_id
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

  with needed as (
    select ri.ingredient_id,
           round(ri.quantity * v_scale, 3) as quantity,
           ri.unit,
           i.grocery_category
      from public.recipe_ingredients ri
      join public.ingredients i on i.id = ri.ingredient_id
     where ri.recipe_id = p_recipe_id
       and not ri.is_optional
       and (
         not p_skip_pantry
         or not exists (
           select 1 from public.pantry_items pi
            where pi.kitchen_profile_id = p_kitchen_profile_id
              and pi.ingredient_id = ri.ingredient_id
              and pi.quantity > 0
         )
       )
  ),
  merged as (
    update public.shopping_list_items sli
       set quantity = sli.quantity + n.quantity,
           is_checked = false
      from needed n
     where sli.kitchen_profile_id = p_kitchen_profile_id
       and sli.ingredient_id = n.ingredient_id
       and sli.unit = n.unit
    returning n.ingredient_id as ingredient_id
  ),
  inserted as (
    insert into public.shopping_list_items (
      kitchen_profile_id, ingredient_id, grocery_category, quantity, unit, added_by
    )
    select p_kitchen_profile_id, n.ingredient_id, n.grocery_category, n.quantity, n.unit, (select auth.uid())
      from needed n
     where n.ingredient_id not in (select ingredient_id from merged)
    returning 1
  )
  -- Returns rows TOUCHED, not rows inserted. An ingredient already on
  -- the list has its quantity increased rather than duplicated, and the
  -- caller still needs to hear about it -- "5 items added" must not
  -- become "3" just because two of them merged.
  select (select count(*) from merged) + (select count(*) from inserted)
    into v_added;

  return v_added;
end;
$$;

-- ---------------------------------------------------------------------
-- Privilege baseline
--
-- PostgREST reaches the database as `anon` or `authenticated`. Grants
-- decide which relations are addressable at all; RLS decides which rows
-- come back. Both layers are required — a table with RLS enabled but no
-- policy returns nothing, and a table with a policy but no grant
-- returns a permission error.
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant usage on schema extensions to anon, authenticated;

grant select on all tables in schema public to anon, authenticated;
grant insert, update, delete on all tables in schema public to authenticated;

-- anon must never write.
revoke insert, update, delete on all tables in schema public from anon;

grant execute on function public.pantry_match(uuid, numeric, public.meal_type, public.season, integer) to authenticated;
grant execute on function public.fork_recipe(uuid, uuid) to authenticated;
grant execute on function public.add_recipe_to_shopping_list(uuid, uuid, integer, boolean) to authenticated;
grant execute on function public.is_kitchen_member(uuid) to authenticated;
grant execute on function public.is_kitchen_admin(uuid) to authenticated;
grant execute on function public.active_kitchen_id() to authenticated;
