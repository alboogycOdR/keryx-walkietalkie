# TASK-018 — Settings-as-back-panel screen (KRX-016)

## Brief
The settings screen in `lib/features/settings_panel/`, rendered as the radio's back panel / battery hatch — configuration that stays in-world. Exposes the TASK-008 repository: squelch, roger variant, TOT, latch, lockout, DSP intensity, force-LOCAL-only, region, dim mode. Equipment-manual copy voice throughout.

## Spec pointers
- FR-100: "Settings rendered as the radio's **back panel / battery-hatch** screen — even configuration stays in-world (P1)."
- FR-061 squelch knob "actually functions — sets RX gate threshold *and* the resting hiss level"; FR-023 TOT 30–120 s; FR-021 latch; FR-022 lockout default on; FR-046 force-LOCAL toggle; FR-008 region; TS §7.2 DSP Off/Light/Full; DS FR-108 dim auto/manual; FR-062 roger variant picker.
- DS §3: "Interface (panels): Inter, 400/600 … panel body 15/1.5."
- DS §7 copy voice: "Labels are nouns or verbs a radio user knows… The same word survives the whole flow: the key says `MONITOR`, the telltale says `MON`, the setting says *Monitor*." Never "Oops!", no apologies.
- FR-106: 48 dp targets, TalkBack labels, WCAG AA contrast.

## Intended approach
1. `back_panel_screen.dart`: housing-styled screen (screw corners, hatch framing from tokens) — navigated from the face's ⚙ key (route registered here, invoked by TASK-017's key intent via a route name to keep territories clean).
2. Controls: `squelch_control.dart` (mini knob or slider mapped 0–1), enum pickers (roger, DSP, dim), duration stepper for TOT (clamped 30–120), switches (latch, lockout, force-LOCAL) — each round-tripping through the TASK-008 repository providers.
3. Copy per DS §7 (e.g. force-LOCAL: "LOCAL ONLY — nothing leaves this network.").
4. Widget tests: every setting renders current value and persists a change (in-memory store), semantics labels, contrast tokens used (no ad-hoc colours).

## Work Log

- [2026-08-21T04:20:56Z] [S5] Claimed. HOLD lifted by ORCH once TASK-030 (settings core successor) merged as a08c6a5; dimMode/mode keys now round-trip, settingsProvider is a live AsyncNotifier, squelchNormalized has a pinned unit contract. Read `lib/core/settings/**` model/repository/README, `lib/core/theme/theme.dart`, `lib/features/tuning/stepper_button.dart` (widget/theming convention), `lib/features/ptt/key_row.dart` (existing `onSettings` no-op callback in `face_screen.dart` — host wiring, out of this task's territory).
- [2026-08-21T~06:20:00Z] [S5] Implemented `lib/features/settings_panel/**`: `BackPanelScreen` (ConsumerWidget on `settingsProvider`) + reusable `PanelSection`/`PanelToggleRow`/`PanelStepperRow`/`PanelPickerRow<T>`/`PanelTextRow` controls, all ≥48dp and TalkBack labelled, copy per DS §7 in `settings_copy.dart` (with an explicit disclosure on criterion 4's MONITOR/MON example — no such field exists in this task's territory, so the general voice-discipline rule is honoured instead, not a literal Monitor control). dimMode carried per the Description despite finding (mm) flagging FR-108 as unratified — disclosed as a pinned implementation decision. `backPanelRouteName` exported as a named route constant; wiring `face_screen.dart`'s `onSettings` to navigate here is host-level plumbing outside `Owned_Paths` (same convention as TASK-017/024) and intentionally not done here. 16 widget tests added covering rendering, round-trip-through-the-repository for every field (read back via a fresh `SettingsRepository(store).load()`, not provider state), TOT/squelch boundary clamps, corrupt-store and rejected-load handling, and TalkBack semantics-label presence. Hit and fixed two widget-test pitfalls along the way: `ListView`'s `SliverList` only realizes children within the test viewport (needed a taller `tester.view.physicalSize`, same convention as `test/features/face/face_view_test.dart`), and cross-row option-label collisions (`OFF` appears in both ROGER BEEP and CHARACTER DSP) needed disambiguating `Semantics` labels (`'$rowLabel $optionLabel'`) plus key-scoped `find.descendant` lookups in tests rather than relying on bare text/semantics-label matches. `flutter analyze` (whole repo): No issues found. `flutter test test/features/settings_panel`: 16/16 passed. Full suite: 443/443 passed, 0 failed, 0 skipped. Committed to `task/TASK-018-s5` (4c6fc7a). → needs_review.
