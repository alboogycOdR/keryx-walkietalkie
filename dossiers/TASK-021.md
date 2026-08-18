# TASK-021 — WebRTC mesh audio: pre-published muted track, enable-on-grant (KRX-032)

## Brief
Full-mesh LAN voice in `lib/services/mesh/` over TASK-020's signaled sessions: flutter_webrtc peer connections with the spec Opus profile, the muted-track pre-publish trick that makes key-up feel instant, RX gating by floor messages, and data channels opened as the floor-control transport.

## Spec pointers
- TS §8.3 step 3: "Media: full-mesh WebRTC audio. Mesh is safe here because PTT means at most one publisher at a time; N ≤ 16 peers."
- TS §8.5: "the audio track is **pre-published muted** on channel join; PTT grant flips `enabled=true`. Cost: a trickle of silent keepalive overhead; benefit: near-instant key-up — the single most 'real radio' feeling in the app."
- FR-020: "TX attack ≤ 50 ms from grant to live audio (pre-published muted track, §8.5)."
- TS §8.1 codec row: "Opus, mono, 16–24 kbps, 20 ms frames, in-band FEC on, DTX off during TX."
- TS §8.3 step 4: "Floor control: over WebRTC data channels using the protocol in §8.6."
- TS §8.3 step 2: "LAN candidates only (host candidates; mDNS ICE)" — no STUN/TURN servers configured on LOCAL.

## Intended approach
1. `mesh_connection.dart`: wrapper over an abstract `RtcAdapter` (thin interface mirroring the flutter_webrtc surface we use — makes unit tests possible); config: no ICE servers, host candidates; audio constraints AEC/NS/AGC on (APM per §8.1).
2. `mesh_controller.dart`: on channel join — getUserMedia once, add track to every peer connection with `track.enabled=false`; on `TX_GRANT` → `enabled=true`; on release/TOT cut → false. SDP munging or `setParameters` for Opus 16–24 kbps mono, `useinbandfec=1`, `usedtx=0` (document exact SDP transforms).
3. `rx_gate.dart`: remote audio elements gated by TX_START/TX_END (peer whose floor it is), feeding an amplitude tap for the grille (stats-based level polling).
4. `floor_transport.dart`: data channel per peer implementing the transport interface TASK-022 consumes (send/broadcast/stream of decoded `FloorMessage`s via the TASK-006 codec).
5. Tests against `FakeRtcAdapter`: track added muted at join, enabled exactly on grant, disabled on end/cut, SDP transform correctness, gating logic.

## Work Log
