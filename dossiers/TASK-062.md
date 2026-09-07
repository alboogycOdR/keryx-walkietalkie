# TASK-062 — R1 release acceptance

## Brief

The final gate: version bump in `pubspec.yaml`, release APK, and the G6 evidence
package in `ops/RELEASE_ACCEPTANCE_R1.md`. Re-runs the complete regression suite
on the retired-legacy tree, executes the Verification §8 safety sweep and the §7
upgrade row on hardware, verifies NFR-11 app size against TASK-064's split
artifacts, and walks PRD §7's nine acceptance items with evidence.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` §9 gates G4/G5/G6, §2
  (release build evidence), §8 (safety regression; no new analytics/contacts/
  message storage), §7 (upgrade row).
- PRD §7, §2.3; `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §10.
- `specs/KERYX_Product_Technical_Spec_v1.1.md` NFR-11 (≤60 MB installed).

## Approach

`pubspec.yaml` is the version source, chosen deliberately over `android/**` so
this task never contends with TASK-064's gradle territory (hence also the
`Depends_On: TASK-064` — the size figure comes from its artifacts). "No
unexpected network call from the new UI" is a real risk in a screen rewrite and
gets an explicit check. The release decision itself is the owner's; this task
hands them the evidence.

## Work Log
