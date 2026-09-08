# TASK-055 — Settings redesign

## Brief

Reorganize the existing settings-panel content into six conventional sections
(Radio, Audio, Connectivity, Identity, Appearance, About) as new widgets over the
unchanged `KeryxSettings` model and `SettingsRepository`. Every existing setting
and its validation survives; new appearance preferences are additive with safe
defaults so an old stored fixture still loads without loss.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.6 — sections, connectivity
  showing configured vs effective vs LOCAL-only, and the rule that a
  session-rebuilding setting must not look like an appearance toggle.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §7 (storage key, defaults,
  migration, no reduced write-back, no hot-mic on apply), §1.1 (settings captured
  at construction — changes need host-managed reconstruction), §10 (upgrade).
- PRD UX-FR-060/061/062/064/066, UX-D07/D08; Verification VT-003, VT-005, VT-022.
- ADR-001 §5 / §6 — model/repository reused, widget tree new.

## Approach

Record an old→new inventory of every setting in this dossier; that mapping is the
evidence for UX-FR-061. VT-003 (presentation-only causes zero reconstruction;
each session-affecting field causes exactly one serialized reconstruction) and
VT-005 (legacy fixture loads lossless) are the two load-bearing tests.
`lib/core/settings/**` belongs to TASK-063 and must not be touched here.

## Old → new inventory (UX-FR-061)

| Legacy label | Legacy section | Successor label | Successor section | Field | Session-affecting |
|---|---|---|---|---|---|
| SQUELCH | AUDIO | Squelch | Audio | squelchLevel | no |
| ROGER BEEP | AUDIO | Roger beep | Audio | rogerBeep | no |
| TIME-OUT TIMER | TRANSMIT | Time-out timer | Radio | totSeconds | yes |
| LATCH | TRANSMIT | Latch | Radio | latchMode | no |
| BUSY LOCKOUT | TRANSMIT | Busy lockout | Radio | busyLockout | yes |
| CHARACTER DSP | CHARACTER | Character DSP | Audio | characterDspIntensity | no |
| DIM | CHARACTER | Dim | Appearance | dimMode | no |
| RADIO MODE | NETWORK | Radio mode | Connectivity | mode | yes |
| LOCAL ONLY | NETWORK | Local only | Connectivity | forceLocalOnly | yes |
| REGION | NETWORK | Region | Radio | region | yes |
| RELAY URL | NETWORK | Relay URL | Connectivity | relayUrl | yes |
| TOKEN URL | NETWORK | Token URL | Connectivity | tokenServiceUrl | yes |
| — | — | Effective route | Connectivity | (read-only) | no |
| — | — | Callsign | Identity | identity store | no |
| — | — | Theme | Appearance | keryx.appearance.v1 | no |
| — | — | Audio routing | Audio | device default | no |
| — | — | Version | About | 1.0.0+1 | no |

Same table lives in `lib/features/settings/settings_inventory.dart` and is
asserted by test.

Session-affecting set mirrors `KeryxRadioHost._sessionAffectingFieldsChanged`
(frozen territory — mirrored, not imported).

**Defer-until-idle policy:** if `FloorEngine.isTransmitting` (fallback
`RadioPhase.tx`), a confirmed session-affecting snapshot is queued and
`RadioHost.applySettings` is not invoked until the engine is idle. FIFO
serialize. No hot-mic window. Settings never calls `joinEvent`.

Theme is additive under `keryx.appearance.v1` so a legacy settings blob is
never rewritten as a reduced object. Night-dimming is existing `dimMode`.

Callsign is identity-store only; on-air name updates at the next session
reconstruction / boot (no host identity-apply API).

`lib/app_shell/**` is not edited — TASK-052 mounts this screen.

## Work Log

- [2026-09-08T10:23:29Z] [GB] Session start. Claimed TASK-055, branch `task/TASK-055-gb` off master `b630c4d`. Preflight: new territory `lib/features/settings/**` and `test/features/settings/**`; dossier exists. Fresh widgets over unchanged `KeryxSettings`/`SettingsRepository`. Will not edit `lib/core/settings/**`, `lib/app_shell/**`, or `lib/features/settings_panel/**`.
- [2026-09-08T10:43:59Z] [GB] Implementation complete. Six sections, inventory, VT-003/005/022, defer-until-idle against `FloorEngine.isTransmitting`, additive theme store, sanitized About. Revert-mutation-checked 4 guards (all RED then restored): (1) `sessionAffectingFieldsChanged` always false → reconstruction test Expected appliedSession Actual appliedPresentation; (2) `isLocallyTransmitting` always false → engine test Expected true Actual false; (3) skip confirm → cancel test Expected cancelled Actual appliedSession; (4) skip deferral → TX test Expected deferred Actual appliedSession. `lib/core/settings/**` untouched. → needs_review.
