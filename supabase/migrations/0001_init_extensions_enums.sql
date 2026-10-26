-- =====================================================================
-- 0001_init_extensions_enums.sql
-- Recipe & Meal Planning App — foundation types
--
-- Target: Supabase (PostgreSQL 15/16)
-- Run order: 0001 -> 0002 -> 0003 -> 0004 -> 0005 -> (optional) 0006
--
-- NOTE: auth.users, auth.uid(), auth.jwt() and storage.objects are
-- provided by the Supabase platform. This script never creates or
-- modifies them; it only references them.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Extensions
-- Supabase convention: non-core extensions live in the `extensions`
-- schema, never in `public`, so that `public` contains only app objects.
-- ---------------------------------------------------------------------
create schema if not exists extensions;

-- Trigram index support for ingredient autocomplete.
create extension if not exists pg_trgm with schema extensions;

-- gen_random_uuid() is core in PostgreSQL 13+; no pgcrypto dependency.

-- ---------------------------------------------------------------------
-- Enumerated domains
-- Enums are used instead of free text so that filtering is a cheap
-- integer comparison on an indexed column, and so that invalid values
-- are rejected by the database rather than trusted from the client.
-- ---------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'meal_type') then
    create type public.meal_type as enum ('breakfast', 'lunch', 'dinner', 'snack', 'dessert');
  end if;

  if not exists (select 1 from pg_type where typname = 'season') then
    create type public.season as enum ('spring', 'summer', 'autumn', 'winter', 'all_year');
  end if;

  if not exists (select 1 from pg_type where typname = 'grocery_category') then
    create type public.grocery_category as enum (
      'veggies',
      'fruits',
      'meat',
      'seafood',
      'dairy',
      'bakery',
      'frozen',
      'pantry_staples',
      'spices',
      'beverages',
      'other'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'measure_unit') then
    create type public.measure_unit as enum (
      'unit', 'piece', 'pinch', 'clove', 'slice',
      'g', 'kg', 'oz', 'lb',
      'ml', 'l', 'tsp', 'tbsp', 'cup', 'fl_oz',
      'bunch', 'can', 'package', 'to_taste'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'member_role') then
    create type public.member_role as enum ('owner', 'admin', 'member');
  end if;

  if not exists (select 1 from pg_type where typname = 'import_source') then
    create type public.import_source as enum ('manual', 'web', 'instagram', 'tiktok', 'fork');
  end if;
end
$$;

-- ---------------------------------------------------------------------
-- URL safety
--
-- The brief requires frontend sanitization of the external video URL
-- field. Frontend sanitization is a usability feature, not a security
-- control: anyone can call PostgREST directly with a bearer token and
-- skip the Flutter client entirely. This CHECK function is the control
-- that actually holds, because it runs inside the database on every
-- INSERT and UPDATE regardless of which client sent the row.
--
-- Accepts: https scheme only, no credentials, no whitespace, no angle
-- brackets, no quotes, no backslashes. That rejects `javascript:`,
-- `data:`, `vbscript:`, protocol-relative `//evil`, and the common
-- `"><script>` breakout payloads at the storage boundary.
-- ---------------------------------------------------------------------
create or replace function public.is_safe_http_url(p_url text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_url is not null
     and char_length(p_url) between 11 and 2048
     and p_url ~ '^https://[A-Za-z0-9._~-]+(:[0-9]{1,5})?(/[^[:space:]<>"''`\\{}|^]*)?$'
     and p_url !~ '[[:cntrl:]]';
$$;

comment on function public.is_safe_http_url(text) is
  'Storage-boundary XSS/SSRF guard for user-supplied URLs. https only, no control chars, no quote/angle-bracket breakout characters.';

-- ---------------------------------------------------------------------
-- Storage object path safety
--
-- Cover image paths are constrained to `<kitchen_uuid>/<recipe_uuid>/cover.<ext>`.
-- Pinning the layout is what allows the storage RLS policies in 0005 to
-- derive the owning kitchen from the object path itself.
-- ---------------------------------------------------------------------
create or replace function public.is_valid_cover_path(p_path text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_path is not null
     and p_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/cover\.(jpg|jpeg|png|webp)$';
$$;

comment on function public.is_valid_cover_path(text) is
  'Enforces the <kitchen_id>/<recipe_id>/cover.<ext> object layout that storage policies depend on.';
