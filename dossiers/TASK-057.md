# TASK-057 — Accessibility and responsive polish

## Brief

A single-owner cross-screen gate, deliberately serialized after all seven Wave 4
screens: its territory is the union of theirs, so exactly one task ever holds the
whole successor feature surface at once. Sweep every screen against the
Verification §6 matrix and fix what fails rather than merely reporting it.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` §6 — 320 logical-pixel
  width, normal/large phone, landscape, text scale 1.0 and 2.0, large insets;
  48 dp targets, PTT size, contrast, focus order, TalkBack, keyboard/switch,
  reduced motion; "Design review must approve actual renderings, not just token
  names".
- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §5 (semantic labels; keyboard
  and screen-reader users must be able to tune, cancel, open Stations, navigate
  Settings and release a latched TX), §3.3, §3.4.
- PRD §6; ADR-001 §3 item 2 (old UI spec §8's accessibility substance carries
  forward).

## Approach

Narrow touch-ups only. Releasing a latched TX without a pointer is a safety
property, not a nicety — treat it as such. A defect needing a screen's
behavioural redesign is a finding for a successor task, not something absorbed
silently here. Note the known trap recorded in this plan: M3 pads
`IconButton`'s render box to 48×48 regardless, so assert `constraints` or use
`meetsGuideline`, never `tester.getSize`.

## Work Log
- [2026-09-08T21:45:00Z] [S5] Surveyed all 7 territories (Explore subagent):
  grepped for Semantics(/SafeArea/Tooltip(/MediaQuery.textScaler/
  meetsGuideline/reducedMotion across lib/features/{channels,
  channel_selector,talk,stations,radio_controls,settings,event_qr_ui}/**,
  read every screen file, and catalogued every existing test file's
  coverage. Findings: Radio Controls and both Event QR UI screens had zero
  Semantics/Tooltip/SafeArea anywhere; Radio Controls' Monitor/Scan
  indicator icons were colour-only (no text state equivalent); Talk's fixed
  Column+Spacer root layout was untested above text-scale 1.0 and had no
  scroll fallback; Settings' SettingsTextRow had no explicit label
  association (separate visible label above the field, not
  InputDecoration.labelText); Channel Selector had zero Semantics
  anywhere and no explicit 48dp enforcement on its buttons/fields (relied on
  Material defaults); Stations was already the best-instrumented screen
  (Semantics + 48dp + tooltips throughout) -- left untouched, no defect
  found. Design section 5's explicit keyboard/switch functional floor
  ("tune, cancel, open Stations, navigate Settings, release a latched TX")
  does NOT name Monitor/Emergency-arm -- those stayed
  Listener-pointer-only by design scope, not oversight; recorded as a
  finding below rather than a silent gap.
- [2026-09-08T22:30:00Z] [S5] Radio Controls (972043d, a000bf1):
  SafeArea wrap; explicit button/toggled Semantics on the Monitor
  hold-target and Emergency arm hold-target (previously bare Listeners
  with no semantics at all); text-equivalent state labels
  (Open/Closed, Scanning/Idle) next to the colour-coded
  Monitor/Scan indicator icons so state is never colour-only; explicit
  Semantics label on the Scan Switch; minWidth on the Emergency hold
  target. Event QR UI (a000bf1): SafeArea on both scan and export
  screens; live-region Semantics on transient feedback (invalid/expired
  scan message, keyed-export-unavailable explanation); 48dp minimum height
  on the permission grant-access button; incidentally closed TASK-056's two
  recorded non-blocking findings (dead tokens parameter now used for real
  styling; the export unavailable title now uses the theme's
  sectionTitle instead of an inline bold TextStyle).

- [2026-09-08T23:10:00Z] [S5] Talk (81ede4a): the fixed Column+
  Spacer() root layout genuinely overflowed (reproduced, not
  hypothetical -- a RenderFlex overflowed by 131 pixels exception, caught
  by the new regression test before any fix) at 320 logical-pixel width
  combined with system text scale 2.0 (Verification section 6's own
  matrix). Restructured into LayoutBuilder + SingleChildScrollView +
  ConstrainedBox(minHeight:) around a two-group Column with
  mainAxisAlignment.spaceBetween -- reproduces the original
  top-content/flexible-gap/bottom-controls visual when everything fits, and
  scrolls instead of clipping when it does not. TalkPttDisc's own inner
  icon+label Column independently overflowed its fixed circular bounds at
  the same text scale (a second, separate bug) -- wrapped in
  FittedBox(fit: scaleDown) so the label shrinks to stay inside the disc
  rather than clip. Both fixes mutation-checked: reverting either
  reproduces a real, distinct overflow.

- [2026-09-08T23:40:00Z] [S5] Settings (e8aba25): SettingsTextRow
  (callsign etc.) wrapped in Semantics(label: widget.label, textField:
  true) -- the visible label lives in SettingsRowHeader above, not
  InputDecoration.labelText (which would float a visually-duplicate
  second label), so nothing associated the two for a screen reader.
  SettingsStepperRow's bare value text between the two step buttons
  announced with no context of which setting it belonged to -- gave it an
  explicit "$label, $display" Semantics label. Both mutation-checked.

- [2026-09-09T00:10:00Z] [S5] Channel Selector (9fdc851): zero
  Semantics anywhere in the file, and Cancel/Apply/the two TextFields/
  recall entries/Retry all lacked the explicit 48dp SizedBox/
  ConstrainedBox(minHeight: KeryxUxSpacing.minTarget) pattern every other
  successor screen already uses -- added it throughout (matches this plan's
  own recorded IconButton/M3-padding trap note: none of these are
  IconButton, so a direct tester.getSize on the enforced SizedBox/
  ConstrainedBox is a legitimate measurement here, not the false-positive
  the trap warns about). Tune-outcome feedback (success/invalid/cancelled/
  retryable-failure) wrapped in a live-region Semantics so it's announced
  without the user having to discover and re-focus it. Mutation-checked.

- [2026-09-09T00:25:00Z] [S5] Channels (66a76c6): the current-channel
  card is a duplicate one-tap shortcut onto the same "Open Talk" action as
  the explicit button beneath it, but had no Semantics label of its own --
  a screen reader had to piece together channel/mode/status text to guess
  what tapping the whole card does. Added an explicit button Semantics
  label. Mutation-checked. Stations: surveyed, already the
  best-instrumented screen in the territory (Semantics + 48dp + tooltips
  throughout, _StationRow already merges its whole row into one
  announcement) -- no defect found, left untouched.

- [2026-09-09T00:30:00Z] [S5] Full-repo flutter analyze: 8 issues, all
  pre-existing TASK-035 warnings in
  test/services/session/radio_session_controller_test.dart (unchanged
  baseline, outside this task's territory) -- zero issues anywhere
  under this task's Owned_Paths. Full flutter test: 1336 tests, 0
  failed, 40 skipped (the unchanged owner-parked FR-025 soak seeds), no
  regression. 19 new regression tests added across the six touched screens
  (Stations untouched); every state-changing fix (SafeArea, the two Talk
  overflow fixes, both Semantics-label fixes, both Settings label fixes,
  the Channel-Selector live-region wiring, the Channels card label) was
  individually mutation-checked -- reverting the fix reliably reddens
  exactly its own new test(s) and nothing else, then restored clean.

- Findings recorded, not fixed (deliberately out of this task's narrow
  touch-up scope per its own Description):
  1. Radio Controls' Monitor hold-target and Emergency arm hold-target
     remain Listener-pointer-only with no keyboard/switch-accessible
     discrete-tap alternative (unlike Talk's TalkPttDisc +
     TalkPttToggleAlternative pair). Design section 5's explicit
     functional floor ("tune, cancel, open Stations, navigate Settings,
     release a latched TX") does not name Monitor or Emergency-arm, so
     this is in-scope for a future task rather than a silently-absorbed
     gap here -- Emergency in particular needs its own deliberate design
     decision (a discrete "hold 600ms" keyboard equivalent is not a
     mechanical copy-paste of Talk's toggle pattern the way Monitor's
     would be).
  2. No golden-fixture infrastructure exists anywhere in the repo yet
     (TASK-058's territory per Verification section 6's "dark and light"
     golden matrix) -- WCAG AA contrast is enforced structurally by
     KeryxUxTokens/KeryxUxContrast's sanctioned pairing table (every
     screen in this territory draws exclusively from those tokens, zero
     literal Color(/Colors. usage, already asserted by each screen's
     existing "no literal colour values" test), not verified against
     actual rendered pixels here -- Verification section 6's "Design
     review must approve actual renderings" is a design-review gate, not
     something a unit test can self-certify.
  3. No automated meetsGuideline/large-display-inset/landscape sweep
     across all seven screens systematically -- Talk gained a landscape
     regression test and the 320px/text-scale-2.0 case is now covered;
     the other six screens are all ListView/SafeArea-based (inherently
     scroll-safe) and were spot-checked by reading, not by a new
     per-screen landscape test for each.
