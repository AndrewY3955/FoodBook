-- =====================================================================
-- 0006_optional_active_claim_hardening.sql
--
-- OPTIONAL. Apply only after reading the trade-off below. The app is
-- fully secure against cross-tenant access without this file; 0004
-- already blocks every foreign-library read and write.
--
-- What this adds: 0004 gates on membership, so a user who belongs to
-- two libraries can touch either one within a single session. This file
-- narrows that to "membership AND the library the session says it is
-- pointed at", read from app_metadata.active_library_id.
--
-- Why you might want it: a stolen or replayed token is confined to one
-- library instead of all of the user's libraries, and a client-side bug
-- that sends the wrong library_id fails loudly at the database
-- rather than silently writing into the other household's pantry.
--
-- Why you might not: app_metadata is only refreshed when the JWT is
-- reissued. Switching libraries then requires a token refresh round-trip
-- (supabase.auth.refreshSession()) instead of a local state change, and
-- a user with exactly one library gains nothing. Membership revocation
-- also stays instant under 0004 but becomes token-lifetime-bound for
-- the claim half of the predicate here.
--
-- app_metadata must be written server-side only. If active_library is
-- ever moved to user_metadata, this file becomes worse than useless:
-- user_metadata is client-writable, so the "gate" would be set by the
-- attacker.
-- =====================================================================

-- Membership AND active claim. Fails closed when the claim is absent.
create or replace function public.is_active_library(p_library_id uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select public.active_library_id() is not null
     and public.active_library_id() = p_library_id
     and public.is_library_member(p_library_id);
$$;

grant execute on function public.is_active_library(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- pantry_items
-- ---------------------------------------------------------------------
drop policy if exists pantry_items_select on public.pantry_items;
create policy pantry_items_select
  on public.pantry_items for select
  to authenticated
  using (public.is_active_library(library_id));

drop policy if exists pantry_items_insert on public.pantry_items;
create policy pantry_items_insert
  on public.pantry_items for insert
  to authenticated
  with check (public.is_active_library(library_id));

drop policy if exists pantry_items_update on public.pantry_items;
create policy pantry_items_update
  on public.pantry_items for update
  to authenticated
  using (public.is_active_library(library_id))
  with check (public.is_active_library(library_id));

drop policy if exists pantry_items_delete on public.pantry_items;
create policy pantry_items_delete
  on public.pantry_items for delete
  to authenticated
  using (public.is_active_library(library_id));

-- ---------------------------------------------------------------------
-- shopping_list_items
-- ---------------------------------------------------------------------
drop policy if exists shopping_list_select on public.shopping_list_items;
create policy shopping_list_select
  on public.shopping_list_items for select
  to authenticated
  using (public.is_active_library(library_id));

drop policy if exists shopping_list_insert on public.shopping_list_items;
create policy shopping_list_insert
  on public.shopping_list_items for insert
  to authenticated
  with check (public.is_active_library(library_id));

drop policy if exists shopping_list_update on public.shopping_list_items;
create policy shopping_list_update
  on public.shopping_list_items for update
  to authenticated
  using (public.is_active_library(library_id))
  with check (public.is_active_library(library_id));

drop policy if exists shopping_list_delete on public.shopping_list_items;
create policy shopping_list_delete
  on public.shopping_list_items for delete
  to authenticated
  using (public.is_active_library(library_id));

-- ---------------------------------------------------------------------
-- meal_plan_entries
-- ---------------------------------------------------------------------
drop policy if exists meal_plan_select on public.meal_plan_entries;
create policy meal_plan_select
  on public.meal_plan_entries for select
  to authenticated
  using (public.is_active_library(library_id));

drop policy if exists meal_plan_insert on public.meal_plan_entries;
create policy meal_plan_insert
  on public.meal_plan_entries for insert
  to authenticated
  with check (public.is_active_library(library_id));

drop policy if exists meal_plan_update on public.meal_plan_entries;
create policy meal_plan_update
  on public.meal_plan_entries for update
  to authenticated
  using (public.is_active_library(library_id))
  with check (public.is_active_library(library_id));

drop policy if exists meal_plan_delete on public.meal_plan_entries;
create policy meal_plan_delete
  on public.meal_plan_entries for delete
  to authenticated
  using (public.is_active_library(library_id));

-- ---------------------------------------------------------------------
-- recipes — writes are pinned to the active library; reads stay on
-- membership so a second library's recipe box is still browsable and
-- public recipes remain discoverable.
-- ---------------------------------------------------------------------
drop policy if exists recipes_insert_member on public.recipes;
create policy recipes_insert_member
  on public.recipes for insert
  to authenticated
  with check (
    public.is_active_library(library_id)
    and created_by = (select auth.uid())
  );

drop policy if exists recipes_update_member on public.recipes;
create policy recipes_update_member
  on public.recipes for update
  to authenticated
  using (public.is_active_library(library_id))
  with check (public.is_active_library(library_id));

drop policy if exists recipes_delete_member on public.recipes;
create policy recipes_delete_member
  on public.recipes for delete
  to authenticated
  using (public.is_active_library(library_id));
