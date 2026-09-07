# Handover — 2026-09-07 — Mobile UX Redesign intake

## State: GREEN (planning only, zero code changes, zero builders dispatched)

Takeover of the KERYX Mobile UX Redesign spec pack, per the project owner's
phased instructions. All six phases through "DEVDEPARTMENT planning" are
complete; PLAN.md itself has NOT been touched — this doc is the planning
artifact awaiting the go-ahead to run `/devteam-decompose` for real.

## What changed this session

- Resumed cleanly from a PreCompact checkpoint; verified `master` clean,
  all 44 prior tasks `done`, no active worktrees/branches (see git log).
- Imported the five-doc Mobile UX Redesign spec pack into `specs/`, merged
  the proposed README addition (commit `ae5a960`).
- Drafted and — after two rounds of owner decisions — finalized
  **`docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md`, status ACCEPTED.**
  Read that file for the full conflict analysis; this doc only carries the
  task decomposition it feeds.
- Re-established the baseline: `flutter pub get` clean, `flutter analyze`
  8 pre-existing warnings (all `test/services/session/radio_session_controller_test.dart`,
  TASK-035 debt, unrelated), `flutter test` **1037 passed / 40 skipped
  (named PARKED FR-025 seeds) / 0 failed**, `flutter build apk --debug`
  succeeded (`app-debug.apk`, 232,151,171 bytes, sha256
  `dfcc3ca672d760ef5b928b16c096658e070918e1f3eb9b70d32fd0d7be6ad53b`).
  Incidental `analysis_options.yaml`/`pubspec.lock` auto-upgrades from
  `pub get`/`analyze` were reverted before commit, same discipline every
  builder in this project follows.
- **Owner decisions recorded** (ADR-001 §7): legacy hardware-radio face
  (both the pre-TASK-041 knob/grille and TASK-043's hero-PTT single-screen
  presentation) is deleted outright once the new shell passes real-device
  acceptance — no dormant classic-theme flag. The new pack's screens are
  built fresh against its own Design-spec mockups rather than wrapping
  TASK-043's widgets — only the engine/state machines/data sources are
  reused, not the widget trees. UX-D01–D09 ratified as written, all nine.

## Task decomposition (PROPOSED — not yet written to PLAN.md)

Numbering continues from TASK-044 (last real task). All `Spec_References`
below are illustrative pointers, to be filled out precisely at
`/devteam-decompose` time. Every task's `Owned_Paths` is drawn from real,
already-verified-to-exist directories per the implementation audit; new
directories are new leaf folders, chosen to be trivially disjoint from
everything else in flight.

### Wave 1 — host extraction + design tokens (parallel, zero deps)

| Task | Title | Owned_Paths | Depends_On | Notes |
|---|---|---|---|---|
| TASK-045 | Persistent RadioHost extraction | `lib/core/radio_host/**`, `lib/features/face/face_screen.dart` (hollowed) | — | The load-bearing task. Hoists everything `_FaceScreenState` currently owns (session/floor/audio/service lifecycle) into a persistent, app-scoped layer per ADR-001 §6. High effort, assign the strongest available builder. |
| TASK-046 | RadioViewState presentation projection + telemetry honesty | `lib/core/presentation/**` | TASK-045 | Pure projection from `RadioState`+`FloorEngine` effects to an immutable view-state; typed intents; "unavailable" not synthetic-full-bars per Technical §5.3. |
| TASK-047 | New design system / tokens / theme | `lib/core/theme/**` (reopened) | — | Design spec §2, §3 tokens; dark-first + full light theme. Territorially disjoint from 045/046 — runs concurrently. |

### Wave 2 — app shell (single owner, converges Wave 1)

| Task | Title | Owned_Paths | Depends_On |
|---|---|---|---|
| TASK-048 | Mobile app shell + Channels/Settings navigation | `lib/app_shell/**`, `lib/app.dart`, `lib/main.dart` | TASK-045, TASK-046, TASK-047 |

### Wave 3 — new screens (parallel, disjoint dirs, all depend only on TASK-048)

| Task | Title | Owned_Paths | Depends_On |
|---|---|---|---|
| TASK-049 | Channels screen | `lib/features/channels/**` | TASK-048 |
| TASK-050 | Channel selector / direct-tune workflow | `lib/features/channel_selector/**` | TASK-048 |
| TASK-051 | Talk screen + new PTT presentation | `lib/features/talk/**` | TASK-048, TASK-046 |
| TASK-053 | Stations screen | `lib/features/stations/**` | TASK-048 |
| TASK-054 | Radio controls screen (incl. emergency) | `lib/features/radio_controls/**` | TASK-048 |
| TASK-055 | Settings redesign | `lib/features/settings/**` | TASK-047, TASK-048 |
| TASK-056 | Event QR re-theme | `lib/features/event_qr_ui/**` (new; old `lib/features/event_qr/**` logic reused as a dependency, not modified in place until retirement) | TASK-047, TASK-048 |

Up to 6 builders/lanes can run concurrently here — the largest parallelization
opportunity in the whole plan, same pattern as Wave A/B in the integration
wave.

### Wave 4 — polish, regression, hardware, retirement (serial gates)

| Task | Title | Owned_Paths | Depends_On |
|---|---|---|---|
| TASK-057 | Accessibility/responsive polish | narrow touch-up across `lib/features/{channels,channel_selector,talk,stations,radio_controls,settings,event_qr_ui}/**` | 049,050,051,053,054,055,056 |
| TASK-058 | Full regression pass (new shell; old face temporarily reachable via a dev-only, unshipped compat route per Technical §10) | `test/**` additions only, no production dir | TASK-057 |
| TASK-059 | Physical-device LOCAL testing | `ops/**` runbook updates only | TASK-058 |
| TASK-060 | Physical-device LINKED testing | `ops/**` runbook updates only | TASK-058 |
| TASK-061 | Legacy face retirement (delete old face/PTT/display/settings_panel widget trees + dev-only compat route) | `lib/features/face/**`, `lib/features/ptt/**`, `lib/features/display/**`, `lib/features/settings_panel/**`, `lib/features/event_qr/**` (old), `test/features/{face,ptt,display,settings_panel,event_qr}/**` | TASK-059, TASK-060 |
| TASK-062 | Release acceptance (final regression + release APK) | `android/**` (version bump only) | TASK-061 |

### Independent debt tasks (zero deps, dispatch anytime, recommend early)

| Task | Title | Owned_Paths | Depends_On |
|---|---|---|---|
| TASK-063 | Fix token URL double-append (`/token/token`) | `lib/core/settings/settings_model.dart`, `lib/services/linked/token_client.dart` | — |
| TASK-064 | NFR-11 app size (`--split-per-abi`, fix inert `abiFilters`) | `android/app/build.gradle.kts` | — |
| TASK-065 | RX remote-track handling + real amplitude/quality telemetry source | `lib/services/mesh/rtc_adapter*.dart`, `lib/services/mesh/rtc_adapter_flutter_webrtc.dart` | — |

**21 new tasks total.** TASK-063/064/065 are pure debt paydown, independent
of the redesign — safe to dispatch in Wave 1 alongside TASK-045/047 for a
builder that would otherwise be idle.

## Dependency graph (text form)

```
TASK-045 ─┐
TASK-046 ←┘ (needs 045)         TASK-047 (parallel, no deps)
    │                                │
    └──────────────┬─────────────────┘
                 TASK-048
                    │
      ┌──────┬──────┼──────┬──────┬──────┐
   TASK-049 050   051(+046) 053  054   055(+047) 056(+047)
      └──────┴──────┴──────┴──────┴──────┴──────┘
                    │
                 TASK-057
                    │
                 TASK-058
                  ┌─┴─┐
              TASK-059 TASK-060
                  └─┬─┘
                 TASK-061
                    │
                 TASK-062

TASK-063, TASK-064, TASK-065: no edges, dispatch whenever a lane is free.
```

## Risks and blockers

1. **TASK-045 is a single point of contention** — every downstream task
   depends on it transitively. Recommend the strongest/most experienced
   available builder, high reasoning effort, and a careful review (this is
   exactly the kind of "session/audio/service lifecycle" surgery that has
   produced blocking findings before — TASK-024's hot-mic window, TASK-037's
   three review rounds).
2. **TASK-044's audio fix is still unverified on real hardware** — no phone
   attached this session either. TASK-059/060 (physical-device gates) carry
   double duty: confirming the new shell AND finally confirming TASK-044.
   If audio still doesn't work, that is a TASK-045-adjacent regression to
   triage before blaming the new UI.
3. **"Rebuild fresh" (owner decision) is a real cost, disclosed plainly**:
   TASK-043's hero-PTT/roster/emergency-band widgets, merged one day before
   this session, become throwaway once TASK-061 lands. Nothing is wasted at
   the engine layer, but the widget code does get replaced. Flagging
   this explicitly rather than burying it — it was a deliberate, informed
   choice (see ADR-001 §7 item 2), not an oversight.
4. **FR-025 emergency double-grant stays PARKED** — do not let TASK-054
   (Radio controls / emergency screen) drift into fixing it; it's a floor-
   engine defect, not a presentation one, and remains explicitly out of
   scope by standing owner decision.
5. **Token URL double-append (TASK-063)** currently forces the runbook's
   "TOKEN URL = bare origin" workaround for any LINKED testing. Recommend
   dispatching TASK-063 in Wave 1 so TASK-060 (LINKED hardware test) can
   use real default settings instead of the workaround.
6. **New spec pack + existing UI spec disagreement is now resolved by
   ADR-001**, but PTS P1 and DS §1/§4/§5/§8 still contain the OLD language
   verbatim in `specs/`, per this project's own rule that only ORCH edits
   specs with a changelog note (not silently rewritten in place — ADR-001
   is the changelog; the base spec text is left historically intact per
   Technical spec §10's own instruction not to mutate the old spec, only
   supersede it via ADR). A future light-touch pass could add a top-of-file
   changelog pointer in the old specs to ADR-001 for readability; not done
   here to avoid touching frozen-adjacent spec files without being asked.

## Next 3 steps — concrete, in order

1. **Owner reviews this decomposition** (already reviewed the ADR's three
   ambiguity points; this doc is the follow-on "does the task shape look
   right" check) and gives explicit go-ahead to run the real
   `/devteam-decompose` pass that writes these into PLAN.md with full
   schema (Acceptance_Criteria, Spec_References, Test_Evidence
   requirements, etc.) per AGENTS.md/COORDINATION_PROTOCOL.md.
2. Run `/devteam-decompose`, bump `plan_version`, verify
   `python scripts/validate_plan.py` reports 0 warnings (pairwise-disjoint
   Owned_Paths, including against TASK-063/064/065's small existing-file
   territories).
3. Dispatch Wave 1 (TASK-045, TASK-047, and one or more of TASK-063/064/065
   to keep every available builder busy) — first dispatch only, per the
   takeover instructions' explicit "do not begin parallel implementation
   until path ownership and dependencies are safe."

## Don't touch

- FR-025 emergency-preemption double-grant — still PARKED, no successor
  task, not reopened by this redesign (ADR-001 §5).
- `KERYX_World_Band_Radio_Spec_v1.0.md` — Phase 2, out of scope, referenced
  in `specs/README.md` but not present as a committed file in this repo
  checkout (confirmed absent from `specs/` this session — pre-existing,
  not something this session touched or broke).
