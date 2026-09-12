# REGRESSION_V2 — TASK-095 evidence report

v2.0 evidence gate (Verification §5 V2-VT-030, §7 safety, §8 G2/G3;
V2-NFR-005/006). Territory: `test/regression/**`, `ops/FIELD_TEST_V2.md`,
`ops/REGRESSION_V2.md`, `dossiers/TASK-095.md` only — no production files.

## 1. Baseline and test environment (Verification §2)

- Integration tip this branch was cut from: `922418e` (`chore(plan): claim TASK-095 [GB]`), which sits on `e274f57` (TASK-094 approved/merged).
- Toolchain (this worktree): **Flutter 3.41.6** stable, Framework `db50e20168`, Engine `5cdd32777948fa7a648fac915f8da7120ac7e97a`, **Dart 3.11.4**, DevTools 2.54.2.
- Android tooling (from source): AGP **8.11.1**, Kotlin **2.2.20**, **compileSdk 37**, **minSdk 26**.
- Commands (worktree `C:\CLAUDECODE_TOOLSETS\wt-grok-walkietalkie-keryx`):
  - `flutter analyze --no-pub`
  - `flutter test --no-pub`
  - `flutter build apk --release --split-per-abi`

## 2. Full regression suite (`flutter test --no-pub`)

**Result: 1407 passed, 0 failed, 40 skipped.**

The 40 skips are the same PARKED FR-025 soak seeds (`test/simulation/soak_test.dart`), reason string unchanged.

### Count reconciliation vs R2 (PLAN cited 1526; frozen R2 report is 1519)

| Point | Passed | Skipped | Notes |
|---|---|---|---|
| R2 (`ops/REGRESSION_UX_R2.md`, TASK-078) | 1519 | 40 | Frozen R2 evidence. PLAN.md's TASK-095 description cites **1526** — 7 above this report; treated as a planning estimate, not a second measured run. |
| TASK-094 merged (`2a0f572`) | 1379 | 40 | v1 deletions (channels/selector/stations/face/ptt/display/event QR + numbered-room tests) |
| This task | 1407 | 40 | +28 vs TASK-094 |

**−140 from R2 1519 → TASK-094 1379** is the v2 deletion wave (TASK-094), not this task. Those tests were presentation tests of retired modules; surviving behaviour is covered by Talk/Contacts/Groups/Settings tests (see `dossiers/TASK-094.md`).

**+28 this task (all in `test/regression/**`):**

| Count | What |
|---|---|
| 4 | Talk V2-VT-030 `ready` + `dnd_target` goldens (dark/light) |
| 14 | Contacts (empty/populated/requests) + Groups (empty/populated) + My code + phrase goldens (dark/light) |
| 2 | Group-detail goldens (dark/light) |
| 7 | Safety sweep (manifest, analytics, HttpClient, WebSocket, https hosts, directory origin, mute-before-publish) |
| 1 | Overflow system-back from My code (V2-VT-029) |

Layout matrix remains 7 cases (same sizes); call sites renamed Channels/Stations → Contacts/Groups. Real-composition G3 test already present from TASK-093; still green.

Feature-owned goldens under `test/features/{contacts,groups,my_code,onboarding}/goldens/` still exist (out of this territory). The copies frozen here are the V2-VT-030 regression set.

## 3. Analyzer and Android builds (Verification G2, V2-NFR-006)

- `flutter analyze --no-pub` → **No issues found!** (20.3 s).
- `flutter build apk --release --split-per-abi` → **SUCCESS** (314 s Gradle). Artifacts (local, not committed):

| APK | Bytes | SHA-256 |
|---|---|---|
| `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | **45158532** (43.1 MB) | `6C8D9518F65280295EAE1B887D46C54E98D5E73F539A3ECD7F121F311F463DFF` |
| `app-armeabi-v7a-release.apk` | 34992868 (33.4 MB) | `4BAAF28B23EB2DB845A828F7D013D75C38FE2E2A8CD4800ACA3D8A4A493BFA97` |
| `app-x86_64-release.apk` | 51879412 (49.5 MB) | `A617CAF502694E0E7DF89C0754E716C8857393F6DDCBC0B362B39C47ADA0EBD7` |

All three ABIs are under 60 MB (V2-NFR-006). v7a/x86_64 files were deleted after hashing to reclaim disk; **arm64-v8a remains on disk** at the path above for ORCH to hand to the owner. Do not install or send from this task.

R2 arm64 was 44,484,200 bytes; this build is 45,158,532 (+674,332) — v2 identity/directory/contacts/groups code on top of the R2 shell.

## 4. Goldens audit (V2-VT-030)

Every named V2-VT-030 surface has a dark and light fixture under `test/regression/goldens/goldens/`:

| Surface | Files |
|---|---|
| Talk no-target | `talk_no_target_{dark,light}.png` (pre-existing) |
| Talk ready | `talk_ready_{dark,light}.png` (new; online contact, idle phase) |
| Talk nobody-listening | `talk_nobody_listening_{dark,light}.png` (pre-existing) |
| Talk DND target | `talk_dnd_target_{dark,light}.png` (new) |
| Talk alert banner | `talk_alert_banner_{dark,light}.png` (pre-existing) |
| Contacts empty / populated / requests | `contacts_{empty,populated,requests}_{dark,light}.png` |
| Groups empty / populated | `groups_{empty,populated}_{dark,light}.png` |
| Group detail | `groups_detail_{dark,light}.png` |
| My code | `my_code_{dark,light}.png` |
| Phrase screen | `phrase_{dark,light}.png` |

Existing Talk ring-state goldens (idle/requesting/granted/receiving/…) were run **without** `--update-goldens` and still match.

## 5. Layout matrix and system back (Verification §6 / V2-VT-029)

`test/regression/layout_matrix_test.dart` pumps `MobileAppShell` at 320×568, 360×640, 412×915 × text scale 1.0 and 2.0, plus landscape 640×360. Each case: no overflow, Talk/Contacts/Groups tabs ≥ 48 dp, overflow menu on-stage, PTT ≥ 96 dp and reachable.

`overflow_system_back_test.dart` uses real `tester.binding.handlePopRoute()` from overflow Settings, Radio controls, and **My code**; previous tab is kept.

G3: `real_composition_test.dart` boots the real `KeryxApp` against a stubbed directory and reaches Talk — still green.

## 6. Safety sweep (Verification §7, V2-NFR-005)

Recorded by `test/regression/safety_sweep_test.dart`:

- No `READ_CONTACTS` / `WRITE_CONTACTS` / `GET_ACCOUNTS` / `READ_PHONE_NUMBERS` / `READ_PHONE_STATE` / `READ_CALL_LOG` / `READ_SMS` in main/debug/profile manifests.
- `pubspec.yaml` has no analytics SDK (firebase/mixpanel/sentry/amplitude/posthog/appsflyer/adjust).
- `HttpClient()` constructors exist only in `token_client.dart` and `directory_client.dart` (relay/token and directory, both configured from settings / derived from the relay URL).
- `WebSocket.connect` exists only in `presence_transport.dart` (directory presence) and `io_signaling_endpoint.dart` (LAN direct signaling).
- The only hardcoded `https://` host in `lib/` is `keryx.app` (ID share links). Directory origin is `https://<relay-host>/v2`.
- Linked path pre-publishes via `publishMutedAudioTrack()`; both Linked and Mesh flip `track.enabled = true` on `TransmitGranted` and `false` on `EndTransmit`.

Revert-mutation: changing the https-host allowlist expected set to `mutation-should-fail.example` failed the allowlist test (actual `{keryx.app}`); restored.

**Out of territory, not claimed:** Verification §7's "directory logs contain no callsigns, keys or room IDs (`logging_policy.py` PrivacyFilter)" is directory-service / G1, not this client task.

## 7. Device matrix

`ops/FIELD_TEST_V2.md` is the owner runbook for rows A–I with steps and evidence slots. All rows start **NOT RUN**. This task does not install or send the APK.
