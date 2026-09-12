# TASK-095 — v2.0 regression pass, device-matrix runbook and release build

## Brief

Evidence gate for v2.0. Complete the golden set of V2-VT-030 for every surface in dark and light, extend the layout matrix and real-back tests to the v2 shell, re-run the R1 safety sweep (§7) including the manifest check for no contacts permission and the network-host allowlist, write `ops/FIELD_TEST_V2.md` as the owner's step-by-step runbook for rows A–I with evidence slots, and produce `ops/REGRESSION_V2.md` with counts reconciled against R2 (1526). Build `flutter build apk --release --split-per-abi`; record the arm64 size (must be < 60 MB) and sha256. Do not install or send anything; ORCH hands it to the owner.

## Spec pointers

- specs/KERYX_v2.0_Verification_v1.0.md §5 (V2-VT-030 full golden set), §6 (device matrix rows A–I, `ops/FIELD_TEST_V2.md`), §7 (safety regression), §8 gates G1–G3; PRD §5, V2-NFR-005/006
- Owned_Paths: test/regression/**, ops/FIELD_TEST_V2.md, ops/REGRESSION_V2.md, dossiers/TASK-095.md
- Depends_On: TASK-094

## Work Log

- [2026-09-12T09:40:00Z] [GB] Claimed. Preflight: `test/regression/**` 38 files; `ops/FIELD_TEST_V2.md` and `ops/REGRESSION_V2.md` NEW; dossier exists.
- [2026-09-12T10:00:31Z] [GB] V2-VT-030 goldens frozen under `test/regression/goldens/` (Talk ready/DND + Contacts/Groups/detail/My code/phrase, dark+light). Layout matrix retargeted to Talk/Contacts/Groups. Overflow system-back covers My code. Safety sweep: no contacts permission, no analytics SDK, HttpClient/WebSocket allowlist, mute-before-publish source contract (mutation-checked). Full suite 1407/0/40. Analyze clean. Release split-per-abi: arm64 45,158,532 bytes (43.1 MB) sha256 `6C8D9518F65280295EAE1B887D46C54E98D5E73F539A3ECD7F121F311F463DFF`. Runbooks written. Ready for needs_review.
