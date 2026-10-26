# CookistryBook

Shared recipe library with URL import, pantry matching, meal planning and
shopping lists. Flutter client, Supabase backend, one codebase from phone to
desktop.

The app includes email/password sign-in, recipe authoring and import, shared
library switching, pantry matching, weekly meal planning, shopping lists, and
guided cooking. Library settings let members inspect the roster, let owners
and admins rename the library, and let any member leave. Owners and admins can
invite people with a single-use code (migration 0009); invitees join with it.

**Read `VERIFICATION.md` before trusting anything here.** It states, per claim,
what was actually executed and what was not. Current Flutter checks pass:
`flutter analyze`, 58 unit tests, and a web production build. The PostgreSQL suite rebuilds the full migration chain and passes 113 assertions (see `VERIFICATION.md`).

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
    (0006 optional hardening lives in supabase/optional/ so it is not applied by default)
    0007_rename_to_libraries.sql         final cookbook/library names
    0008_rebuild_function_bodies.sql     repair renamed SQL function bodies
    0009_library_invitations.sql         hashed single-use invitation tokens + RPCs
    0010_library_creator_can_read_unclaimed.sql   fix: creating a library (INSERT RETURNING)
    0011_library_members_profile_fk.sql  fix: member list embed needs a FK to profiles
  seed.sql                              catalog + three demo tenants
  functions/import-recipe/
    index.ts                            the handler
    guards.ts                           URL / SSRF / stripping (pure, testable)
    guards.test.ts                      55 assertions incl. the SSRF matrix
  tests/
    _local_harness.sql                  LOCAL ONLY — fakes the Supabase platform
    rls_negative_control.sql            113 assertions
    rebuild.sh                          applies 0001-0005, 0007-0011 + seed
    run_tests.sh                        rebuild + run suite (needs local PostgreSQL)
    run_tests_docker.ps1                same, in a throwaway postgres:16 container
    LAST_RUN.txt                        output of the last verified run
    URL_CORPUS_SERVER.txt               26-payload URL corpus, server side

lib/
  main.dart                             Supabase init, keystore session storage
  src/
    core/            env, error translation, quantity formatting
    core/security/   input sanitiser, password policy, secure token storage
    data/models/     enums + row types
    data/repositories/   one per aggregate
    state/           Riverpod graph and controllers
    ui/responsive/   breakpoints + adaptive navigation shell
    ui/screens/      recipe, planner, pantry, shopping, import and cooking views
    ui/widgets/      shared widgets
    platform/        native OS timer handoff
    theme/           Material 3 theme + cooking-mode sizing
test/                                   Dart unit tests

tooling/
  check_url_rules.js / url_corpus.json  client-rule cross-check
```

---

## Running the database locally

```bash
supabase start             # prints API_URL and PUBLISHABLE_KEY
supabase db reset          # applies migrations/ then seed.sql
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<PUBLISHABLE_KEY from supabase start>
```

Run the PostgreSQL suite (rebuilds from zero through migration 0011):

```powershell
powershell -File supabase\tests\run_tests_docker.ps1
```

or `supabase/tests/run_tests.sh` on a host with PostgreSQL.

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

## Pictures, themes and Discover

Migration `0012_recipe_presentation.sql` adds per-recipe `theme`, `accent_color`,
`cuisine`, a background image and up to 12 extra photos (`recipe_images`). Apply
it to a hosted project before shipping this client. The **Discover** tab lists
public recipes only and filters by meal type and cuisine with the category
sliders (also used in the Recipe Box). Cuisine is a closed column because tags
are only readable inside their own library.

API tests: `tooling/recipe-workflow-tests` (run the `*.test.mjs` files with
`node --test`). `simulate-users.mjs [n]` runs n concurrent virtual people
against a local stack; `tooling/ui-personas/personas.mjs [n]` drives the web
build in headless Edge (set `PHOTO_DIR` for fixtures; Edge path is in-script).

## Known trade-offs

**Forks and account deletion.** A fork copies text, ingredient notes, cuisine,
theme, accent, cover, background and every photo (files are copied into the
forker's own storage prefix, so they never depend on the source). Deleting an
account (`delete_my_account`, migration 0013) removes the user's libraries they
alone belong to, recipes they created in shared libraries, and their files;
forks held by other people survive. Apply 0012 and 0013 to the hosted project.

**Large photos are still slow to save.** Re-encoding happens in Dart on the
browser's main thread: four 12 MP phone photos now take ~45 seconds on average
in headless Edge after tuning. Originals over 5 MB are rejected by the bucket,
so resize/re-encode is required. Moving it to native browser image pipelines
would still be the next performance win.

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
