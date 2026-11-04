-- =====================================================================
-- 0015_library_delete_and_leave.sql
--
--   * A user can belong to many libraries (nothing in the schema limits
--     it; this migration changes no policy for that).
--   * Only the owner of a library, or the creator of one nobody has
--     joined, can delete it. Admins and members cannot. Deleting cascades
--     to everything in the library and cannot be undone.
--   * leave_library() removes the caller's membership. When the caller
--     is the only active member the library is deleted with them. When
--     the caller is the last owner of a shared library, ownership passes
--     to the longest-standing remaining member so the library is never
--     left without an owner.
--   * Storage objects cannot be deleted from SQL (protect_delete
--     trigger), so the client removes a library's files before it calls
--     either path.
-- =====================================================================

begin;

create or replace function public.is_library_owner(p_library_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.library_members m
     where m.library_id = p_library_id
       and m.user_id = (select auth.uid())
       and m.member_role = 'owner'
       and m.revoked_at is null
  );
$$;
revoke all on function public.is_library_owner(uuid) from public, anon;
grant execute on function public.is_library_owner(uuid) to authenticated;

-- Replace whichever DELETE policy the earlier migrations left on libraries.
do $$
declare
  r record;
begin
  for r in
    select policyname from pg_policies
     where schemaname = 'public' and tablename = 'libraries' and cmd = 'DELETE'
  loop
    execute format('drop policy %I on public.libraries', r.policyname);
  end loop;
end
$$;

create policy libraries_delete_owner
  on public.libraries for delete
  to authenticated
  using (
    public.is_library_owner(id)
    or (
      created_by = (select auth.uid())
      and public.library_has_no_members(id)
    )
  );

create or replace function public.leave_library(p_library_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := (select auth.uid());
  v_role     public.member_role;
  v_others   integer;
  v_owners   integer;
  v_heir     uuid;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select m.member_role into v_role
    from public.library_members m
   where m.library_id = p_library_id
     and m.user_id = v_uid
     and m.revoked_at is null;
  if not found then
    raise exception 'not a member' using errcode = '42501';
  end if;

  select count(*) into v_others
    from public.library_members m
   where m.library_id = p_library_id
     and m.user_id <> v_uid
     and m.revoked_at is null;

  if v_others = 0 then
    delete from public.libraries where id = p_library_id;
    return 'deleted';
  end if;

  if v_role = 'owner' then
    select count(*) into v_owners
      from public.library_members m
     where m.library_id = p_library_id
       and m.user_id <> v_uid
       and m.member_role = 'owner'
       and m.revoked_at is null;
    if v_owners = 0 then
      select m.user_id into v_heir
        from public.library_members m
       where m.library_id = p_library_id
         and m.user_id <> v_uid
         and m.revoked_at is null
       order by (m.member_role = 'admin') desc, m.joined_at asc
       limit 1;
      update public.library_members
         set member_role = 'owner'
       where library_id = p_library_id and user_id = v_heir;
    end if;
  end if;

  delete from public.library_members
   where library_id = p_library_id and user_id = v_uid;
  return 'left';
end;
$$;
revoke all on function public.leave_library(uuid) from public, anon;
grant execute on function public.leave_library(uuid) to authenticated;

commit;
