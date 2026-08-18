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
