# TASK-027 — RadioState projection fields + floor→reducer bridge (state successor, follow-up (m))

## Brief
Successor to TASK-004 (010→011 pattern): reopen the now-frozen `lib/core/state/**`
to add the projection fields TASK-017 needs and to reconcile the floor-local
state TASK-022 routes around the reducer. `RadioState` today exposes only
phase/mode/channel/code; DS §6's State Catalogue and TS §8.2 ("UI, audio,
haptics, and network are all projections of it") require it to also expose the
telltale flags, station count, active speaker, and aggregate S-meter. This is
the hard blocker for TASK-017 (face assembly), which must render ONE state
source, not two.

## Spec pointers
- TS §8.2: "One reducer owns this. UI, audio, haptics, and network are all
  projections of it — this is what makes the app testable." (L289) — the
  single-reducer invariant that rules out a separate merge/projection layer.
- DS §6 State Catalogue (frozen by golden tests, KRX-018), L114: `OFF · BOOT ·
  IDLE local · IDLE linked · TUNING · TX granted · TX denied/busy · TX time-out
  warning · RX active (callsign shown) · MONITOR open · SCAN cycling · NO LINK ·
  LAN? · EMG active · REPLAY · VOX armed · PRV keyed channel · Station list flip
  · Pro-locked key` — names every telltale/flag the reducer must project.
- FR-067 (L151): "Presence: `STN n` count on the display; tap to flip … station
  list (callsigns + S-meter per station)." — station count + active speaker.
- FR-069 (L153): "the status-strip meter is aggregate … Signal meter (S1–S9)
  per §8.9 telemetry mapping." — aggregate S-meter field.
- FR-025 EMG, FR-045 NO LINK, FR-065 replay-clear on radio-off.
- TS §8.4: AUTO path switch "at floor-idle only" — the SetMode gate.
- NFR-10 (L389): "Reducer/state machine 100% branch."
- Prior art (NOT spec, read before building): TASK-004 Review_Findings (the
  12 non-blocking items, esp. 2–8) and TASK-022 Review_Findings (the "(m) DID
  BITE" section — EMG/holder/arbiter as floor-local effects; `_peers` has no
  public getter so station count has no source at all today).

## Intended approach
1. Extend `RadioState` with: a telltale set/flags (noLink, emg, prv, replay,
   mon, scan, vox), `stationCount` (int, FR-067), `activeSpeaker` (nullable
   peerId/callsign identity, §6.1 / DS §6), `signalQuality` (aggregate S1–S9,
   FR-069). Keep it immutable; extend `copyWith`.
2. Extend the sealed `RadioEvent` hierarchy with events that set each field
   (e.g. `EmergencyPinned`/`EmergencyCleared`, `ActiveSpeakerChanged`,
   `RosterUpdated`, `SignalQualityUpdated`, telltale toggles). Preserve the
   exhaustive `switch (event)` so a future subclass is a compile error.
3. **Bridge (design decision — ratifiable):** proposal (A) — a thin one-way
   adapter in this territory subscribes to TASK-022's existing sealed effect
   stream (`EmgPinned`/`EmgCleared`/`ArbiterChanged`/…) plus the presence
   (TASK-020) + telemetry (KRX-035) feeds, and translates each into a reducer
   event. One-way only: floor effects → reducer events → `RadioState`; the
   reducer never calls back. Rejected alternative (B): a separate view-model
   merging `RadioState` + `FloorEngine` getters — cements two-source rendering,
   contradicts §8.2, formalises the `_Phase`-vs-`RadioPhase` drift risk.
4. Secondary (scope tight): `PowerOff` edge; split Riverpod host into its own
   file + reducer purity test; `StateNotifier`→`Notifier`; rename
   `LinkRecovered` fallback branch; gate `LinkDegraded` to powered-on phases;
   gate `SetMode` to floor-idle.
5. `tuneDelta`: add ONLY if follow-up (k) (wrap-vs-clamp) is ruled before
   dispatch; otherwise defer. Do not depend on (k).
6. Tests: extend the table-driven `RadioPhase` × event matrix over the new
   events. Evidence = matrix counts (legal edges + illegal no-ops) + `LF/LH`;
   no `--branch-coverage` percentage (LCOV emits no `BRF/BRH` here — see
   TASK-004 rework).

## Work Log
