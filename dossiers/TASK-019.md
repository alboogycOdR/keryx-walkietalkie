# TASK-019 — NSD discovery platform channel + MulticastLock lifecycle (KRX-030)

## Brief
Native Android NSD (mDNS) through a platform channel: Kotlin register/browse of `_keryx._tcp` with the spec TXT records, MulticastLock held only while the radio is on, a Dart facade in `lib/services/discovery/` with peer-found/lost streams, plus the UDP broadcast beacon fallback and the `LAN?` state output. First link in the android/** chain (TASK-026 follows it; never concurrent).

## Spec pointers
- FR-041: "LOCAL discovery via mDNS/NSD, service type `_keryx._tcp`, TXT records: `cs` (callsign), `ch` (channel hash prefix), `v` (protocol version). MulticastLock acquired while radio is on."
- TS §8.1: "Android NSD (mDNS) via platform channel; `_keryx._tcp` — Native reliability > plugin roulette."
- TS §8.3 step 1: TXT carries "a *channel-hash prefix* (privacy: full channel/code never broadcast in plaintext)"; step 2: the signaling WebSocket's "random high port, advertised in NSD" — add a `p` (port) TXT record for TASK-020.
- TS §8.3 step 5: "if mDNS is filtered (guest networks, AP isolation), a UDP broadcast beacon fallback runs at 2 s intervals for 30 s after tuning; if both fail the display shows `LAN?` and the troubleshooting card (still no dialog)."
- TS §8.8: "MulticastLock only while LOCAL discovery active." NFR-04: discovery ≥ 98% within 3 s (design target).

## Intended approach
1. Kotlin (`android/app/src/main/kotlin/...`): `NsdHandler` using `NsdManager` — register service (name = peerId prefix) with TXT {cs, ch, v, p}; discover+resolve peers; `WifiManager.MulticastLock` acquire/release tied to explicit start/stop calls from Dart; EventChannel streaming found/lost/resolved.
2. Manifest: `CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_NETWORK_STATE`, `NEARBY_WIFI_DEVICES`/location as required by SDK level (document the 26+ matrix).
3. Dart `lib/services/discovery/`: `DiscoveryService` interface + `NsdDiscoveryService` over MethodChannel/EventChannel; model `DiscoveredPeer {peerId?, callsign, channelHashPrefix, version, host, port}`.
4. `broadcast_fallback.dart`: pure-Dart UDP beacon (RawDatagramSocket broadcast, 2 s × 30 s window post-tune) with same peer model; `DiscoveryState` output incl. `lanTrouble` (→ `LAN?` flag consumer).
5. Channel-hash prefix computation: hash of (region|ch|code) truncated — reuse convention documented in TASK-007's derivation (comment-coordinate; no cross-territory import of rooms lib is fine since it's `lib/core/rooms` — read-only import IS allowed, imports aren't edits).
6. Tests: Dart facade with mocked channels (found/lost sequencing, lock lifecycle calls, fallback timing with fake clock).

## Work Log
