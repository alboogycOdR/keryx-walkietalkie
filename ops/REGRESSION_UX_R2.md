# REGRESSION_UX_R2 — TASK-078 evidence report

UX R2 evidence gate before owner review (ADR-002 §2 O4; Verification §9 G4).
Territory: `test/regression/**`, `ops/REGRESSION_UX_R2.md`, `dossiers/TASK-078.md`
only — no production files.

## 1. Baseline and test environment (Verification §2)

- Integration tip this branch was cut from: `1707a42` (`chore(plan): claim TASK-078 [GB]`), which sits on `a529f3a` (TASK-077 approved/merged).
- Task branch head: `3037f3b` `test(regression): UX R2 shell-frame goldens, measured-glow RX, layout matrix, overflow system-back [TASK-078]`.
- Toolchain (this worktree): **Flutter 3.41.6** stable, Framework `db50e20168`, Engine `5cdd32777948fa7a648fac915f8da7120ac7e97a`, **Dart 3.11.4**, DevTools 2.54.2. This is older than TASK-058's recorded 3.47.2 / Dart 3.13.2 — different PATH on this machine, recorded as observed.
- Android tooling (from source, same as R1): AGP **8.11.1**, Kotlin **2.2.20** (`android/settings.gradle.kts:22-23`), **compileSdk 37**, **minSdk 26**. `java` is not on PATH in this shell; the successful release build used Flutter's Gradle/JDK wiring.
- Commands (worktree `C:\CLAUDECODE_TOOLSETS\wt-grok-walkietalkie-keryx`):
  - `flutter test --no-pub`
  - `flutter analyze --no-pub`
  - `flutter build apk --debug` (failed, disk full — see §3)
  - `flutter build apk --release --split-per-abi` (succeeded)

## 2. Full regression suite (`flutter test --no-pub`)

**Result: 1519 passed, 0 failed, 40 skipped.**

The 40 skips are the same PARKED FR-025 soak seeds (`test/simulation/soak_test.dart`), reason string unchanged.

### Count reconciliation vs R1 (`ops/REGRESSION_UX_R1.md`)

| Point | Passed | Skipped | Notes |
|---|---|---|---|
| R1 (TASK-058, merged) | 1413 | 40 | G4 baseline |
| TASK-077 merged-tree (ORCH, 2026-09-11T14:03:50Z) | 1506 | 40 | UX R2 wave tests landed between R1 and this gate |
| This task | 1519 | 40 | +13 vs TASK-077 |

**+13 this task (all in `test/regression/**`):**
- 2 shell-frame goldens (dark/light)
- 2 measured-glow RX goldens (dark/light)
- 7 layout-matrix cases (320×568 / 360×640 / 412×915 × text scale 1.0 and 2.0, plus landscape 640×360)
- 2 overflow system-back tests (`handlePopRoute()` from Settings and Radio controls)

**+93 from R1 to TASK-077** is the rest of the UX R2 wave (TASK-072..077, 079..081, etc.). None of those tests were deleted or weakened here (`test/` diff vs merge-base is insertions only under `test/regression/**`).

## 3. Analyzer and Android builds (Verification §9 G4)

- `flutter analyze --no-pub` → **No issues found!** (37.7 s). R1 recorded 8 pre-existing TASK-035 warnings; they are gone on this tree.
- `flutter build apk --release --split-per-abi` → **SUCCESS** (334 s Gradle). Artifacts (local, not committed):

| APK | Bytes | SHA-256 |
|---|---|---|
| `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | **44484200** (42.4 MB) | `95812C338435299784D1590F353B420389B3378BAFEE4CBBA817A255A409060B` |
| `app-armeabi-v7a-release.apk` | 34236616 (32.7 MB) | `D08159078A87776BEE7C4D5E9599319F674DE71D924E02B33FFE9631581B83C7` |
| `app-x86_64-release.apk` | 51205080 (48.8 MB) | `33E440CFA66256A5255295B76C1F744DECB26DF287C8AD13B0D9380CD3AE2F7D` |

  v7a/x86_64 files were deleted after hashing to reclaim disk; **arm64-v8a remains on disk** at the path above for ORCH to hand to the owner. Do not install or send from this task.

- `flutter build apk --debug` → **FAILED** three times, all `There is not enough space on the disk` during `:app:mergeDebugNativeLibs` (C: had 0.01–1.2 GB free). Not a compile defect: Dart compile and most Gradle tasks completed; native-lib merge ran out of bytes. A follow-up `--target-platform android-arm64` debug also failed the same way. TASK-077 already built a debug APK on this codebase. Retry debug after freeing several GB on C:.

## 4. Goldens audit (Verification §6)

Existing R1 goldens under `test/regression/goldens/goldens/` were run **without** `--update-goldens`. All 36 original fixtures still match (no pixel drift from the R2 wave). Four **new** fixtures were generated:

| File | What it captures |
|---|---|
| `shell_frame_dark.png` / `shell_frame_light.png` | Assembled R2 shell: KERYX app bar, icon tab strip with accent underline, Talk body (ADR-002 A1). Isolated Talk-state goldens do not include this chrome. |
| `talk_receiving_glow_dark.png` / `talk_receiving_glow_light.png` | Talk RX with `MeasuredMeterLevel(80)` so `TalkPttRing.glowFor` is non-empty. SHA of glow-dark differs from decorative `talk_receiving_dark.png` (`41661540…` vs `542A16C7…`). |

Isolated screen goldens (Channels/Stations/Settings/…) still pump the screen widget, not `MobileAppShell`. That is unchanged from R1 and is why the new shell-frame pair exists.

## 5. Layout matrix (Verification §6)

`test/regression/layout_matrix_test.dart` pumps the assembled `MobileAppShell` at:

- 320×568, 360×640, 412×915 dp × text scale 1.0 and 2.0
- landscape 640×360

Each case: `tester.takeException() == null`, Talk/Channels/Stations tabs ≥ 48 dp, overflow menu on-stage, PTT disc reachable (`ensureVisible`) and ≥ 96 dp shortest side.

## 6. Overflow system back (TASK-077 review carry, ADR-002 A1)

`test/regression/overflow_system_back_test.dart` uses **real** `tester.binding.handlePopRoute()` (never `Navigator.pop` / `pageBack`):

1. Channels tab → overflow Settings → system back → Settings gone, Channels kept.
2. Stations tab → overflow Radio controls → system back → Radio controls gone, Stations kept.

## 7. Findings routed (no production edits)

1. **Fat debug APK** could not be produced on this machine (disk). Owner-review path is the arm64-v8a **release** APK in §3.
2. Isolated R1 screen goldens do not show R2 chrome; covered by the new shell-frame pair rather than regenerating every isolated fixture.
3. DSEG/Barlow glyphs still render as bars in goldens (test font fallback) — pre-existing, same as R1.
