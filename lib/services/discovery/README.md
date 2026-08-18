# LOCAL discovery (KRX-030)

Android NSD via a platform channel plus a UDP broadcast fallback. SFX/UI
consumers read `DiscoveryState.lanTrouble` as the `LAN?` flag — this library
never opens a dialog.

## Service type and TXT

- Type: `_keryx._tcp` (native register uses `_keryx._tcp.`)
- TXT `cs` — callsign
- TXT `ch` — **channel-hash prefix**, never plaintext channel/code
- TXT `v` — protocol version (`1`)
- TXT `p` — LAN signaling port for TASK-020

`ch` is produced by `ChannelHashPrefix.compute(region, channel, code)` =
`hex(SHA-256(utf8("$region|$channel|$code")))[:8]`. This is **not** the §8.7
`roomId` (that is TASK-007). The facade takes an opaque prefix so a later
`roomId` slice can replace this helper without a wire-format fork.

## MulticastLock

Acquired in native `start` (radio on / LOCAL discovery active) and released
in `stop` (power-off). Reference-counted = false; one lock named `keryx-nsd`.

## UDP fallback (TS §8.3 step 5)

After `onTuned()`, a beacon is sent immediately and then every **2 s for 30 s**
to `255.255.255.255:48721`. Payload:

```json
{"v":1,"t":"BEACON","peer":"<peerId>","cs":"<callsign>","ch":"<prefix>","p":<port>}
```

`LAN?` (`lanTrouble`) is set only when NSD never became healthy **and** the
beacon window ended with no Keryx traffic heard. An empty-but-healthy LAN
does not raise `LAN?`.

## Platform channel

- Method: `za.co.basileia.keryx/nsd` — `start` / `stop`
- Event: `za.co.basileia.keryx/nsd_events` — `registered`, `browseStarted`,
  `peerFound`, `peerLost`, `lock`, `error`

`start` args: `peerId`, `callsign`, `channelHashPrefix`, `protocolVersion`,
`signalingPort`, `serviceType`. No `channel` / `code` / `region` keys.

## Android permission matrix (minSdk 26)

| Permission | API | Why |
|---|---|---|
| `INTERNET` | 26+ | UDP beacon + NSD sockets |
| `ACCESS_NETWORK_STATE` | 26+ | Connectivity checks |
| `ACCESS_WIFI_STATE` | 26+ | WifiManager / MulticastLock |
| `CHANGE_WIFI_MULTICAST_STATE` | 26+ | MulticastLock |
| `NEARBY_WIFI_DEVICES` (`neverForLocation`) | 33+ | Wi-Fi awareness / nearby stack on T+ |

Location is **not** requested. Runtime grant for `NEARBY_WIFI_DEVICES` is the
caller's job when the radio powers on (TASK-026 / UI).
