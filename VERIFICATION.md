# Verification report

Every claim below carries a grade. Nothing is rounded up.

- **VERIFIED** — executed here, output observed.
- **OBSERVED** — a faithful re-expression of the rule was executed; the shipped artefact itself was not.
- **INFERRED** — reasoned, not run.
- **UNKNOWN** — not established at all.

The environment had PostgreSQL 16.15 and Node 22.22.2. **It had no Dart or Flutter toolchain, and no network route to obtain one.** That single fact determines most of what follows.

---

## VERIFIED

### Database schema, RLS and engines

Ran in a real PostgreSQL 16.15 instance, from an empty database, in order.

| What | Evidence |
|---|---|
| All six migrations apply cleanly from zero | `supabase/tests/rebuild.sh` — 6/6 files, no errors |
| Seed loads and is idempotent | re-running is a no-op, not a duplicate |
| RLS + engine suite | **88 assertions, 88 PASS, 0 FAIL** — `supabase/tests/LAST_RUN.txt` |

Reproduce with `./supabase/tests/run_tests.sh`.

The suite includes, as separate sections: positive controls (the right user does see their rows), cross-tenant negative controls (reads, writes, tenant-hopping updates), anonymous-role controls, denormalisation-integrity controls, URL/XSS boundary controls, storage object policy controls, engine correctness, and a policy coverage audit.

**Gate-break control (section 3).** RLS was switched off on `pantry_items` on purpose mid-run. The unrelated tenant then reached the data — assertion 3.1 confirms the breach is observable. RLS was re-enabled and forced, and assertion 3.2 confirms access closed again. Without this, the other 87 assertions would only prove that the test could not see anything, which is not the same as proving there was nothing to see.

**A real hole was found and fixed by this process.** The first run failed assertion 2.13: an unrelated user could insert herself as `owner` of another household's library. The bootstrap clause that lets a library's creator claim it used an inline `not exists (select 1 from library_members ...)`. That subquery is itself filtered by the caller's RLS, so a stranger — who cannot see the existing members — got `true` from the emptiness test. Fixed with a `SECURITY DEFINER` function, `public.can_claim_library()`, which checks that the library exists, has no members at all, and was created by the caller. Assertions 2.19–2.22 now cover the path from both directions.

Two further defects were found and fixed: `add_recipe_to_shopping_list` returned only inserted rows and silently ignored rows it merged into existing list entries (it now returns rows touched); and the suite was not idempotent against a used database, so `run_tests.sh` rebuilds first.

### Edge Function security guards

`supabase/functions/import-recipe/guards.ts` holds the URL validation, SSRF address screening and content stripping. It is the module `index.ts` imports, not a copy.

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

### All Flutter and Dart code

**Not one line of Dart in this delivery has been compiled, analysed, or executed.** There was no Dart SDK and no way to fetch one.

That means, specifically, that none of the following is established:

- that `flutter pub get` resolves the dependency set
- that `dart analyze` passes, or even that the code is syntactically valid
- that the widget tree builds
- that the Riverpod provider graph has no cycles and no misuse
- that `test/` passes — those tests have never run
- that the package versions in `pubspec.yaml` expose the APIs used against them. `SecureTokenStorage extends LocalStorage` is written against the supabase_flutter 2.x contract (`initialize`, `accessToken`, `hasAccessToken`, `persistSession`, `removePersistedSession`); that contract has changed between minor versions before and should be checked first.

Two errors of my own were caught by reading rather than by tooling, which is a fair indication of what a compiler would still find: a `FutureProvider` was being written through a non-existent `.notifier` setter (rewritten as an `AsyncNotifier`), and a meaningless extension produced an always-false comparison in the recipe card. Assume more remain.

**First step on a machine with Flutter:** `flutter pub get && dart analyze && flutter test`. Expect to fix things.

### Platform behaviour

Nothing ran on iOS, Android, web, macOS, Windows or Linux. Therefore UNKNOWN:

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

- **As shipped (0004 only):** RLS gates on the membership table. Revoking a member takes effect on their next query. A user in two libraries can touch either within one session.
- **With 0006 applied:** every tenant write must also match the `active_library_id` claim in the JWT. A stolen token is confined to one library, and a client bug that sends the wrong library id fails loudly. The cost is that switching libraries needs a token refresh, and a user with one library gains nothing.

The file documents both sides in its header and is complete and ready to apply. It has **not** been included in the verified 88-assertion run — applying it changes the policy set, and those assertions would need extending first.

A second, smaller one: `cook_logs` carries no user column, so the "average real-world cooking time" figure is genuinely anonymous and genuinely un-deduplicated. One person can log the same recipe ten times. Adding a hashed user column would fix that and make the data pseudonymous rather than anonymous. I have left it anonymous because that is what the brief asked for, but it is a trade, not a free choice.
