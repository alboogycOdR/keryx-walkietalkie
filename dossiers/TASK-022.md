# TASK-022 — Floor control runtime: arbiter election, leases, lockout, TOT, emergency (KRX-041/042/043)

## Brief
The floor-control brain in `lib/core/floor/`: deterministic arbiter election over peerIds, grant leases with self-healing expiry, busy lockout, TOT warn/cut, TX_REQ retries, and emergency pre-emption — consuming TASK-006 messages over an injected transport and driving the TASK-004 reducer with events. Fully deterministic under an injected clock; TASK-023 soaks it.

## Spec pointers
- TS §8.3 step 4: "Deterministic arbiter = lexicographically lowest peer ID currently in the channel (re-elected on churn); grants are idempotent and time-bounded, so arbiter loss self-heals within 500 ms."
- TS §8.6 rules: "emergency `TX_REQ(prio=1)` pre-empts an active lease. Grants expire; a crashed speaker frees the floor automatically at lease end."
- Timing (locked): lease = TOT + 2 s (default 62 s); re-election settle ≤ 500 ms; TX_REQ retry 150 ms / 3 attempts; floor-idle debounce 750 ms.
- FR-022 busy lockout (default on, setting-driven); FR-023 TOT "Warning chirp at T-5 s, hard cut + penalty tone at 0, floor released"; FR-025 EMG "overrides busy lockout, pins an `EMG` indicator until the sender clears it."

## Intended approach
1. `arbiter.dart`: election = min(peerIds present); role recomputed on every churn event; when local peer is arbiter, it answers TX_REQ (grant if floor free or prio=1 pre-emption; deny BUSY/LOCKOUT otherwise); grants idempotent (re-grant same holder safe).
2. `floor_engine.dart`: per-channel engine — local PTT intent → TX_REQ (retry 150 ms ×3 then give up → denied UX event); on grant → lease timer (TOT+2 s), TX_START broadcast; TOT warn event at T−5 s, cut at 0 (penalty event, TX_END); remote TX_START/END → rxActive events; lease expiry with no TX_END → floor freed.
3. `emergency.dart`: prio=1 flow — pre-empt active lease (arbiter revokes by granting over it), EMG pinned until EMG_CLR.
4. Everything takes `Clock` + `FloorTransport` interfaces; outputs are a stream of `FloorEffect`s (grantTone, denyBuzz, totWarn, totCut, reducer events) so SFX/haptics/UI subscribe without coupling.
5. Deterministic tests: two/three simulated peers over a loopback transport with fake clock — election, re-election ≤ 500 ms after departure, lease expiry self-heal, lockout deny, TOT sequence, EMG pre-emption, retry/give-up.

## Work Log
