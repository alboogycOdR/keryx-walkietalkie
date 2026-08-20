# TASK-030 — Settings core successor

## Why this task exists
TASK-008 shipped `lib/core/settings/**` and froze it. Its review then proved
six defects empirically (items (1),(2),(5),(6),(7),(8) in that task's
`Review_Findings`) that **cannot be fixed from any dependent's territory**.
TASK-018 (settings-as-back-panel screen) is currently HELD and
un-dispatchable because of them. This task reopens the territory on the
010→011 successor pattern to clear that block.

Read TASK-008's `Review_Findings` in PLAN.md in full before writing code —
it is the authoritative statement of each defect, with the exact probe
results (e.g. the 10-case corrupt-storage probe, and probe case 8 loading
9 channel-memory entries where FR-009 caps at 6).

## Intended approach
1. `load()` becomes total: catch broadly (`on Object`), and **clamp on read**
   rather than relying on constructor asserts.
2. Validation moves to the read path so debug and release agree. Asserts are
   stripped in release; FR-023's 30–120 TOT bound must hold there.
3. Add `dimMode` (FR-108), `mode` (FR-040, default AUTO), VOX
   sensitivity/hang-time (FR-024).
4. `settingsProvider` → `AsyncNotifier` (or explicit invalidation) so it
   re-emits after `save()`/`rememberChannel()`. This is the one TASK-018
   directly depends on.
5. Squelch: persisted `int 0–10` stays; add a normalized `0.0..1.0` double
   accessor for the frozen `BedMixer.gainsFor(double)`. ORCH ruling — do not
   re-litigate, and do not migrate storage.
6. Serialize `rememberChannel()`'s read-modify-write.

## Explicitly out of scope
- `RogerBeepVariant` vs `RogerVariant` divergence (TASK-008 finding (4)) —
  a real FR-062-vs-§7.1 spec conflict needing an ORCH spec amendment first.
  Leave both enums untouched.
- Anything outside `lib/core/settings/**` + `test/core/settings/**`.
  `forceLocalOnly` enforcement (wiring the stored bit to `RadioMode.local`)
  is noted in TASK-008 finding (6) but belongs to a host-wiring task, not
  here — persist the key, do not enforce it.

## Work Log
