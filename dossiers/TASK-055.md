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

## Work Log
