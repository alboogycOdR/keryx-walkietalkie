# TASK-039 — Release build + app-side two-phone field runbook

## Brief

Relay/token-svc validation moved to TASK-040. This task is the
app-dependent remainder:

1. `flutter build apk --release` with R8 keep rules for flutter_webrtc,
   livekit_client, mobile_scanner, flutter_soloud; signing template;
   `key.properties` gitignored (no real keys).
2. Append the app-side operator script to `ops/TWO_PHONE_TEST.md` after
   TASK-040's marker (do not rewrite §0–§5). LOCAL / LINKED / Event QR,
   FR-cited, SFX named per step. Include the TASK-037 finding (f) manual
   check: ⚙ → `BackPanelScreen`.

Owned_Paths: `android/**`, `ops/TWO_PHONE_TEST.md`, `dossiers/TASK-039.md`.
No Dart.

## Spec pointers

- TS §11 E6 KRX-050 / D2 / NFR-05 / NFR-01 / NFR-02.
- FR-020 PTT, FR-022 busy lockout, FR-023 TOT, FR-025 EMG (parked
  double-grant — log, don't chase), FR-040 modes, FR-041 LOCAL, FR-043/044
  Event QR, FR-045 NO LINK, FR-067 STN flip.
- TASK-036 dart-defines: `KERYX_RELAY_URL` / `KERYX_TOKEN_URL`.
- TASK-034 `SfxProjection` is the SFX source of truth for the script.

## Intended approach

1. `android/.gitignore` for `key.properties` + keystores (root `.gitignore`
   is out of territory).
2. Signing template + debug-keystore fallback so the release build is
   runnable without secrets.
3. Enable R8 (`isMinifyEnabled` / `isShrinkResources`) so keep rules
   actually run; comment each rule with the plugin and why.
4. Append runbook after `<!-- TASK-039 APP-SIDE START -->`.
5. Document the TokenClient origin-vs-`/token` gotcha (TASK-040 note;
   Dart is out of territory).

## Work Log

### [2026-08-22T20:08:00Z] [GB]

Claimed on `task/TASK-039-gb`. Resume scan: no GB in_progress/claimed.
Depends_On TASK-037 + TASK-040 both done.

### [2026-08-22T20:12:00Z] [GB]

Preflight (c8b9872) pasted into PLAN.md. android/** existing (35 files),
ops/TWO_PHONE_TEST.md existing (271 lines), this dossier NEW.

### [2026-08-22T20:25:00Z] [GB]

Signing template (`key.properties.example`, `SIGNING.md`, `android/.gitignore`),
R8 keep rules + minify in `app/build.gradle.kts`, app-side runbook appended.
Next: `git check-ignore` proof, `flutter build apk --release`, full
`flutter test` + `flutter analyze`.
