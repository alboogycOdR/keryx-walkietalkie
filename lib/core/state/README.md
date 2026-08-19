# Radio state projection bridge

`radio_state.dart` contains the framework-free, authoritative `RadioState`,
sealed events, and `RadioReducer`. UI, audio, haptics, and network code read
only reducer state.

`RadioStateBridge` is the single one-way ingress for floor, presence, and
telemetry projections. Construct it with a `FloorEngine` and the host's
`RadioStateController.dispatch`; it forwards existing `DispatchRadio` effects,
maps EMG and arbiter effects, and projects the active speaker from the engine's
lease holder. Presence and telemetry call `updateRoster` and
`updateSignalQuality` on the same bridge. Dispose the bridge with its host.

The reducer never imports Riverpod or calls the bridge, and the bridge never
mutates a `RadioState` directly. This prevents a second rendering state source.
