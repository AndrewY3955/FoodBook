-- =====================================================================
-- 0004_rls_policies.sql
-- The security perimeter.
--
-- Rules applied throughout:
--   * Every table gets ENABLE + FORCE row level security. FORCE means
--     the table owner is subject to policy too, so a future migration
--     that runs as the owner cannot quietly read across tenants.
--   * Every policy names its role (TO anon / TO authenticated). An
--     unqualified policy is evaluated for every role including anon.
--   * auth.uid() is wrapped as (select auth.uid()) so the planner
--     evaluates it once per statement instead of once per row.
--   * USING governs which existing rows are visible; WITH CHECK governs
--     which new or modified rows are allowed to land. UPDATE needs both:
--     USING alone lets a member rewrite a row into another tenant.
--   * No policy exists for an operation that should be impossible, e.g.
--     cook_logs has no UPDATE or DELETE policy, making it append-only.
-- =====================================================================

-- Policy helper: do the caller and the target user share any kitchen?
-- SECURITY DEFINER for the same recursion reason as is_kitchen_member.
create or replace function public.shares_kitchen_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.kitchen_members a
      join public.kitchen_members b on b.kitchen_profile_id = a.kitchen_profile_id
     where a.user_id = (select auth.uid())
       and a.revoked_at is null
       and b.user_id = p_user_id
       and b.revoked_at is null
  );
$$;

grant execute on function public.shares_kitchen_with(uuid) to authenticated;

-- Visibility helper for child rows hanging off a public recipe.
create or replace function public.recipe_is_public(p_recipe_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select r.is_public from public.recipes r where r.id = p_recipe_id), false);
$$;

grant execute on function public.recipe_is_public(uuid) to anon, authenticated;

-- =====================================================================
-- profiles
-- =====================================================================
alter table public.profiles enable row level security;
alter table public.profiles force row level security;

drop policy if exists profiles_select_self_or_kitchen on public.profiles;
create policy profiles_select_self_or_kitchen
  on public.profiles for select
  to authenticated
  using (
    id = (select auth.uid())
    or public.shares_kitchen_with(id)
  );

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self
  on public.profiles for insert
  to authenticated
  with check (id = (select auth.uid()));

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No DELETE policy: profiles are removed only by the auth.users cascade.

-- =====================================================================
-- kitchen_profiles
-- =====================================================================
alter table public.kitchen_profiles enable row level security;
alter table public.kitchen_profiles force row level security;

drop policy if exists kitchen_profiles_select_member on public.kitchen_profiles;
create policy kitchen_profiles_select_member
  on public.kitchen_profiles for select
  to authenticated
  using (public.is_kitchen_member(id));

drop policy if exists kitchen_profiles_insert_self on public.kitchen_profiles;
create policy kitchen_profiles_insert_self
  on public.kitchen_profiles for insert
  to authenticated
  with check (created_by = (select auth.uid()));

drop policy if exists kitchen_profiles_update_admin on public.kitchen_profiles;
create policy kitchen_profiles_update_admin
  on public.kitchen_profiles for update
  to authenticated
  using (public.is_kitchen_admin(id))
  with check (public.is_kitchen_admin(id));

drop policy if exists kitchen_profiles_delete_admin on public.kitchen_profiles;
create policy kitchen_profiles_delete_admin
  on public.kitchen_profiles for delete
  to authenticated
  using (public.is_kitchen_admin(id));

-- =====================================================================
-- kitchen_members
-- =====================================================================
alter table public.kitchen_members enable row level security;
alter table public.kitchen_members force row level security;

drop policy if exists kitchen_members_select_member on public.kitchen_members;
create policy kitchen_members_select_member
  on public.kitchen_members for select
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists kitchen_members_insert_admin on public.kitchen_members;
create policy kitchen_members_insert_admin
  on public.kitchen_members for insert
  to authenticated
  with check (
    public.is_kitchen_admin(kitchen_profile_id)
    -- Bootstrap: the creator of a kitchen that has no members yet may
    -- insert their own owner row. can_claim_kitchen is SECURITY DEFINER
    -- on purpose — see 0003. An inline subquery here would be filtered
    -- by the caller's own RLS and would let any user claim ownership of
    -- any kitchen whose membership they cannot see.
    or (
      member_role = 'owner'
      and user_id = (select auth.uid())
      and public.can_claim_kitchen(kitchen_profile_id)
    )
  );

drop policy if exists kitchen_members_update_admin on public.kitchen_members;
create policy kitchen_members_update_admin
  on public.kitchen_members for update
  to authenticated
  using (public.is_kitchen_admin(kitchen_profile_id))
  with check (public.is_kitchen_admin(kitchen_profile_id));

drop policy if exists kitchen_members_delete_admin_or_self on public.kitchen_members;
create policy kitchen_members_delete_admin_or_self
  on public.kitchen_members for delete
  to authenticated
  using (
    public.is_kitchen_admin(kitchen_profile_id)
    or user_id = (select auth.uid())
  );

-- =====================================================================
-- ingredients
-- Global catalog rows (kitchen_profile_id IS NULL) are world-readable
-- and writable by nobody through the API.
-- =====================================================================
alter table public.ingredients enable row level security;
alter table public.ingredients force row level security;

drop policy if exists ingredients_select_global_anon on public.ingredients;
create policy ingredients_select_global_anon
  on public.ingredients for select
  to anon
  using (kitchen_profile_id is null);

drop policy if exists ingredients_select_global_or_own on public.ingredients;
create policy ingredients_select_global_or_own
  on public.ingredients for select
  to authenticated
  using (
    kitchen_profile_id is null
    or public.is_kitchen_member(kitchen_profile_id)
  );

drop policy if exists ingredients_insert_own on public.ingredients;
create policy ingredients_insert_own
  on public.ingredients for insert
  to authenticated
  with check (
    kitchen_profile_id is not null
    and public.is_kitchen_member(kitchen_profile_id)
  );

drop policy if exists ingredients_update_own on public.ingredients;
create policy ingredients_update_own
  on public.ingredients for update
  to authenticated
  using (
    kitchen_profile_id is not null
    and public.is_kitchen_member(kitchen_profile_id)
  )
  with check (
    kitchen_profile_id is not null
    and public.is_kitchen_member(kitchen_profile_id)
  );

drop policy if exists ingredients_delete_own on public.ingredients;
create policy ingredients_delete_own
  on public.ingredients for delete
  to authenticated
  using (
    kitchen_profile_id is not null
    and public.is_kitchen_member(kitchen_profile_id)
  );

-- =====================================================================
-- recipes
-- =====================================================================
alter table public.recipes enable row level security;
alter table public.recipes force row level security;

drop policy if exists recipes_select_public_anon on public.recipes;
create policy recipes_select_public_anon
  on public.recipes for select
  to anon
  using (is_public);

drop policy if exists recipes_select_member_or_public on public.recipes;
create policy recipes_select_member_or_public
  on public.recipes for select
  to authenticated
  using (
    public.is_kitchen_member(kitchen_profile_id)
    or is_public
  );

drop policy if exists recipes_insert_member on public.recipes;
create policy recipes_insert_member
  on public.recipes for insert
  to authenticated
  with check (
    public.is_kitchen_member(kitchen_profile_id)
    and created_by = (select auth.uid())
  );

drop policy if exists recipes_update_member on public.recipes;
create policy recipes_update_member
  on public.recipes for update
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id))
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists recipes_delete_member on public.recipes;
create policy recipes_delete_member
  on public.recipes for delete
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

-- =====================================================================
-- recipe_ingredients
-- =====================================================================
alter table public.recipe_ingredients enable row level security;
alter table public.recipe_ingredients force row level security;

drop policy if exists recipe_ingredients_select_public_anon on public.recipe_ingredients;
create policy recipe_ingredients_select_public_anon
  on public.recipe_ingredients for select
  to anon
  using (public.recipe_is_public(recipe_id));

drop policy if exists recipe_ingredients_select on public.recipe_ingredients;
create policy recipe_ingredients_select
  on public.recipe_ingredients for select
  to authenticated
  using (
    public.is_kitchen_member(kitchen_profile_id)
    or public.recipe_is_public(recipe_id)
  );

drop policy if exists recipe_ingredients_insert on public.recipe_ingredients;
create policy recipe_ingredients_insert
  on public.recipe_ingredients for insert
  to authenticated
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists recipe_ingredients_update on public.recipe_ingredients;
create policy recipe_ingredients_update
  on public.recipe_ingredients for update
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id))
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists recipe_ingredients_delete on public.recipe_ingredients;
create policy recipe_ingredients_delete
  on public.recipe_ingredients for delete
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

-- =====================================================================
-- recipe_steps
-- =====================================================================
alter table public.recipe_steps enable row level security;
alter table public.recipe_steps force row level security;

drop policy if exists recipe_steps_select_public_anon on public.recipe_steps;
create policy recipe_steps_select_public_anon
  on public.recipe_steps for select
  to anon
  using (public.recipe_is_public(recipe_id));

drop policy if exists recipe_steps_select on public.recipe_steps;
create policy recipe_steps_select
  on public.recipe_steps for select
  to authenticated
  using (
    public.is_kitchen_member(kitchen_profile_id)
    or public.recipe_is_public(recipe_id)
  );

drop policy if exists recipe_steps_insert on public.recipe_steps;
create policy recipe_steps_insert
  on public.recipe_steps for insert
  to authenticated
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists recipe_steps_update on public.recipe_steps;
create policy recipe_steps_update
  on public.recipe_steps for update
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id))
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists recipe_steps_delete on public.recipe_steps;
create policy recipe_steps_delete
  on public.recipe_steps for delete
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

-- =====================================================================
-- tags / recipe_tags — private to the kitchen, never public
-- =====================================================================
alter table public.tags enable row level security;
alter table public.tags force row level security;

drop policy if exists tags_select on public.tags;
create policy tags_select
  on public.tags for select
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists tags_insert on public.tags;
create policy tags_insert
  on public.tags for insert
  to authenticated
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists tags_update on public.tags;
create policy tags_update
  on public.tags for update
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id))
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists tags_delete on public.tags;
create policy tags_delete
  on public.tags for delete
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

alter table public.recipe_tags enable row level security;
alter table public.recipe_tags force row level security;

drop policy if exists recipe_tags_select on public.recipe_tags;
create policy recipe_tags_select
  on public.recipe_tags for select
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists recipe_tags_insert on public.recipe_tags;
create policy recipe_tags_insert
  on public.recipe_tags for insert
  to authenticated
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists recipe_tags_delete on public.recipe_tags;
create policy recipe_tags_delete
  on public.recipe_tags for delete
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

-- =====================================================================
-- pantry_items
-- =====================================================================
alter table public.pantry_items enable row level security;
alter table public.pantry_items force row level security;

drop policy if exists pantry_items_select on public.pantry_items;
create policy pantry_items_select
  on public.pantry_items for select
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists pantry_items_insert on public.pantry_items;
create policy pantry_items_insert
  on public.pantry_items for insert
  to authenticated
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists pantry_items_update on public.pantry_items;
create policy pantry_items_update
  on public.pantry_items for update
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id))
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists pantry_items_delete on public.pantry_items;
create policy pantry_items_delete
  on public.pantry_items for delete
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

-- =====================================================================
-- shopping_list_items
-- =====================================================================
alter table public.shopping_list_items enable row level security;
alter table public.shopping_list_items force row level security;

drop policy if exists shopping_list_select on public.shopping_list_items;
create policy shopping_list_select
  on public.shopping_list_items for select
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists shopping_list_insert on public.shopping_list_items;
create policy shopping_list_insert
  on public.shopping_list_items for insert
  to authenticated
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists shopping_list_update on public.shopping_list_items;
create policy shopping_list_update
  on public.shopping_list_items for update
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id))
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists shopping_list_delete on public.shopping_list_items;
create policy shopping_list_delete
  on public.shopping_list_items for delete
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

-- =====================================================================
-- meal_plan_entries
-- =====================================================================
alter table public.meal_plan_entries enable row level security;
alter table public.meal_plan_entries force row level security;

drop policy if exists meal_plan_select on public.meal_plan_entries;
create policy meal_plan_select
  on public.meal_plan_entries for select
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists meal_plan_insert on public.meal_plan_entries;
create policy meal_plan_insert
  on public.meal_plan_entries for insert
  to authenticated
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists meal_plan_update on public.meal_plan_entries;
create policy meal_plan_update
  on public.meal_plan_entries for update
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id))
  with check (public.is_kitchen_member(kitchen_profile_id));

drop policy if exists meal_plan_delete on public.meal_plan_entries;
create policy meal_plan_delete
  on public.meal_plan_entries for delete
  to authenticated
  using (public.is_kitchen_member(kitchen_profile_id));

-- =====================================================================
-- Community layer
-- =====================================================================
alter table public.substitution_suggestions enable row level security;
alter table public.substitution_suggestions force row level security;

drop policy if exists substitutions_select_anon on public.substitution_suggestions;
create policy substitutions_select_anon
  on public.substitution_suggestions for select
  to anon
  using (public.recipe_is_public(recipe_id));

drop policy if exists substitutions_select on public.substitution_suggestions;
create policy substitutions_select
  on public.substitution_suggestions for select
  to authenticated
  using (
    public.recipe_is_public(recipe_id)
    or exists (
      select 1 from public.recipes r
       where r.id = substitution_suggestions.recipe_id
         and public.is_kitchen_member(r.kitchen_profile_id)
    )
  );

drop policy if exists substitutions_insert_own on public.substitution_suggestions;
create policy substitutions_insert_own
  on public.substitution_suggestions for insert
  to authenticated
  with check (
    created_by = (select auth.uid())
    and public.recipe_is_public(recipe_id)
  );

drop policy if exists substitutions_update_own on public.substitution_suggestions;
create policy substitutions_update_own
  on public.substitution_suggestions for update
  to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

drop policy if exists substitutions_delete_own on public.substitution_suggestions;
create policy substitutions_delete_own
  on public.substitution_suggestions for delete
  to authenticated
  using (created_by = (select auth.uid()));

alter table public.substitution_votes enable row level security;
alter table public.substitution_votes force row level security;

drop policy if exists votes_select on public.substitution_votes;
create policy votes_select
  on public.substitution_votes for select
  to authenticated
  using (
    exists (
      select 1
        from public.substitution_suggestions s
       where s.id = substitution_votes.suggestion_id
         and public.recipe_is_public(s.recipe_id)
    )
  );

drop policy if exists votes_insert_own on public.substitution_votes;
create policy votes_insert_own
  on public.substitution_votes for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists votes_update_own on public.substitution_votes;
create policy votes_update_own
  on public.substitution_votes for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists votes_delete_own on public.substitution_votes;
create policy votes_delete_own
  on public.substitution_votes for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- cook_logs: append-only. SELECT and INSERT policies only; the absence
-- of UPDATE/DELETE policies is the control that makes history immutable
-- from the client.
alter table public.cook_logs enable row level security;
alter table public.cook_logs force row level security;

drop policy if exists cook_logs_select on public.cook_logs;
create policy cook_logs_select
  on public.cook_logs for select
  to authenticated
  using (
    public.recipe_is_public(recipe_id)
    or exists (
      select 1 from public.recipes r
       where r.id = cook_logs.recipe_id
         and public.is_kitchen_member(r.kitchen_profile_id)
    )
  );

drop policy if exists cook_logs_insert on public.cook_logs;
create policy cook_logs_insert
  on public.cook_logs for insert
  to authenticated
  with check (
    public.recipe_is_public(recipe_id)
    or exists (
      select 1 from public.recipes r
       where r.id = cook_logs.recipe_id
         and public.is_kitchen_member(r.kitchen_profile_id)
    )
  );
