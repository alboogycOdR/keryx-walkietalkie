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

### [2026-09-07T19:25:08Z] [GB]

Landed `ad02731` (`fix(android): remove inert ndk.abiFilters for split-per-abi
[TASK-064]`). `ndk { abiFilters += listOf("arm64-v8a") }` and the false
"single-ABI artifact without extra flags" comment are gone; replaced with a
comment pointing at `FlutterPlugin.configureAbiWithoutSplits` and the
`--split-per-abi` command. Signing / minify / proguard / defaultConfig
applicationId-minSdk untouched.

`flutter build apk --release --split-per-abi` exit 0 in 535.2 s Gradle
`assembleRelease`. R8 ran (`mapping.txt` 32,668,068 bytes). Three artifacts,
no leftover fat `app-release.apk`. Each APK's `lib/` contains exactly one ABI
(16 `.so` files, same set as TASK-039's fat APK had per ABI):

| APK | bytes | MiB | uncompressed entries | uncompressed `.so` | sha256 |
|---|---:|---:|---:|---:|---|
| app-armeabi-v7a-release.apk | 34,461,372 | 32.86 | 37,306,660 (35.58 MiB) | 29,535,708 | 9CF3AC97CFBF96E5739AE7077A277B765E74C2F19BE7AB35F55AE6070C96CFC4 |
| app-arm64-v8a-release.apk | 44,872,796 | 42.79 | 47,707,384 (45.50 MiB) | 39,936,432 | E45BA24D37D49AF0BE5EAD6224D9821AB33DB4D9321ADCAF0338387695F6E050 |
| app-x86_64-release.apk | 51,642,828 | 49.25 | 54,486,848 (51.96 MiB) | 46,715,896 | 33C45E4FCFF42BE6BEFD4196504129D2707AAE497B912DAFD59D36C502FE1CAF |

NFR-11 (≤ 60 MB): **all three APKs and their uncompressed entry totals are
under the target.** Field phones (HONOR 90 Lite / two-phone script) take the
arm64 artifact at 42.79 MB vs the previous 114 MB fat APK. Uncompressed `.so`
sizes match TASK-039's inspect figures (arm64 39 / v7a 29 / x86_64 46 MB)
within a megabyte — the win is not shipping the other two ABIs.

`.so` list (identical names in every APK, only the ABI directory differs):
`libapp.so`, `libbarhopper_v3.so`, `libdartjni.so`,
`libdatastore_shared_counter.so`, `libFLAC.so`, `libflutter_soloud_plugin.so`,
`libflutter.so`, `libimage_processing_util_jni.so`,
`libjingle_peerconnection_so.so`, `libnoise.so`, `libogg.so`, `libopus.so`,
`libsurface_util_jni.so`, `libvorbis.so`, `libvorbisenc.so`, `libvorbisfile.so`.

`flutter analyze`: 8 issues, all pre-existing in
`test/services/session/radio_session_controller_test.dart` (TASK-035 debt);
zero in Owned_Paths. Analyzer tried to rewrite `analysis_options.yaml` with
an `exclude: build/** / android/**` block — reverted, not committed.
`flutter test`: 1070 passed / 40 skipped (parked FR-025 soak seeds) / 0 failed.

No new Dart regression test (no test path in Owned_Paths). Discriminating
evidence is the per-APK `lib/` inspect: a fat APK would show three ABI
directories in one zip; each of these shows one.

Ops note (out of territory, for TASK-062 / whoever updates the runbook):
`ops/TWO_PHONE_TEST.md` still says `flutter build apk --release` (fat). The
NFR-11 path is `flutter build apk --release --split-per-abi`; sideload
`app-arm64-v8a-release.apk` on the HONOR 90 Lite.

→ needs_review.
