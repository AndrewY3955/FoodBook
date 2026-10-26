# Security architecture

The short version: **the database is the only thing that enforces anything.**
Everything in the Flutter client is convenience, and is written on the
assumption that an attacker will not run it.

---

## 1. Where the perimeter actually is

The anon key ships inside the binary. Anyone can extract it and call PostgREST
directly with `curl`. So the client's input sanitiser, its password rules and
its cookbook selector are all bypassable by construction, and none of them is
treated as a control.

What holds:

| Control | Where | Enforced against |
|---|---|---|
| Tenant isolation | RLS policies, migration 0004 | every request, every role |
| URL safety | `CHECK (is_safe_http_url(...))`, 0001 | every insert and update |
| Cover path shape | `CHECK (is_valid_cover_path(...))`, 0001 | every insert and update |
| Child-row tenancy | triggers, 0003 | client-supplied `library_id` is overwritten |
| Object access | storage policies, 0005 | every object read and write |
| Import fetching | Edge Function guards | every URL, every redirect hop |

The client mirrors the URL rule so the user gets an error in the form instead of
from the server. If you loosen one side, loosen both, or people get rejections
they cannot explain.

---

## 2. Tenant isolation

> **Naming note.** Migrations `0001`–`0005` created these objects as
> `kitchen_profiles`, `kitchen_members` and `kitchen_profile_id`. `0007`
> renamed them to `libraries`, `library_members` and `library_id`; `0008`
> rewrote the function bodies, which a rename does not touch. Read the old
> names in those migration files as the new ones. The user-facing word for
> the grouping people actually see is **Cookbook**; `library` is the
> invisible per-person ownership space and never appears in the UI.

`libraries` is the tenant. `library_members` binds users to libraries, and
every user-data table carries an explicit `library_id` so that RLS is a
single indexed predicate rather than a join chain.

Rules applied to every table without exception:

- `ENABLE` **and** `FORCE ROW LEVEL SECURITY`. Force means the table owner is
  subject to policy too, so a later migration running as owner cannot quietly
  read across tenants.
- Every policy names its role — `TO anon` or `TO authenticated`. An unqualified
  policy is evaluated for every role, including `anon`.
- `auth.uid()` is wrapped as `(select auth.uid())` so it is evaluated once per
  statement, not once per row.
- Every `UPDATE` policy has both `USING` and `WITH CHECK`. `USING` alone lets a
  member rewrite one of their own rows into another tenant. Assertion 2.17 is
  the negative control for exactly this.
- No policy exists for an operation that should be impossible. `cook_logs` has
  `SELECT` and `INSERT` only, which is what makes it append-only.

### Two traps this schema walks into deliberately, and how it gets out

**Policy recursion.** A policy on `library_members` needs to ask "is this user a
member?", and a subquery against its own table under invoker rights recurses
until Postgres aborts with `42P17`. `is_library_member()` is `SECURITY DEFINER`
to break the cycle.

**RLS-blind subqueries.** This one bit for real. The bootstrap that lets a
library's creator claim ownership originally read
`not exists (select 1 from library_members ...)` inline. That subquery is itself
filtered by the caller's RLS — a stranger cannot see the existing members, so
the emptiness test returned `true` and they could insert themselves as owner of
someone else's library. The negative-control suite caught it on the first run
(assertion 2.13). Fixed with `can_claim_library()`, which is `SECURITY DEFINER`
and requires that the library exists, has no members at all, and was created by
the caller.

**The general lesson: any RLS predicate that queries an RLS-protected table is
blind in precisely the direction that matters.** Use a definer-rights function
or you are testing the attacker's view, not the truth.

Every `SECURITY DEFINER` function pins `search_path`. Without that, a caller who
can create objects in an earlier schema can shadow a table the function depends
on. Assertion 9.5 audits this.

---

## 3. Sessions and passwords

JWTs go to the platform keystore via `SecureTokenStorage`, not to
SharedPreferences. The refresh token is a long-lived bearer credential; anyone
who reads it can mint access tokens until it is revoked.

**Web is the honest exception.** A browser has no keystore. "Secure" storage
there is obfuscated `localStorage`, whose key also lives in the browser, and a
refresh token in `localStorage` is readable by any successful XSS. So on web,
session persistence is switched off entirely: the session ends with the tab.

Sign-out uses `SignOutScope.global`, which revokes the refresh token
server-side. A local-only sign-out leaves a working token on the device.

Password rules: 12 characters minimum; **72 maximum**, because bcrypt silently
ignores everything past 72 bytes and a user with a 200-character passphrase
would otherwise be authenticated by its first 72 without ever being told. Mixed
case, a digit, a symbol, no whitespace, and a short local screen for the
passwords at the top of every credential-stuffing list. Enable Supabase's
HaveIBeenPwned check as well — the local list is a courtesy, not coverage.

Error messages never distinguish "no such account" from "wrong password", and
password reset returns the same text whether or not the address exists. The
difference is an account-enumeration oracle.

---

## 4. Media

One private bucket, `recipe-covers`. Object keys are pinned to
`<library_uuid>/<recipe_uuid>/cover.<ext>`, which is what lets the storage
policies derive the owning tenant from the key itself.

- 5 MB ceiling, and `image/jpeg`, `image/png`, `image/webp` only. **SVG is
  excluded deliberately**: an `<svg>` served from your own origin can carry
  `<script>` and run with your origin's privileges. Raster formats cannot.
- Reads go through short-lived signed URLs, so a link pasted into a group chat
  stops working instead of becoming a permanent public handle.
- The only cross-tenant read that exists is the cover of a recipe whose owner
  set `is_public`, scoped to the second path segment so a public recipe never
  exposes its neighbours.
- Uploads are re-encoded on the device before they leave it. That strips EXIF —
  which on a phone photo carries the GPS coordinates of the user's kitchen —
  guarantees the bytes really are an image rather than a renamed file, and cuts
  a 4 MB photo to a couple of hundred KB.

**Zero video is hosted or proxied.** The external video field is a text URL that
opens in the OS browser. No in-app webview: that would run third-party script
inside the app's process and undo the point of not embedding video.

---

## 5. The import function

This is the only component that fetches attacker-chosen URLs, so it is the most
defended thing here.

1. **Authenticated.** `verify_jwt` stays on. An unauthenticated fetch-anything
   endpoint on a public URL is an open proxy and it will be found.
2. **https only**, no credentials in the authority, no non-443 port, no
   breakout characters.
3. **SSRF screening** of loopback, private, link-local, carrier-NAT, multicast
   and cloud-metadata addresses, plus `.internal` and `.local`, in both IPv4 and
   IPv6 form.
4. **Redirects are followed manually and re-validated at every hop.** A page
   that passes the check and then 302s to `169.254.169.254` is the classic
   bypass; `redirect: "manual"` plus re-validation is what closes it.
5. **Resource limits**: 8-second total timeout, 3-redirect cap, 1.5 MB ceiling
   enforced *while streaming*. `Content-Length` is a hint from a hostile server
   and is checked but never trusted.
6. **Strip before parse.** `script`, `style`, `noscript`, `template`, `svg`,
   `iframe`, `object`, `embed` and comments are removed whole, then every
   returned string passes `sanitiseLine`, which drops control and bidi
   characters, scheme handlers, `on*=` attributes and `{}<>`.
7. **Bounded output.** Fixed fields, fixed lengths, fixed array sizes. Whatever
   the remote page contains, the response shape is identical.
8. **Failures are opaque.** The upstream reason is logged, never returned.
   Telling a caller the difference between "timed out", "refused" and "not
   found" turns the endpoint into a network scanner.

Nothing imported is saved automatically. The parse lands in the editor.

---

## 6. Privacy by omission

No grocery delivery integrations. No voice permissions. No store layout
mapping. No analytics SDK. No third-party network calls of any kind from the
client other than to the project's own Supabase instance and to signed storage
URLs.

Shopping categories are a fixed enum ordering, not a learned model of any
particular shop — which is the point: it is the same every week, so it becomes
muscle memory, and no store-visit data is collected to produce it.

`cook_logs` holds no user reference at all. That makes the "average real-world
cooking time" genuinely anonymous rather than pseudonymous, at the cost of
being impossible to de-duplicate. That is a trade, and it is written down here
rather than hidden.

---

## 7. What is not covered

Read `VERIFICATION.md`. The database perimeter is verified with negative
controls including a deliberate gate break. The client is **not verified at
all** — it has never been compiled. Nothing here has run on a real device or a
hosted Supabase project.

Before production: run the suite against a real Supabase instance, enable leaked
password protection and rate limiting in Auth settings, decide on migration 0006,
and get a second pair of eyes on the storage policies against the real
`storage.foldername()` rather than the local emulation of it.
