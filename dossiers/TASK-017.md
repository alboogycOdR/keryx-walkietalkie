# TASK-017 — Face assembly: layout, status strip, station-list flip, app wiring (KRX-010 assembly)

## Brief
Compose the whole radio face in `lib/features/face/` and own the app entry (`lib/main.dart`, `lib/app.dart`): housing material, the DS §4 vertical allocation, status strip (aggregate S-meter, STN, BAT, mode), station-list panel flip, orientation handling — and wire every child widget (glass, knob, steppers, PTT, grille) to projections of the TASK-004 reducer. This is the integration task for all E2 widgets; it runs only after they are all done, so it may touch their public APIs read-only (imports), never their files.

## Spec pointers
- TS §6.1 face diagram (status strip / glass / grille / knob+steppers / key row / PTT / EMG side key) and "Landscape supported (radio rotates to 'brick on its side' layout); portrait is primary."
- DS §4: "status strip 6% · glass 18% · grille 26% · control cluster 22% · PTT 22% · safe area 6%. PTT owns the bottom fifth… Controls never occupy the top third." Housing: shell-700 + 2–3% noise + single top-left light source.
- FR-067: "Presence: `STN n` count on the display; tap to flip the display panel to the station list (callsigns + S-meter per station). Flip back automatically after 5 s (P5: the face stays a radio)."
- FR-069: "The **status-strip meter is aggregate**: while a station transmits it shows that station's link; at idle it shows the worst active peer link… **Per-station meters** appear in the station-list panel flip."
- TS §8.2: "UI… are all projections of it" — no widget owns radio state.
- PT: full page layout, strip markup, 9-bar S-meter.

## Intended approach
1. `face_screen.dart`: Column with the exact allocation fractions from `KrxLayout`; housing decoration (noise overlay via a const SVG-free painter, light-source gradient) per DS §4.
2. `status_strip.dart`: S-meter bars (aggregate logic as pure function of peer telemetry list + active speaker), STN count (tap → flip), battery, mode label.
3. `station_panel.dart`: flip animation (snap curve) replacing the glass region with callsign list + per-station meters; 5 s auto flip-back timer.
4. `face_view_model.dart`: Riverpod providers projecting reducer state → display model (TASK-012), knob/stepper intents → reducer events, PTT intents → floor-request events (stubbed until TASK-022 lands — face must remain functional standalone with LOCAL-less simulated grant for now, clearly marked).
5. `lib/app.dart` + `lib/main.dart`: MaterialApp shell (dark, no Material chrome), boots to face.
6. Widget tests: allocation ratios, flip/auto-flip-back, aggregate meter selection (TX vs idle worst-peer), landscape variant renders.

## Work Log
