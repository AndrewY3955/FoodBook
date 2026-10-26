-- =====================================================================
-- 0010_library_creator_can_read_unclaimed.sql
--
-- PostgREST runs `INSERT ... RETURNING` for insert().select(). Postgres
-- applies the SELECT policy to the returned row, but a library's creator
-- is not a member until the second statement (the owner claim) runs, so
-- creating a library failed with 403.
--
-- The creator may now read the library while it has no members, which is
-- exactly the window the owner-claim bootstrap uses. Once any member
-- exists, only members can read it, as before.
--
-- The creator check is inline on purpose: a STABLE helper that re-reads
-- public.libraries cannot see the row being inserted by the same
-- statement. The helper below only inspects library_members.
-- =====================================================================

begin;

create or replace function public.library_has_no_members(p_library_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.library_members lm where lm.library_id = p_library_id
  );
$$;

revoke all on function public.library_has_no_members(uuid) from public, anon;
grant execute on function public.library_has_no_members(uuid) to authenticated;

drop policy if exists libraries_select_member on public.libraries;
create policy libraries_select_member
  on public.libraries for select
  to authenticated
  using (
    public.is_library_member(id)
    or (
      created_by = (select auth.uid())
      and public.library_has_no_members(id)
    )
  );

commit;
