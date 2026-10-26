-- =====================================================================
-- 0011_library_members_profile_fk.sql
--
-- The app lists library members by embedding profiles through PostgREST,
-- which requires a foreign key between library_members and profiles.
-- user_id only referenced auth.users, so that query failed with 400.
-- profiles.id is itself the auth.users id, so this adds no new data
-- relationship and cascades the same way.
-- =====================================================================

begin;

alter table public.library_members
  drop constraint if exists library_members_profile_fkey;
alter table public.library_members
  add constraint library_members_profile_fkey
  foreign key (user_id) references public.profiles(id) on delete cascade;

commit;

notify pgrst, 'reload schema';
