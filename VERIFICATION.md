# Verification report

Every claim below carries a grade. Nothing is rounded up.

- **VERIFIED** — executed here, output observed.
- **OBSERVED** — a faithful re-expression of the rule was executed; the shipped artefact itself was not.
- **INFERRED** — reasoned, not run.
- **UNKNOWN** — not established at all.

## Current Flutter checks — 2026-10-26

Executed in this workspace with Flutter 3.47.4 and Dart 3.13.3:

| Check | Result |
|---|---|
| `flutter analyze` | PASS — no issues found |
| `flutter test` | PASS — 60 tests |
| `flutter build web` | PASS — compiled with placeholder Supabase build defines |
| Dependency resolution | PASS — 47 packages have newer versions outside current constraints |

The web build's WASM dry run reports that `flutter_secure_storage_web` uses
APIs unsupported by WASM; the normal JavaScript web build succeeds. The build
was not connected to a live Supabase project. Android/iOS runtime behavior is
still unverified.

The PostgreSQL suite was repaired: `rebuild.sh` now applies 0001–0005, 0007–0011 and the seed, and the suite uses the `library_*` names. On 2026-10-26 it ran from an empty database in a postgres:16 container (`supabase/tests/run_tests_docker.ps1`): PASS 113, FAIL 0, including invitations (section 11) and library creation (section 12). It was also applied to a real local Supabase stack (CLI 2.122, `supabase start`), where an end-to-end API run (signup, create library, invite, accept, replay, cross-tenant checks) passed. That run found and fixed a real bug: creating a library failed with 403 (migration 0010). The Flutter web build was then driven in Chrome (Playwright, semantics tree) against that stack: sign-up, auto-created library, member list, creating an invitation and copying its code, sign-up of a second user, a rejected bad code, and joining with the real code (library switches, role Member, no invite button). That found two more bugs, fixed in migration 0011 (member list query had no FK to profiles) and in the library controller (selection was lost after joining). Recipe CRUD, pantry, planner, shopping, cooking mode, image upload and the import-recipe function were not exercised, and nothing ran on hosted Supabase, Android or iOS.

**Pictures, themes and Discover (2026-10-26, updated).** Migrations 0012 and 0013 were applied locally. `flutter analyze` clean; `flutter test` 63 passed; PostgreSQL suite PASS 129, FAIL 0; API tests 6/6 passed including real-size upload limits, full fork copy (text/notes/cuisine/theme/accent/images), account deletion survival semantics for forks, and punctuation-preserving title search. A 30-person concurrent API simulation (`simulate-users.mjs`) still passed with no leaks. The UI persona run was expanded to **30 real browser users** in 3 batches of 10 at 930px (`tooling/ui-personas/personas.mjs`) using real-size photo fixtures: all 30 passed signup → recipe creation with background + multiple photos → publish → discover/category filter → open another's recipe → fork, with periodic delete-account confirmation. Save latency for large-image recipes after tuning (`coverMaxEdge=900`, `coverJpegQuality=68`) averaged ~45.5s in headless Edge. Still not exercised: hosted Supabase migration apply, Android, iOS.

---

## Previous verification evidence

### Database schema, RLS and engines

The earlier report says the pre-rename migrations were run against a real
PostgreSQL 16.15 instance from an empty database. That result does not cover
the current migration chain.

| What | Evidence |
|---|---|
| RLS + engine + invitation suite | PASS 113 / FAIL 0 (`supabase/tests/LAST_RUN.txt`) |
| Current migration chain | VERIFIED 0001–0005, 0007–0011 + seed on PostgreSQL 16 and on local Supabase (0006 moved to supabase/optional/) |

The platform is faked by `_local_harness.sql`; real Supabase behaviour (e.g. `auth.jwt()` email claim) is not verified.

The test SQL contains sections for positive controls, cross-tenant negative
controls, anonymous-role controls, denormalisation integrity, URL/XSS
boundaries, storage policies, engine behavior, and policy coverage.

The previous report describes a gate-break control that disabled RLS on
`pantry_items`, confirmed cross-tenant access, then re-enabled RLS. Do not treat
that as a current test result until the runner is repaired and rerun.

The prior verification report recorded a real RLS hole and its fix: the
bootstrap membership check was replaced with a `SECURITY DEFINER` function,
`public.can_claim_library()`. Its old assertion numbers are not treated as
current suite evidence until the test harness is brought up to date.

The previous report also records fixes to
`add_recipe_to_shopping_list` and to the test runner's rebuild behavior; these
claims likewise need confirmation in the current migration/test setup.

### Earlier Edge Function security-guard results

`supabase/functions/import-recipe/guards.ts` holds the URL validation, SSRF
address screening and content stripping. It is the module `index.ts` imports,
not a copy. These prior results were not rerun in this session.

| What | Evidence |
|---|---|
| Guard suite | **55 assertions, 55 PASS, 0 FAIL** |
| SSRF matrix | 17 private/loopback/link-local/metadata addresses refused; 5 public addresses still accepted |
| Gate-break control | `isForbiddenHost` forced to `return false` → **17 failures**; restored → 55/0 |

Run with `node --experimental-strip-types guards.test.ts`.

**Caveat on the runtime.** This executed under Node 22 with type stripping, not under Deno. The module uses only WHATWG `URL`, `RegExp` and `String`, which are the same in both, so the behaviour is expected to be identical — but "expected" is INFERRED, not VERIFIED. It has never run on Deno Deploy.

### URL boundary, server side

A 26-payload corpus (`javascript:`, `data:`, protocol-relative, embedded credentials, quote-breakout, whitespace-smuggled, empty authority, and legitimate URLs) was run through the real `public.is_safe_http_url` CHECK function in Postgres: **26/26 correct**. Saved at `supabase/tests/URL_CORPUS_SERVER.txt`.

---

## OBSERVED

### URL boundary, client side

The same 26-payload corpus was run through a JavaScript re-expression of the Dart `InputSanitizer.safeUrl` rule: 26/26. Saved at `tooling/URL_CORPUS_CLIENT.txt`.

This validates the **rule**, not the Dart. It also surfaced a genuine divergence worth knowing about: Node's WHATWG `URL` normalises `https:///nohost` to a valid host, whereas Dart's `Uri.parse` leaves the host empty. The port needed an explicit empty-authority guard to match Dart and the server regex. Where the two disagree, the server is the authority, because it is the only one an attacker cannot skip.

---

## UNKNOWN

### Remaining Flutter and Dart unknowns

Static analysis, unit tests, and the web build now pass. These checks do not
establish that user flows work against a real backend, that OAuth is configured,
or that platform-specific secure storage and timer handoff work on devices.
The dependency graph also has 47 packages with newer versions excluded by the
current constraints; no upgrades have been applied.

### Platform behaviour

The web build completed, but no connected app session or native device build
was tested. Therefore UNKNOWN:

- that `flutter_secure_storage` reaches the Keychain / Keystore / DPAPI / libsecret as intended on any of them
- that the Android `SET_TIMER` intent URI is accepted by any particular Clock app
- that `clock-timer://` opens anything on any iOS version — it is documented in the code as not presetting a duration, which is itself from documentation rather than observation
- that the responsive breakpoints produce the intended layout at any real device size. The arithmetic is unit-tested in principle; the rendering is not
- that OAuth redirects resolve, since no provider was configured

### Live Supabase behaviour

The migrations ran against stock PostgreSQL with a hand-built harness (`supabase/tests/_local_harness.sql`) that fabricates `auth.users`, `auth.uid()`, `auth.jwt()`, the PostgREST roles and a minimal `storage` schema. So:

- **VERIFIED:** the policies behave correctly given those semantics.
- **UNKNOWN:** that hosted Supabase's real `auth` and `storage` schemas match the harness closely enough. The storage policies in particular depend on `storage.foldername()` returning path segments without the filename; that behaviour was emulated, not observed against the real implementation.
- **UNKNOWN:** anything about PostgREST's own request handling, rate limits, or the Edge Function deployment pipeline.

---

## Decisions left open

**Migration 0006 is not applied by default, and that is your call, not mine.**

- **Without 0006:** RLS gates on the membership table. Revoking a member takes effect on their next query. A user in two libraries can touch either within one session.
- **With 0006 applied:** every tenant write must also match the `active_library_id` claim in the JWT. A stolen token is confined to one library, and a client bug that sends the wrong library id fails loudly. The cost is that switching libraries needs a token refresh, and a user with one library gains nothing.

The file documents both sides in its header and is complete and ready to apply. It has **not** been included in the verified 88-assertion run — applying it changes the policy set, and those assertions would need extending first.

A second, smaller one: `cook_logs` carries no user column, so the "average real-world cooking time" figure is genuinely anonymous and genuinely un-deduplicated. One person can log the same recipe ten times. Adding a hashed user column would fix that and make the data pseudonymous rather than anonymous. I have left it anonymous because that is what the brief asked for, but it is a trade, not a free choice.
