# START HERE

Extract this into an empty folder — `C:\Users\acyat\Desktop\FoodBook` — with
nothing else in it.

```powershell
cd C:\Users\acyat\Desktop\FoodBook
.\setup.ps1
```

That script installs nothing. It finds Flutter, resolves dependencies,
generates the platform folders, and runs static analysis. Re-running it is safe.

---

## What is in this package

| Folder | What it is | State |
|---|---|---|
| `lib/` | The Flutter app, 43 files | **Never compiled.** 17 files have cleared `dart analyze`; the other 26 have not been analysed by anyone |
| `test/` | 2 Dart unit test files | **Never executed** |
| `supabase/migrations/` | 6 SQL migrations | Verified against real PostgreSQL 16.15 |
| `supabase/tests/` | 95-assertion RLS suite | Verified: 95 pass, 0 fail, including two deliberate gate-breaks |
| `supabase/functions/` | The import Edge Function | Guards verified: 55 pass, 0 fail |
| `tooling/` | URL corpus cross-check | 26/26 both sides |

Read **VERIFICATION.md** before trusting any of it. It grades every claim.

---

## What is deliberately not here

`android/`, `web/`, `windows/` — Flutter generates these; `setup.ps1` calls
`flutter create` to produce them. Committing generated scaffolding is how
projects end up wedged on an old Flutter version.

`ios/` — building it requires macOS. Your iPhone route is the web build,
installed from Safari via Share → Add to Home Screen. It behaves like an
installed app: own icon, no browser chrome, no App Store, no yearly fee.

---

## The order of operations

1. **`.\setup.ps1`** — get the project analysing. Expect errors the first time;
   send them back.
2. **Create a Supabase project**, then apply `supabase/migrations/` in numbered
   order and run `supabase/seed.sql`. Do not apply `0006` until you have read
   its header — it is a deliberate open decision, not an oversight.
3. **Deploy the Edge Function** with `verify_jwt` left on.
4. **Run it**: `flutter run -d chrome --dart-define=...` (see README.md).
5. **Host the web build** somewhere free — Cloudflare Pages, Netlify, Vercel —
   and put it behind a password so it is not publicly reachable.
6. **Add to Home Screen** on the iPhone.

Steps 2 through 6 are not written yet as a runbook. Ask for it when step 1 is
clean.

---

## Two decisions still yours

**Migration 0006.** Membership-authoritative (as shipped) means revoking a
member takes effect immediately, and a user in two libraries can touch either
within one session. Claim-pinned (0006 applied) confines a stolen token to one
library but makes switching libraries require a token refresh. The file's header
argues both sides.

**Web session persistence.** `lib/main.dart` currently disables it on web, so
the session ends with the tab. That is the safe choice and it will irritate you
by the third day of using a home-screen app. The alternatives are persisting
with a short refresh-token lifetime plus a strict CSP, or leaving it off.
