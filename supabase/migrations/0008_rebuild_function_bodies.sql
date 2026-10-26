-- =====================================================================
-- 0008_rebuild_function_bodies.sql
--
-- 0007 renamed objects. PostgreSQL rebinds policies, constraints and
-- triggers by OID, so those survived the rename untouched. Function
-- BODIES are stored as text and are NOT rewritten by a rename, so after
-- 0007 every function still referenced public.kitchen_profiles,
-- public.kitchen_members and the kitchen_profile_id column -- none of
-- which exist any more. tg_handle_new_user was therefore dead: every
-- new signup would have failed on "relation public.kitchen_profiles
-- does not exist".
--
-- This migration reads each function's own stored definition, applies
-- the same rename chain 0007 used, and puts it back. Six functions take
-- a parameter that was named p_kitchen_profile_id; CREATE OR REPLACE
-- cannot rename an input parameter, so those are dropped first. CASCADE
-- reaches only the policies that call them, and every such policy is
-- captured beforehand and restored afterwards.
--
-- No data is touched. Runs in one transaction.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Snapshot every policy, so a CASCADE cannot lose one.
-- ---------------------------------------------------------------------
create temp table _pol_bak on commit drop as
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname in ('public', 'storage');

-- ---------------------------------------------------------------------
-- 2. Snapshot the rewritten definition of every affected function.
--    identity_args is the DROP signature (types only); full_args carries
--    the parameter names, which is what decides if a drop is needed.
-- ---------------------------------------------------------------------
create temp table _fn_new on commit drop as
select p.proname,
       pg_get_function_identity_arguments(p.oid) as identity_args,
       pg_get_function_arguments(p.oid)          as full_args,
       replace(
         replace(
           replace(
             replace(
               replace(pg_get_functiondef(p.oid),
                 'kitchen_profile_id', 'library_id'),
               'kitchen_profiles', 'libraries'),
             'kitchen_members', 'library_members'),
           'kitchen', 'library'),
         'Kitchen', 'Cookbook') as def
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
  and pg_get_functiondef(p.oid) like '%kitchen%';

-- ---------------------------------------------------------------------
-- 3. Drop only the functions whose parameter names have to change.
-- ---------------------------------------------------------------------
do $drops$
declare
  r record;
begin
  for r in select proname, identity_args from _fn_new where full_args like '%kitchen%'
  loop
    execute format('drop function if exists public.%I(%s) cascade', r.proname, r.identity_args);
  end loop;
end
$drops$;

-- ---------------------------------------------------------------------
-- 4. Put every function back from its rewritten definition. A
--    language-sql function is parsed at creation time and may depend on
--    another function in this set, so the list is retried until it
--    stops shrinking.
-- ---------------------------------------------------------------------
do $recreate$
declare
  r         record;
  v_left    text[] := '{}';
  v_prev    integer := -1;
  v_pass    integer := 0;
  v_lasterr text;
begin
  select array_agg(def) into v_left from _fn_new;

  while array_length(v_left, 1) is not null and array_length(v_left, 1) <> v_prev loop
    v_prev := array_length(v_left, 1);
    v_pass := v_pass + 1;
    declare
      v_still text[] := '{}';
      d       text;
    begin
      foreach d in array v_left loop
        begin
          execute d;
        exception when others then
          v_lasterr := sqlerrm;
          v_still := v_still || d;
        end;
      end loop;
      v_left := v_still;
    end;
  end loop;

  if array_length(v_left, 1) is not null then
    raise exception '0008: % function(s) would not recreate after % passes; last error: %',
      array_length(v_left, 1), v_pass, v_lasterr;
  end if;
end
$recreate$;

-- ---------------------------------------------------------------------
-- 5. Restore any policy the cascade removed.
-- ---------------------------------------------------------------------
do $restore$
declare
  r record;
begin
  for r in
    select b.* from _pol_bak b
    where not exists (
      select 1 from pg_policies p
      where p.schemaname = b.schemaname
        and p.tablename  = b.tablename
        and p.policyname = b.policyname)
  loop
    execute format(
      'create policy %I on %I.%I as %s for %s to %s %s %s',
      r.policyname, r.schemaname, r.tablename,
      case when r.permissive = 'PERMISSIVE' then 'PERMISSIVE' else 'RESTRICTIVE' end,
      r.cmd,
      array_to_string(r.roles, ', '),
      case when r.qual       is not null then 'using (' || r.qual || ')' else '' end,
      case when r.with_check is not null then 'with check (' || r.with_check || ')' else '' end);
  end loop;
end
$restore$;

-- ---------------------------------------------------------------------
-- 6. 0007 did not touch storage policy NAMES. ALTER POLICY ... RENAME
--    needs ownership of storage.objects, which the dashboard role does
--    not have, so this is a drop-and-recreate from the snapshot taken in
--    step 1. It is cosmetic: the four policies already enforce the right
--    thing, only their names still say "kitchen". If the role cannot do
--    it either, say so and carry on rather than rolling back the
--    function fix, which is the part that matters.
-- ---------------------------------------------------------------------
do $storage$
declare
  r record;
begin
  for r in select * from _pol_bak
           where schemaname = 'storage' and policyname like '%kitchen%'
  loop
    begin
      execute format('drop policy %I on storage.objects', r.policyname);
      execute format(
        'create policy %I on storage.objects as %s for %s to %s %s %s',
        replace(r.policyname, 'kitchen', 'cookbook'),
        case when r.permissive = 'PERMISSIVE' then 'PERMISSIVE' else 'RESTRICTIVE' end,
        r.cmd,
        array_to_string(r.roles, ', '),
        case when r.qual       is not null then 'using (' || r.qual || ')' else '' end,
        case when r.with_check is not null then 'with check (' || r.with_check || ')' else '' end);
    exception when insufficient_privilege then
      raise notice '0008: cannot rename storage policy % (needs ownership of storage.objects); left as is', r.policyname;
    end;
  end loop;
end
$storage$;

-- ---------------------------------------------------------------------
-- 7. Assertions. Any failure rolls the whole migration back.
-- ---------------------------------------------------------------------
do $assert$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
    and pg_get_functiondef(p.oid) like '%kitchen%';
  if v_bad > 0 then
    raise exception '0008 incomplete: % function bodies still contain kitchen', v_bad;
  end if;

  select count(*) into v_bad
  from pg_policies
  where schemaname in ('public', 'storage')
    and (coalesce(qual, '')       like '%kitchen%'
      or coalesce(with_check, '') like '%kitchen%');
  if v_bad > 0 then
    raise exception '0008 incomplete: % policy expressions still reference kitchen', v_bad;
  end if;

  select count(*) into v_bad
  from pg_policies where schemaname = 'public' and policyname like '%kitchen%';
  if v_bad > 0 then
    raise exception '0008 incomplete: % public policies still named kitchen', v_bad;
  end if;

  select count(*) into v_bad
  from pg_policies where schemaname = 'storage' and policyname like '%kitchen%';
  if v_bad > 0 then
    raise notice '0008: % storage policy name(s) still say kitchen (cosmetic, needs storage owner)', v_bad;
  end if;

  select count(*) into v_bad from pg_policies where schemaname = 'public';
  if v_bad <> 61 then
    raise exception '0008: expected 61 public policies, found %', v_bad;
  end if;

  select count(*) into v_bad from pg_policies where schemaname = 'storage';
  if v_bad <> 5 then
    raise exception '0008: expected 5 storage policies, found %', v_bad;
  end if;

  raise notice '0008 ok';
end
$assert$;

commit;
