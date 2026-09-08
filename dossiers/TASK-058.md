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

- 2026-09-08T19:15:00Z [S5] Claimed (reassigned from GB, which hit a usage-balance
  exhaustion with no code committed). Ran an Explore sub-agent to map every
  VT-001..VT-024 item and the §6 golden/a11y requirements against the existing
  suite before writing anything. Coverage map (condensed; full detail was in the
  sub-agent's report, not re-pasted verbatim here to keep this file scannable):
  - VT-001, VT-002, VT-003, VT-004, VT-005 — covered (mobile_app_shell_test.dart,
    keryx_radio_host_test.dart, settings_apply/persistence_test.dart).
  - VT-010 — covered, partial on exhaustive per-state enumeration (talk_screen_test
    has a "Design §4 state catalogue" group but not confirmed line-by-line for
    all 14 named states).
  - VT-011, VT-012, VT-013, VT-015 — covered (talk_screen_test.dart, floor_engine_test.dart).
  - VT-014 — PARTIAL/GAP: no test proved on-screen + notification + hardware PTT
    converge on the same floor engine inside the new shell, and none proved
    notification actions survive leaving Talk. Closed in this task (see below).
  - VT-020, VT-021, VT-023, VT-024 — covered (channel_selector/tune_coordinator/
    channel_memory/event_qr_ui/stations test files).
  - VT-022 — covered, partial (only one named test found; full mode-matrix
    parameterization not individually confirmed).
  - §6 goldens — TOTAL GAP: zero golden-image infrastructure anywhere in the repo.
    All prior dark/light and visual-state claims were logic/semantic assertions,
    never a rendered image diff.
  - §9's own explicit ask ("include a test that exercises the actual composition
    when the defect concerns wiring") — GAP: every widget test overrides
    `radioHostProvider` with a scoped `FakeRadioHost`; nothing pumps the real
    `KeryxApp` -> real `radioHostProvider` -> real `KeryxRadioHost` together.
  - Legacy `test/features/face/**` — present, untouched, 7 files / 64 tests.

  Decision: this task's own new tests target the three confirmed gaps
  (real-composition wiring test, VT-014 convergence, golden infra) rather than
  re-proving what's already covered elsewhere — re-litigating already-covered
  VT items here would just be a second, weaker copy of an existing test.
  `ops/REGRESSION_UX_R1.md` names every VT item's covering test explicitly per
  AC 2, including the ones this task did not add new tests for.

  Implemented: `test/regression/real_composition_test.dart` (5 tests — boot,
  VT-001 nav, VT-004 dispose, VT-014 PTT convergence, VT-014 notification
  persists off-Talk; all against the real `KeryxApp`/`KeryxRadioHost`, only the
  5 native-boundary factories faked per Verification §2's own instruction).
  `flutter test` -> 5/5 pass. `flutter analyze` -> clean.

  Implemented: `test/regression/goldens/talk_states_golden_test.dart` — first
  golden-image infra in the repo. 8 significant Talk states x dark+light = 16
  goldens, driven through the real `radioStateProvider` reducer. Generated via
  `--update-goldens`, re-ran clean (16/16) to confirm determinism.

  Next: Channels/selector/Stations/Settings/Radio Controls/Event QR goldens,
  VT-010/022 spot-checks, `ops/REGRESSION_UX_R1.md`, full G4 evidence run.
