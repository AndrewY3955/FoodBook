# Runtime Validation Report

**Generated:** 2026-10-26  
**Target:** `C:\Users\acyat\Desktop\FoodBook`

environment:
  docker: AVAILABLE — local Supabase Docker stack and db container reachable  
  node: AVAILABLE — `v24.18.0`  
  playwright: AVAILABLE — `playwright-core` + headless Edge  
  infra-tier: PRIMARY(Docker-based)  
  browser-tier: PRIMARY(Playwright)

startup: PASS — web app served at `http://127.0.0.1:8081/` and responded 200
integration: PASS — exit_code: 0, passed: 6, failed: 0, skipped: 0
e2e: PASS — exit_code: 0, passed: 30, failed: 0, flows: signup → create styled recipe with real-size images → publish → discover/category filter → open shared recipe → fork → periodic account delete
overall: PASS

## Summary

| Step | Status | Exit Code | Details |
|---|---|---:|---|
| Flutter analysis | PASS | 0 | `flutter analyze` clean |
| Flutter unit/widget tests | PASS | 0 | `flutter test` — 63 passed |
| PostgreSQL/RLS suite | PASS | 0 | `supabase\tests\run_tests_docker.ps1` — PASS 129, FAIL 0 |
| API workflow tests | PASS | 0 | 6/6 pass (`recipe-presentation-feed` + `fork-delete-realsize`) |
| UI personas with real-size photos | PASS | 0 | 30/30 pass in three 10-user batches at 930px |

## Real-size UI run evidence

- Script: `tooling/ui-personas/personas.mjs`
- Fixtures: `%TEMP%\fb-photos\photo-*.jpg` (4032x3024 originals) and generated `-web` variants
- Batches:
  - `batch1.log`: 10/10 pass
  - `batch2.log`: 10/10 pass
  - `batch3.log`: 10/10 pass
- Save latency after image tuning (`coverMaxEdge=900`, `coverJpegQuality=68`):
  - avg: **45,529.6 ms**
  - min: 42,303 ms
  - max: 48,328 ms

## Issues found and resolved in this validation cycle

1. UI persona flakiness at 930px (category and file chooser interactions)  
   - Fixed by hardening click/filechooser retries in `tooling/ui-personas/personas.mjs`.
2. Slow real-size image save path  
   - Improved by reducing encode size/quality in `lib/src/core/env.dart`.

## Scope gaps

- Hosted Supabase project migration execution was **not** run in this local validation report.
- Android/iOS runtime behavior remains unverified.
