-- =====================================================================
-- 0009_library_invitations.sql
--
-- Secure, token-based invitations to a library.
--
-- * Only a SHA-256 hash of the token is stored; the plaintext is
--   returned once, to the inviting admin, by create_library_invitation.
-- * The table is not writable through the API. All changes go through
--   the SECURITY DEFINER functions below, which pin search_path.
-- * Tokens are single-use, expire, can be revoked, and may be bound to
--   an email address. Every failure to accept raises the same generic
--   error so tokens cannot be probed.
-- * Invitations can only grant 'member' or 'admin', never 'owner'.
-- =====================================================================

begin;

create table if not exists public.library_invitations (
  id            uuid primary key default gen_random_uuid(),
  library_id    uuid not null references public.libraries(id) on delete cascade,
  token_hash    bytea not null unique,
  member_role   public.member_role not null default 'member'
                  check (member_role in ('member', 'admin')),
  invited_email text check (invited_email is null or invited_email = lower(invited_email)),
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  accepted_by   uuid references auth.users(id) on delete set null,
  accepted_at   timestamptz,
  revoked_at    timestamptz
);

create index if not exists library_invitations_library_idx
  on public.library_invitations (library_id);

comment on table public.library_invitations is
  'Hashed single-use invitation tokens. Written only through the *_library_invitation functions.';

alter table public.library_invitations enable row level security;
alter table public.library_invitations force row level security;

drop policy if exists library_invitations_select_admin on public.library_invitations;
create policy library_invitations_select_admin
  on public.library_invitations for select
  to authenticated
  using (public.is_library_admin(library_id));

revoke all on public.library_invitations from anon, authenticated;
grant select (id, library_id, member_role, invited_email, created_by,
              created_at, expires_at, accepted_by, accepted_at, revoked_at)
  on public.library_invitations to authenticated;

-- ---------------------------------------------------------------------
-- Create. Returns the plaintext token exactly once.
-- ---------------------------------------------------------------------
create or replace function public.create_library_invitation(
  p_library_id uuid,
  p_role       public.member_role default 'member',
  p_email      text default null,
  p_ttl_hours  integer default 168
)
returns table (invitation_id uuid, token text, expires_at timestamptz)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_id    uuid;
  v_exp   timestamptz;
  v_email text := nullif(lower(btrim(p_email)), '');
begin
  if (select auth.uid()) is null or not public.is_library_admin(p_library_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_role not in ('member', 'admin') then
    raise exception 'invalid role' using errcode = '22023';
  end if;
  if p_ttl_hours is null or p_ttl_hours < 1 or p_ttl_hours > 720 then
    raise exception 'invalid expiry' using errcode = '22023';
  end if;

  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_exp   := now() + make_interval(hours => p_ttl_hours);

  insert into public.library_invitations
    (library_id, token_hash, member_role, invited_email, created_by, expires_at)
  values
    (p_library_id, sha256(convert_to(v_token, 'UTF8')), p_role, v_email,
     (select auth.uid()), v_exp)
  returning id into v_id;

  return query select v_id, v_token, v_exp;
end;
$$;

-- ---------------------------------------------------------------------
-- Accept. Locks the row so a token cannot be redeemed twice.
-- ---------------------------------------------------------------------
create or replace function public.accept_library_invitation(p_token text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_email text := lower(coalesce((select auth.jwt()) ->> 'email', ''));
  v_inv   public.library_invitations%rowtype;
begin
  if v_uid is null or p_token is null then
    raise exception 'invalid invitation' using errcode = '42501';
  end if;

  select * into v_inv
    from public.library_invitations i
   where i.token_hash = sha256(convert_to(p_token, 'UTF8'))
   for update;

  if not found
     or v_inv.accepted_at is not null
     or v_inv.revoked_at is not null
     or v_inv.expires_at <= now()
     or (v_inv.invited_email is not null and v_inv.invited_email <> v_email) then
    raise exception 'invalid invitation' using errcode = '42501';
  end if;

  -- An existing active membership is never downgraded or altered.
  insert into public.library_members (library_id, user_id, member_role, invited_by)
  values (v_inv.library_id, v_uid, v_inv.member_role, v_inv.created_by)
  on conflict (library_id, user_id) do update
     set member_role = excluded.member_role,
         invited_by  = excluded.invited_by,
         joined_at   = now(),
         revoked_at  = null
   where public.library_members.revoked_at is not null;

  update public.library_invitations
     set accepted_by = v_uid, accepted_at = now()
   where id = v_inv.id;

  return v_inv.library_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Revoke a pending invitation.
-- ---------------------------------------------------------------------
create or replace function public.revoke_library_invitation(p_invitation_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lib uuid;
begin
  select library_id into v_lib
    from public.library_invitations where id = p_invitation_id;
  if v_lib is null or not public.is_library_admin(v_lib) then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  update public.library_invitations
     set revoked_at = now()
   where id = p_invitation_id
     and accepted_at is null and revoked_at is null;
  return found;
end;
$$;

revoke all on function public.create_library_invitation(uuid, public.member_role, text, integer) from public, anon;
revoke all on function public.accept_library_invitation(text) from public, anon;
revoke all on function public.revoke_library_invitation(uuid) from public, anon;
grant execute on function public.create_library_invitation(uuid, public.member_role, text, integer) to authenticated;
grant execute on function public.accept_library_invitation(text) to authenticated;
grant execute on function public.revoke_library_invitation(uuid) to authenticated;

commit;
