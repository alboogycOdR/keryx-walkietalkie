# LOCAL signaling (KRX-031 / KRX-034)

LAN WebSocket session layer for TS §8.3 step 2. No media — that is TASK-021.
Discovery stays in `lib/services/discovery/` (frozen); this package consumes
`DiscoveredPeer.host` / `.port` as already-resolved dial targets and exposes
its bound port for `DiscoveryConfig.signalingPort` (NSD TXT `p`).

## Bind and dial

- Production bind is `InternetAddress.anyIPv4` + ephemeral port (`0`), never
  `127.0.0.1`. That is the "loopback-free LAN WebSocket" in TS §8.3 step 2.
- The bound port is advertised by the caller via TASK-019; this package does
  not open NSD, beacons, or invent addresses.
- Dial targets come only from `DiscoveredPeer.host` + `.port`. Missing host
  skips the dial.
- Dedup: lexicographically **lower** `peerId` dials, higher listens. Stops
  two devices opening a pair of sockets to each other. Extra connections for
  an already-sessioned peer are closed.

FR-042 (fully serverless, packets stay on the LAN): no STUN/TURN URLs, no
cloud host, no default gateway lookup. ICE that is not a LAN candidate is
dropped on send and receive (see below).

## Wire: signaling envelope (spec-silent, pinned here)

TS §8.3 names offer/answer/ICE over the LAN WebSocket but never a JSON
shape. TASK-006's `FloorCodec` is floor-control only (`TX_REQ` / `GRANT` /
…). Envelope v1, disclosed so TASK-021 does not guess:

```json
{"v":1,"type":"offer","from":"<peerId>","to":"<peerId>","payload":{"sdp":"..."}}
```

| Key | Meaning |
|---|---|
| `v` | Envelope version. v1 is `1`. Unknown versions ignored. |
| `type` | `hello` \| `hello-ok` \| `offer` \| `answer` \| `ice-candidate` |
| `from` / `to` | §8.6 `peerId`. `to` is required on offer/answer/ICE. |
| `payload` | Type-specific object (below). |

`type` (not `t`) is the discriminator against `FloorCodec`, which uses `t`.

| `type` | `payload` |
|---|---|
| `hello` / `hello-ok` | `{cs, ch}` — callsign + channel-hash prefix (same `ch` as NSD TXT) |
| `offer` / `answer` | `{sdp}` — SDP string. Non-LAN `a=candidate:` lines are stripped. |
| `ice-candidate` | `{candidate, sdpMid?, sdpMLineIndex?}` |

Unknown `type`, missing fields, and malformed JSON decode to `null`
(ignored, never thrown) — same forward-compat posture as `FloorCodec`.

Handshake: dialer sends `hello`; listener replies `hello-ok` after `ch`
matches. Mismatch or `v` ≠ 1 closes the socket. Channel matching is a
second check; discovery already filtered, but a crossed wire must not
complete a session.

## Wire: presence (not invented)

Heartbeats are TASK-006 `PRESENCE` via `FloorCodec.encode` on the **same**
socket, not a new signaling `type`:

```json
{"v":1,"t":"PRESENCE","peer":"<peerId>","cs":"<callsign>","seq":1}
```

Cadence is `FloorTiming.presenceHeartbeat` / `presenceMissesToDepart`
(5 s / 3 misses = 15 s). A session with no `PRESENCE` for 15 s is
departed. Discovery `peersLost` also tears the session down.

## LAN ICE (TS §8.3 step 2)

Allowed: `typ host`, and candidates whose address is an `.local` mDNS
hostname. Rejected: `typ srflx`, `typ relay`, `typ prflx`. Same filter
on send, receive, and SDP `a=candidate:` lines.

## Soft cap (KRX-034 / R3)

`N ≤ 16` remote sessions is the supported envelope. Connections past 16
are still accepted (soft); `SignalingState.capWarning` is true when
`sessions.length > 16`. UI copy / "split the channel" is not this task.

## Test seam

`InProcessSignalingHub` pairs in-process channels — no real sockets.
`IoSignalingEndpoint` is the production `dart:io` `HttpServer` +
`WebSocket` bind. Unit tests use the hub plus `VirtualClock`.
