# TASK-070 — Lock in channel/privacy-code boundary validation

## Brief

ORCH-created 2026-09-09, a routed finding from TASK-058's round-2 review:
VT-020 requires boundary coverage for channel (1-99) and privacy-code (0-38)
input, but only `tune(0,0)` was ever exercised — the actual edges were
never tested. ORCH read `channel_validation.dart` directly before creating
this task: the logic already appears correct (regex rejects negatives
outright, range check handles the rest). No defect is assumed — add the
tests, confirm the logic really holds at every edge, fix narrowly if not.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` VT-020.
- `specs/KERYX_Mobile_UX_Redesign_PRD_v1.0.md` UX-FR-003.
- TASK-058's Review_Findings §9.9 — the exact gap this closes.
- `lib/features/channel_selector/channel_validation.dart` — read it before
  writing tests; don't guess at the boundary semantics.

## Intended approach

1. Add explicit test cases: channel 1/99 (valid), 0/100 (invalid); code
   0/38 (valid), "-1"/39 (invalid, and confirm "-1" is rejected as
   non-digit text, not parsed as a negative int).
2. If every case passes against the existing implementation, that's the
   whole task — the logic was already correct, now it's proven.
3. If a real boundary bug surfaces, fix it narrowly in
   `channel_validation.dart` only, document exactly what was wrong.
4. Revert-mutation the new tests; full suite + analyze.

## Work Log

### CX9 implementation

Inspection at base `bc91c79` corrects the brief's coverage premise: the
existing five validation tests already included all eight requested boundary
assertions, grouped into broader cases. They remain byte-for-byte unchanged.
Added nine independently named regressions: four channel edges, four privacy
code edges, and a signed-input case. No production defect was found and no
production change is needed.

The `"-1"` case passes text to the public parser, never an integer. Its null
result alone cannot identify which internal guard rejects it: both the digit
gate and the numeric lower bound would reject it. The additional `"-0"` and
`"+1"` assertions distinguish those guards because `int.tryParse` accepts
both and their numeric values are in range. Removing the digit gate must
therefore fail that test. Source inspection confirms the digit gate precedes
`int.tryParse`, so the original implementation rejects `"-1"` before parsing.

### Running the regression tests

Run `flutter test --no-pub test/features/channel_selector/channel_validation_test.dart`.
Use `--plain-name "VT-020 explicit boundaries"` to select the nine new tests.
All existing empty, non-numeric, malformed-input and formatting cases remain.

### Mutation evidence

Each mutation ran the nine new tests with the command above and its
`--plain-name` filter. Each exited 1 with exactly the listed test failing
and the other eight passing. The production file was restored from saved
bytes after each run, with final `git diff --exit-code` confirming no change.

| Temporary mutation | Failing new case |
|---|---|
| Channel minimum 1 → 2 | channel 1 |
| Channel maximum 99 → 98 | channel 99 |
| Channel minimum 1 → 0 | channel 0 |
| Channel maximum 99 → 100 | channel 100 |
| Code minimum 0 → 1 | code 0 |
| Code maximum 38 → 37 | code 38 |
| Code maximum 38 → 39 | code 39 |
| Remove plain-digit regex guard | signed in-range text |
| Return -1 for code text `"-1"` before the digit guard | code -1 |

The last mutation explicitly simulates accepting negative text through both
guards; merely removing the regex would still reject -1 at the range check.

### Final verification

- `flutter test --no-pub test/features/channel_selector/channel_validation_test.dart`:
  14 passed (five existing tests plus nine new cases).
- `flutter test --no-pub`: 1,422 passed, zero failures, 40 existing skipped
  soak seeds. The nine added tests account for the increase over 1,413.
- `flutter analyze --no-pub lib/features/channel_selector/channel_validation.dart test/features/channel_selector`:
  no issues.
- `flutter analyze --no-pub`: eight pre-existing TASK-035 findings, all in
  `test/services/session/radio_session_controller_test.dart`; no new findings.
  Repository-wide analysis is therefore not literally clean; this is the
  same established baseline documented in the preceding reviews.
- `dart format test/features/channel_selector/channel_validation_test.dart`
  and `git diff --check`: formatting applied, whitespace check passed.
- Dependency bootstrap required `flutter pub get`; its automatic changes to
  `pubspec.lock` and `analysis_options.yaml` were restored. Neither is part
  of this change. Production validation is unchanged.
- PLAN coordination commits landed on shared master through
  `scripts/plan_commit.ps1`. Its auxiliary notification helper raised a
  reader-thread error after committing; commit existence and clean PLAN
  diff were checked directly. No code was committed to master.
