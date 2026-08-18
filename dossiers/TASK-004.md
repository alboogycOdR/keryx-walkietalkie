# TASK-004 — Radio state machine reducer + 100%-branch test suite (KRX-003)

## Brief
The single authoritative radio state machine as a pure Dart reducer in `lib/core/state/` — events in, immutable state out, zero IO. Everything else in the app (UI, audio, haptics, network) is a projection of this. 100% branch coverage is a hard NFR.

## Spec pointers
- TS §8.2 (verbatim graph):
  ```
  OFF → BOOT → IDLE(RX) ⇄ TUNING
  IDLE → TX_REQ → TX (granted) → IDLE
  IDLE → RX_ACTIVE (remote floor) → IDLE
  any → LINK_DEGRADED → IDLE|LOCAL_FALLBACK
  ```
  "One reducer owns this. UI, audio, haptics, and network are all projections of it — this is what makes the app testable."
- FR-001/FR-002: channels 1–99, privacy codes 00–38 (`00` = open).
- FR-040: three-position LOCAL/AUTO/LINKED, default AUTO.
- FR-045: degradation is a state + flags, "never a modal error dialog".
- NFR-10: "Reducer/state machine 100% branch."

## Intended approach
1. `radio_state.dart`: sealed/immutable state — phase enum (off, boot, idle, tuning, txReq, tx, rxActive, linkDegraded), channel (1–99), code (0–38), mode (local/auto/linked), flags (noLink, emg, mon, prv label, replay), station count, active speaker.
2. `radio_event.dart`: powerOn/off, tuneDelta, tuneDirect, txRequested/Granted/Denied/Ended, remoteTxStarted/Ended, linkLost/Restored, etc.
3. `radio_reducer.dart`: pure function `(state, event) → state`; illegal transitions return unchanged state (and are enumerated in tests).
4. Riverpod `NotifierProvider` wrapper kept trivially thin (all logic in the pure function).
5. Tests: table-driven full transition matrix + channel/code wrap/clamp; run `flutter test --coverage` and verify 100% branch on the reducer files (paste lcov summary as evidence).

## Work Log
