-- =====================================================================
-- 0007_rename_to_libraries.sql
--
-- Pure rename. No behaviour changes, no policy logic touched, no data
-- moved. The tenancy concept was called a "kitchen"; the product calls
-- the user-visible grouping a Cookbook, so the invisible ownership space
-- is renamed to a "library" and the word kitchen leaves the schema.
--
-- Why this is safe to do on a live database:
--   PostgreSQL binds policies, constraints, triggers, views and function
--   bodies to OIDs and attribute numbers, not to text. Renaming a table,
--   a column or a function therefore updates every dependent object
--   automatically. All 61 policies survive untouched, and so do the four
--   storage policies that call is_kitchen_member() from another schema.
--
-- Naming chain, longest match first so compound names resolve correctly:
--   kitchen_profile_id -> library_id
--   kitchen_profiles   -> libraries
--   kitchen_members    -> library_members
--   kitchen            -> library
--
-- Rollback is the same script with the chain reversed.
-- =====================================================================

do $$
declare
  r record;
  v_new text;
  n_columns     integer := 0;
  n_indexes     integer := 0;
  n_constraints integer := 0;
  n_triggers    integer := 0;
  n_policies    integer := 0;
  n_functions   integer := 0;
  n_tables      integer := 0;
begin

  -- 1. Columns. Done first so constraint and index names picked up below
  --    are the only thing left carrying the old word.
  for r in
    select c.table_name, c.column_name
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.column_name like '%kitchen%'
     order by c.table_name, c.column_name
  loop
    v_new := replace(r.column_name, 'kitchen_profile_id', 'library_id');
    execute format('alter table public.%I rename column %I to %I',
                   r.table_name, r.column_name, v_new);
    n_columns := n_columns + 1;
  end loop;

  -- 2. Indexes.
  for r in
    select indexname from pg_indexes
     where schemaname = 'public' and indexname like '%kitchen%'
     order by indexname
  loop
    v_new := replace(replace(replace(replace(r.indexname,
      'kitchen_profile_id', 'library_id'),
      'kitchen_profiles',   'libraries'),
      'kitchen_members',    'library_members'),
      'kitchen',            'library');
    execute format('alter index public.%I rename to %I', r.indexname, v_new);
    n_indexes := n_indexes + 1;
  end loop;

  -- 3. Constraints, including the auto-generated foreign key and check
  --    names that embedded the old column name.
  for r in
    select c.conname, t.relname as table_name
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public' and c.conname like '%kitchen%'
     order by t.relname, c.conname
  loop
    v_new := replace(replace(replace(replace(r.conname,
      'kitchen_profile_id', 'library_id'),
      'kitchen_profiles',   'libraries'),
      'kitchen_members',    'library_members'),
      'kitchen',            'library');
    execute format('alter table public.%I rename constraint %I to %I',
                   r.table_name, r.conname, v_new);
    n_constraints := n_constraints + 1;
  end loop;

  -- 4. Triggers.
  for r in
    select t.tgname, c.relname as table_name
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and not t.tgisinternal
       and t.tgname like '%kitchen%'
     order by c.relname, t.tgname
  loop
    v_new := replace(r.tgname, 'kitchen', 'library');
    execute format('alter trigger %I on public.%I rename to %I',
                   r.tgname, r.table_name, v_new);
    n_triggers := n_triggers + 1;
  end loop;

  -- 5. Policies. Renaming a policy changes its label only; the USING and
  --    WITH CHECK expressions already point at the renamed columns and
  --    functions by OID.
  for r in
    select policyname, tablename from pg_policies
     where schemaname = 'public' and policyname like '%kitchen%'
     order by tablename, policyname
  loop
    v_new := replace(replace(replace(replace(r.policyname,
      'kitchen_profile_id', 'library_id'),
      'kitchen_profiles',   'libraries'),
      'kitchen_members',    'library_members'),
      'kitchen',            'library');
    execute format('alter policy %I on public.%I rename to %I',
                   r.policyname, r.tablename, v_new);
    n_policies := n_policies + 1;
  end loop;

  -- 6. Functions. Every caller, including the four storage policies in
  --    another schema, follows the OID and needs no edit.
  for r in
    select p.proname, pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like '%kitchen%'
     order by p.proname
  loop
    v_new := replace(r.proname, 'kitchen', 'library');
    execute format('alter function public.%I(%s) rename to %I',
                   r.proname, r.args, v_new);
    n_functions := n_functions + 1;
  end loop;

  -- 7. Tables last, so every lookup above resolved against the old names.
  for r in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
       and c.relname like '%kitchen%'
     order by c.relname
  loop
    v_new := replace(replace(r.relname,
      'kitchen_profiles', 'libraries'),
      'kitchen_members',  'library_members');
    execute format('alter table public.%I rename to %I', r.relname, v_new);
    n_tables := n_tables + 1;
  end loop;

  raise notice 'renamed: % columns, % indexes, % constraints, % triggers, % policies, % functions, % tables',
    n_columns, n_indexes, n_constraints, n_triggers, n_policies, n_functions, n_tables;
end
$$;

-- ---------------------------------------------------------------------
-- Comments, refreshed so the schema reads consistently.
-- ---------------------------------------------------------------------
comment on table public.libraries is
  'Ownership root, one per user, never shown in the UI. All user data is partitioned by library_id.';

comment on table public.library_members is
  'Join table binding auth users to libraries. revoked_at IS NULL means active.';

comment on function public.is_library_member(uuid) is
  'Authoritative tenancy predicate for RLS. SECURITY DEFINER to avoid policy recursion on library_members.';

-- ---------------------------------------------------------------------
-- Assertion: nothing in public may still carry the old word.
-- ---------------------------------------------------------------------
do $$
declare
  v_left integer;
begin
  select
    (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relkind='r' and c.relname like '%kitchen%')
  + (select count(*) from information_schema.columns
      where table_schema='public' and column_name like '%kitchen%')
  + (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname like '%kitchen%')
  + (select count(*) from pg_indexes
      where schemaname='public' and indexname like '%kitchen%')
  + (select count(*) from pg_policies
      where schemaname='public' and policyname like '%kitchen%')
  + (select count(*) from pg_constraint c join pg_namespace n on n.oid=c.connamespace
      where n.nspname='public' and c.conname like '%kitchen%')
  + (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and not t.tgisinternal and t.tgname like '%kitchen%')
  into v_left;

  if v_left <> 0 then
    raise exception 'rename incomplete: % objects still named kitchen*', v_left;
  end if;
end
$$;
