# TASK-064 — NFR-11 app size and the inert abiFilters line

## Brief

Pure debt paydown. Two related defects in `android/app/build.gradle.kts`: the
release output is a three-ABI fat APK (~114 MB against NFR-11's ≤60 MB target),
and the existing `ndk.abiFilters` line is inert — TASK-039's review proved by
inspecting the built APK's `lib/` that all three ABIs still ship — while its
comment claims otherwise.

## Spec pointers

- `specs/KERYX_Product_Technical_Spec_v1.1.md` NFR-11 (≤60 MB installed).
- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §5 (carried debt).
- PLAN.md `orchestrator_notes` 2026-08-23T05:55Z — the per-ABI `.so` figures
  (arm64 39 MB / v7a 29 MB / x86_64 46 MB) and the inert-line finding.
- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` §8 ("Compare against
  baseline measurements rather than inventing replacement targets"), §2.

## Approach

`--split-per-abi` (or the equivalent gradle `splits` block), then measure the
real artifacts and report actual per-ABI sizes — if a split still exceeds
60 MB, that is a reported fact with a recommendation, not something to paper
over. Inspect the built artifact's `lib/` as evidence, the same standard that
exposed the inert line. Either make `abiFilters` take effect or delete it; either
way correct the false comment. No manifest, permission, service, signing or
proguard change is authorized here.

## Work Log

### [2026-09-07T19:10:00Z] [GB]

Claimed on `task/TASK-064-gb` (claim fields landed on master via the concurrent
ORCH `1491804` PLAN.md write; blackboard state is `claimed` with this branch).
Preflight (c8b9872) matched expectation: existing `android/app/build.gradle.kts`
+ this dossier.

Root cause of the inert filter, from Flutter 3.47.2
`packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt`:
`configureAbiWithoutSplits` does `abiFilters.clear(); addAll(PLATFORM_ABI_LIST)`
whenever `-Psplit-per-abi` is not set. That runs after the app `defaultConfig`
block, so TASK-039's `ndk { abiFilters += listOf("arm64-v8a") }` was wiped
before packaging. The plugin comment claiming user filters "take precedence"
does not match that `clear()`. The same leftover filter is the configuration
the plugin itself says conflicts with `--split-per-abi`.

Decision: **delete** the `ndk.abiFilters` line (do not try to make it take
effect). A working arm64-only filter would prevent per-ABI artifacts for
v7a/x86_64, which this task requires. Per-ABI packaging is Flutter's
`--split-per-abi` path (`configureAbis` enables AGP `splits.abi` with
`isUniversalApk = false`). No always-on `splits {}` block in this file:
it would fight `configureAbiWithoutSplits` on unflagged `flutter build apk`
(CI debug + `ops/TWO_PHONE_TEST.md` still use the unflagged command) and
those files are out of territory.

Next: gradle.kts edit, then `flutter build apk --release --split-per-abi`,
inspect each APK `lib/`, record byte sizes vs ≤60 MB, full suite + analyze.
