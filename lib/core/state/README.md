# Radio state projection bridge

`radio_state.dart` contains the framework-free, authoritative `RadioState`,
sealed events, and `RadioReducer`. UI, audio, haptics, and network code read
only reducer state.

`RadioStateBridge` is the single one-way ingress for floor, presence, and
telemetry projections. Construct it with a `FloorEngine` and the host's
`RadioStateController.dispatch`; it forwards existing `DispatchRadio` effects,
maps EMG and arbiter effects, projects the active speaker from the engine's
lease holder, and translates `TotWarn`/`TotCut`/`DenyBuzz` into reducer events
(`TotWarningRaised`/`TotWarningCleared`/`TransmitDeniedIndicated`) so the
face can render DS §6 "TX time-out warning" and "TX denied/busy" from
`RadioState` alone. Presence and telemetry call `updateRoster` and
`updateSignalQuality` on the same bridge. Dispose the bridge with its host.

`isTotWarning` is a TX-phase overlay: set on `TotWarn`, cleared on `TotCut`
or any event that ends TX (`EndTransmit`, `PowerOff`, `LinkDegraded`).
`isTransmitDenied` is a transient flash: set on deny-buzz / denied
`TransmitDenied`, cleared by the next state-changing `RadioEvent`. Neither
field uses a reducer timer.

`LAN?` is deliberately not a `RadioState` field — it is driven by the
KRX-033 UDP-broadcast discovery fallback, which has no task yet.

The reducer never imports Riverpod or calls the bridge, and the bridge never
mutates a `RadioState` directly. This prevents a second rendering state source.
