# TASK-043 — Assemble the new hero-PTT home screen, roster screen, and emergency band

## Brief

The convergence task. Once TASK-041 (display strip) and TASK-042 (PTT disc)
are both merged, compose them into `FaceScreen`/`FaceView` per the approved
canvas: header → LCD strip → hero disc → key rail. Move station listing from
the old flip-panel treatment to a full-screen roster route, and add the
emergency orange band. This reopens `lib/features/face/**` +
`lib/app.dart`/`lib/main.dart` — the same territory TASK-037 built, now being
reshaped, not rebuilt from scratch.

## Spec pointers

- Approved canvas — every artboard is normative here: `Main.dc.html` (layout,
  interaction), `Emergency.dc.html` (hard orange band), `Roster.dc.html`
  (full-screen station list, not a flip panel).
- `specs/KERYX_Product_Technical_Spec_v1.1.md` §8.2 (single state source —
  don't invent a second stream; read off the same session/floor state
  `FaceScreen` already reads).
- FR-067 (station flip panel) — its full-screen successor is what
  `Roster.dc.html` specifies; the old flip-panel pattern in
  `glass_flip_controller.dart` is being superseded for station listing.
- `lib/features/face/face_screen.dart`, `face_view.dart`, `housing.dart`,
  `roster.dart`, `station_panel.dart`, `glass_flip_controller.dart`,
  `status_strip.dart` — read all of these before changing any of them; this is
  the file set TASK-037 built and its dossier/Review_Findings in PLAN.md are
  worth reading for context on the existing session/session_host seam.

## Intended approach

1. Confirm TASK-041 and TASK-042 are both `done` before claiming (hard
   dependency — do not start early on assumed interfaces).
2. Read the merged `lib/features/display/**` and `lib/features/ptt/**` APIs as
   they actually landed, not as this dossier speculated they might.
3. Rewire `FaceScreen`/`FaceView` layout to header → display strip → PTT disc
   → key rail. Feed the strip the session's real mode/channel/telltale/status
   data (straight rewire of what already flows to the old glass widget). Feed
   the disc real state (idle/tx/rx/emergency) from the same source the old PTT
   key used, and real TX amplitude from whatever mic-level pipeline TASK-037
   wired; RX amplitude may be a documented proxy value — state this plainly,
   don't block on building real remote metering.
4. Move roster presentation to a full screen (new route or repurposed
   `station_panel.dart` content — builder's call, state which), reachable from
   the rail's `STN` key, returning via back action.
5. Wire the emergency band to whatever signal `emg_key.dart` already surfaces.
6. Register any new route in `lib/app.dart`/`lib/main.dart` additively.
7. Go through every existing `test/features/face/**` test file and replace any
   assertion against a now-deleted widget (knob, grille, flip panel) with an
   equivalent assertion against the new widgets — list every replacement in
   the Work Log below so nothing silently loses coverage.
8. Full suite + `flutter build apk --debug` before submitting.

## Work Log

(empty — fill in as work proceeds)
