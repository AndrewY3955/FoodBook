# CookistryBook

Recipe box, pantry matcher and meal planner. Flutter client, Supabase backend,
one codebase from phone to desktop.

**Read `VERIFICATION.md` before trusting anything here.** It states, per claim,
what was actually executed and what was not. In short: the database layer is
verified against a real PostgreSQL instance with an 88-assertion suite; the
Edge Function guards are verified with a 55-assertion suite; **no Dart was ever
compiled**, because the build environment had no Flutter toolchain.

---

## Layout

```
supabase/
  migrations/
    0001_init_extensions_enums.sql      enums, URL and path safety functions
    0002_core_tables.sql                tables, constraints, indexes
    0003_functions_triggers.sql         security helpers, integrity triggers, engines
    0004_rls_policies.sql               the security perimeter
    0005_storage_policies.sql           private cover-image bucket
    0006_optional_active_claim_hardening.sql   OPTIONAL — read the header first
  seed.sql                              catalog + three demo tenants
  functions/import-recipe/
    index.ts                            the handler
    guards.ts                           URL / SSRF / stripping (pure, testable)
    guards.test.ts                      55 assertions incl. the SSRF matrix
  tests/
    _local_harness.sql                  LOCAL ONLY — fakes the Supabase platform
    rls_negative_control.sql            88 assertions
    rebuild.sh                          drop, recreate, migrate, seed
    run_tests.sh                        rebuild then run — use this one
    LAST_RUN.txt                        output of the last verified run
    URL_CORPUS_SERVER.txt               26-payload URL corpus, server side

lib/
  main.dart                             Supabase init, keystore session storage
  src/
    core/            env, error translation, quantity formatting
    core/security/   input sanitiser, password policy, secure token storage
    data/models/     enums + row types
    data/repositories/   one per aggregate
    state/           Riverpod graph and controllers   (Phase 2)
    ui/responsive/   breakpoints + adaptive navigation shell  (Phase 2)
    ui/screens/      the views  (Phase 3)
    ui/widgets/      shared widgets
    platform/        native OS timer handoff
    theme/           Material 3 theme + cooking-mode sizing
test/                                   Dart unit tests — NEVER EXECUTED

tooling/
  check_url_rules.js / url_corpus.json  client-rule cross-check
```

---

## Running the database locally

```bash
supabase start
supabase db reset          # applies migrations/ then seed.sql
```

To run the verification suite against a plain PostgreSQL instance instead
(which is how the 88 assertions were produced):

```bash
./supabase/tests/run_tests.sh
```

`run_tests.sh` rebuilds from zero first. The suite is not idempotent — section
8c commits rows — so running the SQL file directly against a used database will
produce spurious failures in section 1.

`_local_harness.sql` fabricates `auth.users`, `auth.uid()`, `auth.jwt()`, the
PostgREST roles and a minimal `storage` schema. **Never run it against a real
Supabase project**; it would shadow platform objects.

---

## Running the Edge Function tests

```bash
cd supabase/functions/import-recipe
node --experimental-strip-types guards.test.ts
```

Deploy with `supabase functions deploy import-recipe`. Leave `verify_jwt` at its
default of on — the function fetches caller-supplied URLs, and unauthenticated
that is an open proxy.

---

## Building the client

Configuration is passed at build time. Nothing is checked in.

```bash
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY

# Release
flutter build apk    --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build ipa    --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build web    --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build macos  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build windows --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

The anon key is public by design: it identifies the project and carries the
`anon` role. Authority comes from RLS. The `service_role` key must never appear
in this application.

Before anything else, on a machine that has Flutter:

```bash
flutter pub get && dart analyze && flutter test
```

Expect to fix things. See `VERIFICATION.md` for why.

### Platform prerequisites

- **Android** — `minSdkVersion 23` for `flutter_secure_storage`'s
  EncryptedSharedPreferences. Below that the plugin degrades silently, which is
  the worst of both worlds.
- **iOS/macOS** — Keychain entitlement; the OAuth redirect scheme
  `app.cookistrybook://login-callback` must be registered before enabling Apple or
  Google sign-in.
- **Linux** — `libsecret-1-dev` at build time and a running secret service at
  run time.
- **Web** — session persistence is disabled deliberately. See SECURITY.md.

---

## Demo data

**Not applied on the hosted project.** `seed.sql` Part B inserts directly into
`auth.users`, which hosted Supabase rejects; only Part A (the global ingredient
catalog) is loaded. The identities below describe the local harness.

Three fixed identities, chosen so the isolation tests have something to prove:

| Who | Cookbook | Role |
|---|---|---|
| Ana | Rivera Family Cookbook | owner |
| Ben | Rivera Family Cookbook, plus his own | member / owner |
| Cara | Cara's Cookbook | owner, no link to Rivera |

Cara exists to be locked out. Four recipes, one of them public; a pantry stocked
so that Shakshuka lands at exactly 5 of 6 required ingredients (83%).

`seed.sql` inserts directly into `auth.users`, which is fine for
`supabase db reset` and staging. On a hosted project, create the accounts
through the Admin API instead — a direct insert skips identity-row creation and
the seeded accounts cannot sign in with a password.

---

## Known trade-offs

**Recipe save is not atomic.** PostgREST has no multi-statement transaction, so
saving a recipe replaces its children with delete-then-insert across several
requests. If the process dies between them, the recipe is left without
ingredients rather than with duplicated ones — recoverable by saving again.
Moving the whole save into one plpgsql RPC would make it atomic and is the
obvious next hardening step.

**Cook-time analytics cannot be de-duplicated.** `cook_logs` has no user column,
so the average is genuinely anonymous and one person can log the same recipe ten
times. See VERIFICATION.md.

**Cookbook switching versus token pinning.** Migration 0006 is written, complete,
and deliberately not applied. Its header explains both sides.

**The import parser is a guess.** Social captions are written for people. The
parsed result always lands in the editable form and is never saved on the user's
behalf.

**iOS timer handoff does not preset a duration.** There is no public URL scheme
for it. `NativeTimer.isSupported` exists so the UI can say so rather than
offering a button that quietly does nothing.
