-- =====================================================================
-- 0005_storage_policies.sql
-- Recipe cover images.
--
-- One bucket, private. `public = false` means Supabase will not serve
-- /object/public/... for it at all; reads go through a signed URL or an
-- authenticated request, and in both cases the policies below decide.
--
-- Object key layout is fixed:  <kitchen_uuid>/<recipe_uuid>/cover.<ext>
-- The policies read the tenant straight out of the key, which is why
-- 0001 pins the layout with a CHECK on recipes.cover_image_path.
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'recipe-covers',
  'recipe-covers',
  false,
  5242880,                                            -- 5 MB ceiling per object
  array['image/jpeg', 'image/png', 'image/webp']      -- no SVG: it is a script carrier
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- SVG is excluded deliberately. An <svg> served from your own origin can
-- carry <script> and run with your origin's privileges; raster formats
-- cannot.

-- ---------------------------------------------------------------------
-- Read
-- ---------------------------------------------------------------------
drop policy if exists "covers: members read own kitchen" on storage.objects;
create policy "covers: members read own kitchen"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'recipe-covers'
    and public.is_valid_cover_path(name)
    and public.is_kitchen_member(((storage.foldername(name))[1])::uuid)
  );

-- The only cross-tenant read that exists: the cover of a recipe whose
-- owner has explicitly set is_public. Scoped to the second path segment,
-- so a public recipe never exposes its neighbours in the same folder.
drop policy if exists "covers: public recipe covers readable" on storage.objects;
create policy "covers: public recipe covers readable"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'recipe-covers'
    and public.is_valid_cover_path(name)
    and public.recipe_is_public(((storage.foldername(name))[2])::uuid)
  );

-- ---------------------------------------------------------------------
-- Write — members of the owning kitchen only, and only at a key that
-- matches the pinned layout.
-- ---------------------------------------------------------------------
drop policy if exists "covers: members upload own kitchen" on storage.objects;
create policy "covers: members upload own kitchen"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'recipe-covers'
    and public.is_valid_cover_path(name)
    and public.is_kitchen_member(((storage.foldername(name))[1])::uuid)
    and owner = (select auth.uid())
  );

drop policy if exists "covers: members replace own kitchen" on storage.objects;
create policy "covers: members replace own kitchen"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'recipe-covers'
    and public.is_valid_cover_path(name)
    and public.is_kitchen_member(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'recipe-covers'
    and public.is_valid_cover_path(name)
    and public.is_kitchen_member(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "covers: members delete own kitchen" on storage.objects;
create policy "covers: members delete own kitchen"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'recipe-covers'
    and public.is_valid_cover_path(name)
    and public.is_kitchen_member(((storage.foldername(name))[1])::uuid)
  );

-- ---------------------------------------------------------------------
-- No other bucket is created. There is no avatar bucket, no video
-- bucket, no import-scratch bucket. Every additional bucket is another
-- perimeter to police, and the brief calls for zero hosted video.
-- ---------------------------------------------------------------------
