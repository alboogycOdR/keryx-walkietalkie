# KERYX — Mobile UX Redesign Verification & Acceptance Plan

> **Version:** 1.0 | **Status:** Proposed test contract | **Date:** 2026-09-07  
> **Companions:** Mobile UX Redesign PRD, Design and Technical specifications v1.0.  
> **Changelog:** v1.0 — defines the regression, state, lifecycle, accessibility and real-device gates for the successor interface.

## 0. Verification principles

Tests must prove observable behavior, not merely that a widget renders or a method can be called. The existing radio engine and full test suite are preserved as the regression baseline. Do not delete or weaken a historical test merely because the old UI is retired. Retired visual goldens may be replaced only after the corresponding successor screen/state tests and owner approval are in place. Record the exact baseline commit, toolchain, command, result and any pre-existing failures.

A passing mocked UI test does not establish that real audio, discovery, routing or relay communication works. Hardware validation is a separate release gate. The latest inspected source baseline includes an unverified real-device audio correction; it must be tested rather than assumed fixed.

## 1. Traceability matrix

| Product requirement | Minimum verification |
|---|---|
| UX-FR-001/005 | Navigation through all routes preserves a single host/session and current channel. |
| UX-FR-002/008/045/046 | Configured vs effective mode, unknown presence and unmeasured quality are displayed truthfully. |
| UX-FR-003/004/009/010 | Boundary validation, recall, retune, cancel, failure and race tests. |
| UX-FR-020–030 | Floor-state matrix, press/release, cancellation, latch, disabled states, TOT and hardware-entry parity. |
| UX-FR-040–044 | Live roster, monitor hold, scan, emergency and entitlement tests. |
| UX-FR-060–066 | Old-settings migration, settings reconstruction, privacy, QR and audio preservation. |
| Design §§1–5 | Navigation, responsive, theme, semantics, contrast and state goldens. |
| Technical §§2–10 | Host ownership, lifecycle, serialization, recovery and migration integration tests. |

## 2. Baseline and test environment

Before work begins, ORCH records the current branch/commit, active tasks/worktrees, Flutter/Dart version, Android build tooling, test commands and passing/failing counts. Run `flutter pub get`, `flutter analyze`, `flutter test` and the repository's actual build command. The project README lists `flutter build apk --debug`; release build evidence is also required before release. Do not state that the suite is green based solely on historical PLAN.md notes.

Capture representative baseline screenshots, current settings fixture, channel memory, session start/stop behavior and PTT state transitions. Use fake SessionHost, audio sink, identity and permission/service adapters for deterministic widget tests. Never require real UDP sockets or native plugin availability in a standard Flutter widget test.

## 3. Host and navigation integration tests

### VT-001 — Single instance

Launch the application with instrumented factories. Navigate Channels → Talk → Stations → Settings → Talk repeatedly. Assert exactly one live session, one floor engine, one SFX pipeline and one foreground service. No extra session.start, retune or dispose call occurs due solely to navigation.

### VT-002 — Boot race

Issue overlapping boot requests and complete fake asynchronous operations out of order. Assert one adopted session, no leaked superseded resources, and a final state matching the latest valid intent.

### VT-003 — Settings reconstruction

Change presentation-only preferences and assert no session reconstruction. Change each session-affecting field and assert one serialized reconstruction with correct new settings, no stale listener and proper old-resource cleanup.

### VT-004 — Disposal and background operation

Leave Talk while receiving; verify that audio and service remain active. Dispose the application host once and assert all subscriptions, session resources, timers and audio resources are released. Repeated disposal is safe. A native service-killed event produces the correct off/recovery state.

### VT-005 — Configuration persistence

Load a fixture saved by the legacy version. Verify callsign/identity, region, channel memory, LOCAL-only preference, URLs, sound settings, latch and all relevant settings are retained. Save a new appearance preference and confirm old fields are not dropped.

## 4. PTT and floor-state tests

### VT-010 — State matrix

For each authoritative phase and independent overlay, assert label, icon, color, enabled action and accessibility value. Cover off, boot, idle, tuning, requesting, granted, receiving, denied, degraded, latched, emergency, permission denial and service fault. Assert that a pending request is not shown as granted TX.

### VT-011 — Request/grant/release

Pointer down creates one request. Before grant, no red TX and no published live audio. Grant changes the UI; release sends one release intent. Duplicate pointer-up/cancel and late grant events cannot cause duplicate or stuck transmission.

### VT-012 — Cancellation and disposal

Cover pointer cancellation, route unmount during a hold, app background transition, permission loss and engine replacement. Ordinary hold intent is released safely. An explicitly established latch is handled according to the host contract, not accidentally created or released by navigation. All tests assert authoritative engine state rather than only widget color.

### VT-013 — Busy, TOT and emergency

Busy lockout denies transmission without a false TX indicator. TOT warning and hard cut operate through the existing engine. Emergency activation, arbitration, priority indication and clear behavior are tested separately. The known parked emergency-preemption issue must be reviewed and resolved or explicitly accepted through a separate release decision; no UI test can waive a floor-exclusivity defect.

### VT-014 — Multiple entry points

On-screen PTT, notification PTT and supported hardware controls all reach the same floor engine. Verify that navigating away from Talk does not remove notification actions. Ensure the interaction model for click/toggle notification PTT is not incorrectly treated as a mechanical hold.

### VT-015 — Audio truthfulness

A phase-driven decorative animation is not announced as a measured amplitude. An actual amplitude meter requires a verified audio sample source. No fake network quality or station count is exposed.

## 5. Tuning and connectivity tests

### VT-020 — Input validation

Test channels 1, 99, 0, 100 and non-numeric/empty input; codes 0, 38, -1, 39; cancel; Apply; and last-six recall order/deduplication. Invalid input does not dispatch tuning.

### VT-021 — Retune serialization

Use deferred fake futures to submit rapid A→B→C changes. Complete them in different orders. Assert one deterministic final target, no stale state adoption, no overlapping incompatible transport resources and no false success. Test retune failure after teardown and the documented recovery policy.

### VT-022 — Mode matrix

Test LOCAL, LINKED and AUTO with and without configured relay; force-LOCAL overrides all WAN-capable choices. Display configured and effective mode separately. Verify existing fallback behavior on relay failure. Do not assert unimplemented dual-homing.

### VT-023 — QR transition

Valid, invalid, expired, numbered and supported keyed payload cases. Test scan while LOCAL, LINKED unavailable, force-LOCAL enabled, user cancellation and join failure. Assert no unauthorized WAN call, no silent no-op and a defined post-failure session/channel state. Existing token-service expiry verification remains separate from widget tests.

### VT-024 — Roster and quality

Live join/depart updates while Stations is open. Unknown callsign and missing quality use neutral representations. LINKED roster absence must not render a verified zero-member count. Assert placeholder maximum quality is not displayed as measured full bars.

## 6. Visual and accessibility verification

Create golden fixtures for every significant Talk state, Channels empty/populated, selector, Stations empty/populated, Settings, controls, QR and error states. Cover dark and light themes. Test at a minimum 320 logical-pixel width, a normal phone, a larger phone, landscape, system text scale 1.0 and 2.0, and large display insets. No essential control or state label may be clipped or require horizontal scrolling.

Check minimum 48 dp touch targets, primary PTT size and one-hand access, WCAG AA text contrast, focus order, TalkBack labels, state announcements, keyboard/switch access and reduced-motion behavior. Verify that primary state changes remain understandable without color, sound or haptics. Test a screen-reader-accessible non-drag alternative for PTT and reliable latch release.

Design review must approve actual renderings, not just token names. Existing hardware-face goldens are retained until explicit retirement; successor goldens become the new baseline after owner sign-off.

## 7. Real-device release matrix

Use two physical Android devices meeting the supported minimum SDK and at least one current Android version. Include different manufacturers where available. Record device model, OS, app commit, network configuration and test result.

| Test | Required result |
|---|---|
| LOCAL discovery | Devices discover each other on the same LAN without internet. |
| LOCAL voice A→B and B→A | Audible intelligible audio through the intended output route, correct grant/release and no stuck microphone. |
| Busy and contention | Only one station owns floor; simultaneous requests obey arbitration. |
| Channel change | Both devices tune to matching channel/code and communicate; old channel is no longer incorrectly active. |
| LINKED | Supported relay join and bidirectional voice succeed using the existing backend. |
| Network failure | Actual reconnect/fallback and no-link behavior match documented policy. |
| Audio routing | Speakerphone, wired and available Bluetooth routes are tested as supported; no silent earpiece-only regression. |
| Background | Lock screen, notification action, app switch and return preserve expected session and audio behavior. |
| Long running | Existing TOT, battery and foreground-service requirements are checked against the established test plan. |
| Upgrade | Install old release, save settings, upgrade, and verify no data loss or mandatory account introduction. |

The current baseline's WebRTC routing fix must receive explicit physical-device confirmation. Review remote-track handling if voice remains absent. Do not claim a release candidate is audio-verified based only on emulator, fake adapter or compile success.

## 8. Non-functional and safety regression

Retain the original performance budgets, latency definition, battery bench and network/security requirements. Compare against baseline measurements rather than inventing replacement targets. Verify microphone is muted before publish and after release, floor exclusivity, no recording persistence, LOCAL-only traffic isolation, privacy-code semantics, secret handling, and no unexpected network calls from the new UI.

No new analytics, contacts permissions, address-book upload or message storage is introduced in R1. Crash/error logs must not leak passphrases, tokens or raw private media. Emergency controls must not make unsupported emergency-service or location claims.

## 9. Evidence and exit gates

Each task provides exact commands, test results, changed files, acceptance-criteria mapping and any known limitations. ORCH independently runs relevant tests and reviews ownership. A scoped mock test is not sufficient evidence for a production wiring change; include a test that exercises the actual composition when the defect concerns wiring.

Required gates:
- G0: Owner-approved successor ADR and signed-off scope.
- G1: Baseline inventory, task reconciliation and design approval.
- G2: Persistent host and lifecycle tests passing.
- G3: New UI and state contract tests passing.
- G4: Complete regression suite, analyzer and Android builds passing or documented approved pre-existing exceptions.
- G5: Physical-device LOCAL and LINKED audio, routing, background and contention tests passing.
- G6: Owner acceptance of final UI and explicit release decision.

A blocked or failed gate is reported with evidence; it is not converted to pass through an assumption. No automatic dispatch or merge is authorized by this document.
