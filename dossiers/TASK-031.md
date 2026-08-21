# TASK-031 — Floor-control late-joiner double-grant fix

## Why this task exists
TASK-023's soak harness proved deterministically (seed=-1, three-line
minimal repro, no randomness) that a peer joining mid-transmission which
out-ranks the incumbent arbiter on election can self-grant the floor while
a lease is already live — a real double-grant, not a flaky race. Root
cause: §8.6 defined no message carrying current floor state, so a
late-joining peer has no way to learn a lease is live before it grants
itself.

Read PLAN.md TASK-023's `Review_Findings` (finding (ll)) and the
"Late-joiner floor-state blind spot" paragraph in
`specs/KERYX_Product_Technical_Spec_v1.1.md` §8.6 in full before writing
code. This task implements option A of the three costed alternatives
ORCH scoped there — do not reach for options B or C.

## Intended approach
1. `PRESENCE` gains two optional fields: `holder` (peerId or absent) and
   `lease_remaining_ms` (present iff `holder` is present). No protocol
   version bump — the existing unknown/optional-field tolerance covers
   this. Encode/decode via the existing `FloorCodec`.
2. The arbiter populates these on every outgoing `PRESENCE` from its own
   live floor view — not a cached/stale snapshot.
3. A peer may not self-grant on any `TX_REQ` (including its own
   initial-request-becomes-self-grant path) until it has observed one
   full `FloorTiming.presenceHeartbeat` interval (5 s) since joining,
   UNLESS it has direct proof the floor was idle before any peer joined.
   This must be a genuine elapsed-time gate — not satisfiable by a burst
   of PRESENCE messages arriving faster than real time.
4. A `TX_REQ` during the guard window resolves to `TX_DENY(BUSY)`, never
   a silent drop or a hang.
5. §8.5's ≤50ms TX path and ordinary in-channel PTT after the guard
   window must be provably unaffected — no new await chain on that path.

## Explicitly out of scope
- `test/simulation/**` — do NOT touch TASK-023's harness. If your fix
  doesn't make the unmodified "KNOWN ISSUE" repro pass, the fix is wrong.
- Options B (new CHAN_STATE message) and C (verified round-trip on every
  grant) — both considered and rejected in favour of A; do not reintroduce
  either.

## Work Log

- [2026-08-21T11:05:30Z] [GB] Claimed. Resume check: no GB in_progress/claimed. Preflight: 5 existing entries (protocol 5, floor 8, test/protocol 2, test/floor 2, dossier). Implementing option A: Presence.holder/leaseRemainingMs optional pair; FloorEngine join-guard (elapsed presenceHeartbeat, first-occupant exception); populate outgoing PRESENCE from live lease; adopt inbound holder/lease. Not touching test/simulation/**.
- [2026-08-21T11:28:05Z] [GB] Implemented option A. Codec: optional `holder`/`lease_remaining_ms` pair, idle omits both (golden unchanged), partial pair decodes as idle. Engine: elapsed-time join guard keyed to `FloorTiming.presenceHeartbeat`; first-occupant and all-others-idle-PRESENCE are the idle-proof exceptions; outgoing PRESENCE populated from `_liveHolder` at send time; inbound holder adopted; do not extend live leases from snapshots. In-territory tests cover the KNOWN ISSUE sequence (late joiner BUSY, original still TX). TASK-023 harness left unmodified. Deterministic KNOWN ISSUE now fails its old "both transmitting" expects (fix landed). 500-seed soak 441/500 pass (was 345/500); remaining 59 named in PLAN.md Test_Evidence. Full `flutter test` 520/520, `flutter analyze` clean. → needs_review.
- [2026-08-21T12:48:00Z] [GB] Resume rework (ORCH 2026-08-21T14:15Z). Same branch `task/TASK-031-gb` at `98065b0`. Residual: `rosterSize <= 1` / `_peers.length <= 1` treated constructor-default {self} as aloneness proof before host `updateRoster` (soak delivers roster on the same 2–60 ms delayed channel as PRESENCE; join-PTT at 50 ms races it). Fix: size≤1 is solo proof only after host `updateRoster` (`rosterConverged`); TX_START without a lease installs `TOT+2s` so a crashed speaker cannot be held forever; PRESENCE cannot resurrect an already-expired holder. Not touching `test/simulation/**`.
