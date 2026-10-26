-- =====================================================================
-- _local_harness.sql
--
-- LOCAL TEST SCAFFOLDING ONLY. NEVER RUN THIS AGAINST A SUPABASE
-- PROJECT. It fabricates the parts of the Supabase platform that the
-- migrations depend on (auth schema, JWT helpers, PostgREST roles,
-- storage schema) so the migrations and the RLS test suite can be
-- executed on a bare PostgreSQL instance.
--
-- On a real project all of this already exists and is managed by
-- Supabase. Applying this file there would shadow platform objects.
-- =====================================================================

create schema if not exists auth;
create schema if not exists storage;
create schema if not exists extensions;

-- PostgREST roles ------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;

grant anon, authenticated, service_role to current_user;

-- auth.users -----------------------------------------------------------
-- Column subset mirroring the real Supabase table, so that seed scripts
-- written against production also run here unchanged.
create extension if not exists pgcrypto with schema extensions;

create table if not exists auth.users (
  instance_id        uuid default '00000000-0000-0000-0000-000000000000',
  id                 uuid primary key default gen_random_uuid(),
  aud                text default 'authenticated',
  role               text default 'authenticated',
  email              text unique,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_app_meta_data  jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- JWT helpers ----------------------------------------------------------
-- Mirrors Supabase: claims arrive as the `request.jwt.claims` GUC.
create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
$$;

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid;
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(auth.jwt() ->> 'role', 'anon');
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.jwt(), auth.role() to anon, authenticated, service_role;

-- storage --------------------------------------------------------------
create table if not exists storage.buckets (
  id                 text primary key,
  name               text not null,
  public             boolean not null default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz not null default now()
);

create table if not exists storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text not null references storage.buckets(id) on delete cascade,
  name       text not null,
  owner      uuid,
  created_at timestamptz not null default now(),
  unique (bucket_id, name)
);

-- Supabase's storage.foldername: path segments excluding the filename.
create or replace function storage.foldername(name text)
returns text[]
language plpgsql
immutable
as $$
declare
  parts text[];
begin
  parts := string_to_array(name, '/');
  return parts[1:greatest(array_length(parts, 1) - 1, 0)];
end;
$$;

alter table storage.objects enable row level security;
alter table storage.objects force row level security;

grant usage on schema storage to anon, authenticated;
grant select on storage.objects to anon, authenticated;
grant insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to anon, authenticated;
