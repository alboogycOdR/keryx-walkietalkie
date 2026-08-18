# TASK-020 — LAN signaling WebSocket + peer session management (KRX-031, KRX-034)

## Brief
The serverless LAN signaling layer in `lib/services/signaling/`: every device runs a WebSocket server on a random high port (advertised via NSD TXT `p`), peers with matching channel hash exchange WebRTC offer/answer over it, sessions are tracked through presence heartbeats, and the 16-peer soft cap is surfaced. Media itself is TASK-021.

## Spec pointers
- TS §8.3 step 2: "each device runs a loopback-free LAN WebSocket (random high port, advertised in NSD). Peers on a matching channel hash perform WebRTC offer/answer over it. LAN candidates only (host candidates; mDNS ICE)."
- FR-042: "LOCAL is fully serverless: LAN-internal signaling (§8.3), no packets leave the network, works with the internet down."
- TS §8.3 step 3: "N ≤ 16 peers per channel on LAN is the supported envelope (soft cap, warn beyond)." (KRX-034)
- TS §8.6 PRESENCE: "5 s heartbeat; 3 misses = departed" — use TASK-006 codec and TASK-009 peerIds.
- R3: cap guidance "on-display guidance to split channels".

## Intended approach
1. `signaling_server.dart`: `HttpServer` + WebSocket upgrade on port 0 (ephemeral), exposes bound port for discovery advertisement.
2. `signaling_client.dart`: dials peers found by discovery (host:port from TXT), channel-hash handshake first — mismatch → close.
3. `messages.dart`: signaling envelope (hello {peerId, cs, ch-hash, v}, offer, answer, ice) — versioned like the floor protocol; reuse `FloorMessage` PRESENCE via read-only import from `lib/core/protocol`.
4. `peer_sessions.dart`: session registry keyed by peerId — connect dedup rule (lower peerId dials, higher listens — deterministic, avoids double connections), heartbeat scheduling, 3-miss departure, churn events out; `capWarning` state at > 16 peers.
5. Tests: in-process server+client pairs — handshake match/mismatch, offer/answer relay, dedup rule, departure on missed heartbeats (fake clock), cap warning.

## Work Log
