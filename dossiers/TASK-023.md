# TASK-023 — Floor-control simulation soak harness (KRX-044)

## Brief
A randomized multi-peer simulation suite in `test/simulation/` that soaks the TASK-022 floor engine over a simulated lossy, reordering, churning transport for 500 seeded runs and asserts the protocol's safety and timing invariants. This is the release-confidence instrument for floor control.

## Spec pointers
- TS §11 KRX-044: "Simulation test harness: 500-run randomized churn/loss soak, zero double-grants; asserts the locked timing constants and peerId election properties of §8.6."
- TS §8.6 timing table (presence 5 s/3 miss, lease TOT+2 s, re-election ≤ 500 ms, retry 150 ms ×3, debounce 750 ms) and peer identity ("uniformly distributed ID space that avoids election thrashing on simultaneous joins").
- NFR-10: "floor protocol simulation suite" is part of the coverage bar.

## Intended approach
1. `sim_transport.dart`: virtual network — per-link delay jitter, loss %, reordering, partition events; fake clock driving everything (no real timers → fast runs).
2. `sim_peer.dart`: N floor engines (TASK-022, read-only import) with generated peerIds (TASK-009 derivation, read-only import), random PTT press/release schedules, random join/leave churn, occasional crash (silent disappearance mid-TX).
3. `soak_test.dart`: 500 runs × randomized seed (seed printed on failure); invariants asserted per run: (a) at no simulated instant do two peers believe they hold the floor; (b) after any churn, a sole arbiter exists within 500 ms; (c) a crashed speaker's floor frees by lease end; (d) elections always pick the lexicographic minimum present; (e) retry/give-up counts match 150 ms ×3.
4. Runtime budget: keep the whole soak under ~2 min in CI (tune peer count ~4–8, run length ~120 simulated seconds).

## Work Log
