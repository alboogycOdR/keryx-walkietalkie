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

## Round 2 (rework) -- 2026-09-09

REWORK round 1 findings addressed. Summary per finding:

1. **AC1, blocking -- responsive matrix was 1/7, not 7/7.** Added
   `test/features/talk/a11y_matrix_support.dart`: a shared
   `ResponsiveCase`/`kResponsiveMatrix` (320 lp width, larger phone
   411x891, landscape 640x320, 320 lp + text scale 2.0) and an
   `expectResponsiveMatrix(tester, pump)` driver that iterates the matrix
   and asserts `tester.takeException()` is null at each case. Each of the
   seven screens got its own new "TASK-057 round 2" test group wiring its
   own pump/build closure through the shared driver (provider setup
   differs per screen, so the matrix and assertion are shared, the pump
   closure is not) -- Talk, Channels, Channel Selector, Radio Controls,
   Settings, Stations, Event QR UI scan and export screens all now
   exercise the full matrix, not just Talk. This caught two real,
   previously-undetected overflow bugs (see 5/6 below), not just
   confirmed the six screens were already safe.
2. **AC3, blocking -- rendered contrast was asserted by source-grep, not
   by rendering.** Added `expectRenderedContrast`/`expectTapTargets` to
   the same support file, both backed by Flutter's own
   `meetsGuideline(textContrastGuideline)` /
   `meetsGuideline(androidTapTargetGuideline)` against the actual rendered
   frame (via `tester.ensureSemantics()`), not token names. Every one of
   the seven screens now has a dark-theme and light-theme test asserting
   both guidelines pass on the real render. All pass cleanly except one
   pre-existing, out-of-territory exception (see 7 below).
3. **Non-blocking -- AC7 (reduced motion) left unchecked despite being
   swept.** Re-verified: within this task's seven territories the only
   animation is `talk_ptt_disc.dart`'s 160ms `AnimatedContainer`, which is
   a critical state change (matches `KeryxUxMotion`'s "critical" floor
   that stays on even under reduced motion by design) -- there is no
   decorative animation anywhere in scope to suppress. Ticked on the plan
   with this stated, rather than left as a false gap.
4. **Non-blocking -- Channels current-card Semantics missing
   `excludeSemantics: true`.** Fixed in `channels_landing.dart`: without
   it, the card's own child text (channel label, configured/effective
   mode, status) was still individually announced after the composite
   button label -- a duplicated announcement, same pattern as the
   Settings stepper fix already carried. The existing descendant-Semantics
   test still passes (it inspects the widget tree, not the merged
   semantics tree, so `excludeSemantics` doesn't affect it).
5. **Real bug found by the new matrix (Settings): reconnect badge
   overflowed 8px at 320 lp width.** `ReconnectsRadioBadge`'s
   `Row(mainAxisSize: MainAxisSize.min, ...)` inside `SettingsRowHeader`'s
   `Wrap` had an un-flexed `Text` that didn't fit the narrow slot next to
   the row label at 320dp. Fixed with `Flexible` + `TextOverflow.ellipsis`
   around the badge text. Mutation-checked: reverting to a plain `Text`
   reproduces the exact overflow and reddens the new matrix test; restored
   clean.
6. **Real bug found by the new matrix (Event QR UI export): the frozen
   `EventQrExportScreen` (`lib/features/event_qr/**`, out of this task's
   territory -- ADR-001 section 6, "consumed as a dependency, never
   edited") overflows 176px at a small landscape height (640x320).**
   Cannot edit the frozen widget itself. Fixed at the wrapper layer
   instead -- `EventQrUiExportScreen` (in territory) now wraps
   `_body(...)` in a `SingleChildScrollView`, letting the embedded frozen
   screen scroll rather than clip when it doesn't fit, without touching
   its internals. Mutation-checked: removing the `SingleChildScrollView`
   reproduces the exact overflow; restored clean.
7. **Known, accepted exception -- Event QR UI export screen's tap-target
   sweep.** The frozen `EventQrExportScreen` renders a `SelectableText`
   (key `event_qr_link_text`, the join-link display, long-press-to-copy)
   at ~20dp height -- a genuine sub-48dp Android tap-target guideline
   miss, but the widget is frozen out-of-territory code (same file as
   finding 6) and a read-only long-press-to-select text row is a
   different interaction class than a button in the first place. The
   export screen's tap-target test explicitly asserts this is the *only*
   guideline failure present (by counting distinct failure messages and
   matching the known link text), so any other tap-target regression on
   that screen would still fail the test -- this is a scoped, checked
   exception, not a silent skip. Recorded here rather than absorbed
   silently; a permanent fix belongs to whatever task eventually revisits
   `lib/features/event_qr/**` (TASK-061 territory).

Full-repo verification after round 2: `flutter analyze` 8 pre-existing
TASK-035 warnings only (zero new); `flutter test` 1360 total / 0 failed /
40 skipped (was 1336; +24 new tests: 3 per screen x 8 screen-test-files);
`flutter build apk --debug` succeeded. Toolchain auto-edits to
`analysis_options.yaml` and `android/gradle.properties` reverted before
every commit, as in round 1.
