# KERYX — DEVDepartment Spec Intake

> **Version:** 1.0 | **Date:** 2026-09-07 | **Status:** Ready for owner review and ORCH intake  
> **Baseline:** `master` at `55c51da237c89767806969a52b30cc30e44025c9`.

## 1. Purpose

This package supplies the specification inputs for the existing DEVDepartment workflow. It is not an alternative planning system and must not replace PLAN.md, REVIEW.md, AGENTS.md, the coordination protocol or the existing builder registry.

The requested outcome is a modern, Zello-inspired mobile UI for the KERYX walkie-talkie, retaining the existing communication backend. The current product spec explicitly forbids the proposed navigation direction; therefore the successor ADR and owner approval are prerequisites for development.

## 2. Package manifest

| File | Role |
|---|---|
| `KERYX_Mobile_UX_Redesign_PRD_v1.0.md` | Product scope, requirements, decisions and release boundaries. |
| `KERYX_Mobile_UX_Redesign_Design_v1.0.md` | Information architecture, screens, interaction states, tokens and design gates. |
| `KERYX_Mobile_UX_Redesign_Technical_v1.0.md` | Existing-code mapping, host extraction, lifecycle, migration and planning dependencies. |
| `KERYX_Mobile_UX_Redesign_Verification_v1.0.md` | Traceable acceptance criteria, regression tests and real-device release gates. |

All four files have stable names and numbered sections suitable for PLAN.md `Spec_References` and acceptance-criteria references.

## 3. Import procedure

Place the four specification files in the repository's `specs/` directory. Preserve existing specifications and prototypes. Update `specs/README.md` to include the new documents as proposed successors. Do not overwrite the old UI spec or mutate the current PLAN during import.

The GitHub integration rejected the attempted direct write and branch creation with HTTP 403, so this package has not been committed to the repository. The local files are the deliverable; import them through the authorized local development workflow or an appropriately permitted GitHub connection. No branch, pull request or repository mutation is claimed.

## 4. Handover to ORCH

Use the following prompt in the existing orchestrator terminal after importing the specs:

> You are ORCH for the KERYX repository. Read AGENTS.md, docs/COORDINATION_PROTOCOL.md, CLAUDE.md, autopilot.json, PLAN.md and REVIEW.md fresh from disk. Inspect the current integration branch, git history, active branches/worktrees, all current specs and the four KERYX_Mobile_UX_Redesign_v1.0 companion documents in specs/. Do not assume the prior ChatGPT audit is current.
>
> The project owner requests a modern Zello-inspired mobile interface while preserving the existing radio backend. Treat the four new files as proposed successor specifications. First reconcile their explicit UI direction against the existing product and UI specs, and prepare the necessary versioned ADR and owner decision record. Do not silently override the original P1/P5 or other conflicting requirements. Confirm scope decisions UX-D01–UX-D09 before implementation.
>
> Audit the current source and tests, including the latest real-device audio findings, frozen territories and unfinished tasks. Establish the current baseline. Produce a dependency-ordered migration plan with exact owned paths, task IDs, acceptance criteria, tests and integration gates. Prioritize persistent host extraction before the new navigation shell, preserve the existing floor/session/audio contracts, and prevent concurrent changes to shared files. Any necessary engine defect fix must be a separately scoped successor task.
>
> After owner approval, update PLAN.md through the current authorized coordination procedure and dispatch only eligible tasks to configured, available builders. Do not change the model roster, control mode, branch policy or unrelated project configuration without explicit authorization. Do not merge or start implementation merely because the specs have been imported. Use the existing review gates and require independent tests plus real-device audio verification before release.

## 5. Source audit notes

The inspected source shows that `FaceScreen` owns session/audio/service lifecycle and its disposal tears those resources down. A new persistent host is therefore the first architectural dependency. The existing session has construction-time settings and a channel-scoped retune rebuild. LOCAL roster and placeholder quality data are not sufficient to claim complete LINKED presence or measured signal. QR join requires an active LINKED session. The latest source commit records an Android audio routing fix that still requires physical-device verification.

The new specs deliberately exclude a new contacts/message-history backend from R1. Existing channel memory is not a message history. These boundaries avoid turning a UI redesign into an unplanned product/backend rewrite.

## 6. Source references

- https://github.com/alboogycOdR/keryx-walkietalkie/blob/master/AGENTS.md
- https://github.com/alboogycOdR/keryx-walkietalkie/blob/master/docs/COORDINATION_PROTOCOL.md
- https://github.com/alboogycOdR/keryx-walkietalkie/blob/master/specs/KERYX_Product_Technical_Spec_v1.1.md
- https://github.com/alboogycOdR/keryx-walkietalkie/blob/master/specs/KERYX_UI_Design_Specification_v1.0.md
- https://github.com/alboogycOdR/keryx-walkietalkie/blob/master/lib/features/face/face_screen.dart
- https://github.com/alboogycOdR/keryx-walkietalkie/blob/master/lib/features/face/session_host.dart
- https://github.com/alboogycOdR/keryx-walkietalkie/blob/master/lib/services/session/radio_session_controller.dart
- https://github.com/alboogycOdR/keryx-walkietalkie/blob/master/lib/services/session/station_info.dart
- https://github.com/alboogycOdR/keryx-walkietalkie/commit/55c51da237c89767806969a52b30cc30e44025c9
