# TASK-058 — Full regression pass and G3/G4 evidence

## Brief

The evidence gate before any hardware testing. Assembles the cross-cutting
integration and golden coverage no single screen task owns: VT-001–VT-005
against the assembled shell, VT-010–VT-015 and VT-020–VT-024 coverage, and
goldens for every significant state in both themes. Its territory contains no
production directory on purpose — a failure becomes a finding routed back to the
owning task, which is the whole reason this gate exists separately.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` §0 (never delete or
  weaken a historical test), §2 (record exact commit, toolchain, commands,
  counts, pre-existing failures), §3/§4/§5 (the VT suites), §6 (goldens, dark and
  light), §9 gates G3/G4 and "a scoped mock test is not sufficient evidence for a
  production wiring change".
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §1 (Tests row), §10
  (dev-only compat harness may still exist at this point).
- ADR-001 §5 — the 40 named PARKED FR-025 soak skips stay skipped, reasons intact.

## Approach

The legacy face and its tests are still alive here; TASK-061 deletes them after
the hardware gates. Report the 8 pre-existing TASK-035 analyzer warnings
explicitly as the known documented exception rather than absorbing them into a
"clean" claim.

## Work Log
