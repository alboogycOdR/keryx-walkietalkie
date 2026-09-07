# ADR-001: Mobile UX Redesign — Successor Scope & Reconciliation

**Status:** Proposed — awaiting owner decision (see §7 "Owner decisions required" — this ADR is not yet in force)
**Date:** 2026-09-07
**Author:** ORCH
**Supersedes (conditionally, pending acceptance):** the hardware-radio-face mandate in `KERYX_Product_Technical_Spec_v1.1.md` P1/§6.1 and `KERYX_UI_Design_Specification_v1.0.md` §1/§4/§5/§8, for the main-screen navigation and presentation layer only.
**Does NOT supersede:** anything listed in §5 below.

## 1. Context

The project owner requested a Zello-inspired transformation of KERYX's UI, and
supplied a five-document spec pack (`KERYX_Mobile_UX_Redesign_{PRD,Design,Technical,
Verification,Intake}_v1.0.md`, imported into `specs/` by this ADR's companion
commit). Those documents were themselves prepared with the explicit
understanding that they conflict with the current, ratified product and UI
specs and require an ADR before any implementation — every one of the five
files says so.

Separately, and *before* this spec pack arrived, the project already approved
and merged a first UI-redesign wave: **TASK-041/042/043 ("Phase 2 PTT
redesign")**, merged 2026-09-06 (`f65ac1e`/`76efb2c`), which removed the knob
and grille, replaced them with a hero PTT disc + amplitude ring, added a
pushed full-screen `RosterScreen`, and added an emergency band — all still
inside the single `FaceScreen`, still launched from a plain `Navigator.push`,
no persistent host, no `Channels`/`Talk` shell. That wave's own PLAN.md entry
already flagged the spec debt this ADR now closes: *"a formal spec amendment
updating §5/§1 to match should be written once this wave merges... tracked
here as ORCH-owed debt."* This ADR is that amendment, extended to also cover
the new, larger pack.

## 2. What actually conflicts

### 2.1 Existing spec text that blocks the new direction

| Existing requirement | Text | New pack's position |
|---|---|---|
| PTS **P1** (§2, binding on every ticket) | *"Radio first, app second. Deliberate skeuomorphism... No Material minimalism, no bottom nav bars, no hamburger menus on the main face."* | PRD §2.1 wants a persistent two-destination (`Channels`/`Settings`) shell — structurally a bottom-nav/tab pattern, exactly what P1 forbids. |
| PTS §6.1 | The face *is* the single primary screen; radio-console layout is the reference implementation for KRX-010–018. | Design spec §1: *"An instrument, not an interface"* is replaced by *"calm, modern and functional... no simulated screws, molded textures, seven-segment glass or faux hardware housing."* |
| DS §1, §4, §5 | Fixed layout-grid percentages, knob+glass as the only two "signature elements," *"if a fourth 'special' element appears in a build review, cut it."* | Design spec §0/§3.1: faceplate tokens, LCD styling, grille and knob explicitly declared "not mandatory." |
| DS §8 (non-negotiable accessibility floor) | *"Faceplates may change materials and hue but never layout, contrast ratios, or control positions."* | New shell changes control positions and layout by definition (new screens, new navigation). |
| DS §6 | 18-state catalogue is frozen by golden tests; *"No state may use a dialog, toast, or snackbar."* | New pack introduces genuinely new screens (Channels, Talk, Stations, Settings-as-mobile-settings) that are not panel-flips on one face. |

The second research pass (existing-spec audit) found **no clause anywhere**
in either existing spec that reserves room for an alternate presentation —
P1 and DS §1/§4/§5/§8 are stated as unconditional. So this is a real,
total conflict on the *visual/navigational* layer, not a misreading.

### 2.2 What does NOT conflict

Every one of the five new documents is independently explicit, repeatedly,
that the *engine* is untouched. Representative quotes (full inventory in the
audit reports, available on request):

- PRD §0: *"this is a successor product direction, not permission to rebuild
  the communication backend."*
- Technical §0: *"The existing `RadioReducer`, `FloorEngine`, session
  transports, discovery, signaling, LiveKit and token-service contracts
  remain authoritative. No speculative backend API may be introduced to make
  a mockup work."*
- Technical §5.1: *"The UI must not dispatch `TransmitGranted`, `EndTransmit`
  or remote floor events to simulate a result."*
- PRD §2.3: *"No... replacement transport protocol, replacement floor
  engine..." is authorized.*

This matches CLAUDE.md's and the project owner's own framing exactly
("preserving the existing KERYX communication engine"). **No reconciliation
is needed on the engine/session/audio/protocol/privacy layer** — the new pack
and the old PTS agree completely there. §5 below still enumerates it
explicitly, per the takeover instructions, so nothing is silently assumed.

### 2.3 A wrinkle the new pack could not have known about

The new pack's Intake doc (§5) and Technical spec (§1.1) both independently
re-derive, from reading the source fresh, that `FaceScreen` owns the session
and a persistent host must be extracted first — **and this is correct**, confirmed
independently by this session's own implementation audit (see the "State
Projection risk assessment" in the implementation-audit report). Good sign:
two independent audits (the pack's authors, and this session's) converged on
the same architectural finding without collaboration.

What the pack could not have known: TASK-043 already shipped a `RosterScreen`
(full-screen, `ValueListenable`-driven live roster) and an emergency band,
both still living inside `FaceScreen`'s ownership. The new pack's own
"Stations" and "Radio controls / Emergency" screens are *not* greenfield —
there is already a working implementation to migrate/wrap, not build from
scratch. This materially changes work-package E/F/G sizing downward from
what the Technical spec's illustrative sequence assumes, and is reflected in
the task decomposition below.

## 3. Decision

**Adopt the new pack's product direction, conditionally on the owner
decisions in §7, as the ratified successor for KERYX's main-screen
navigation and presentation layer only:**

1. `KERYX_Mobile_UX_Redesign_PRD_v1.0.md` §2.1's R1 scope (Channels landing,
   Talk screen, channel selector, Stations, Radio controls, Settings,
   Event QR, new visual system) supersedes PTS P1's "no bottom nav / main
   face must be the console" clause and PTS §6.1's single-screen mandate.
2. `KERYX_Mobile_UX_Redesign_Design_v1.0.md` supersedes
   `KERYX_UI_Design_Specification_v1.0.md` §1, §3.1 (typography — Inter is
   explicitly retained, DSEG7/Share Tech Mono are not mandated outside a
   possible future "classic theme"), §4, §5, §6's 18-state catalogue (a new,
   smaller state model is authoritative for the new screens) and §8's
   "layout/control positions never change" clause (superseded because the
   whole point is that layout changes; the *substance* of §8 — contrast
   ≥4.5:1, 48dp targets, TalkBack, haptic/sound-only operability — carries
   forward unchanged into the new design, per the new Verification spec's
   own §6).
3. TASK-041/042/043's already-merged hero-PTT disc, amplitude ring,
   `RosterScreen`, and emergency band are retroactively recognized as the
   **first increment** of this same successor direction, not a separate or
   superseded design. They are reused, not redone (see §6 work package
   ordering).
4. Everything in §5 below is explicitly NOT superseded.

## 4. UX-D01–D09 (PRD §3) — ratification recommendation

The new PRD lists nine decisions requiring owner ratification. ORCH's
read, cross-checked against both the existing specs and the current
implementation, is that all nine are internally consistent with each other,
with the engine-preservation rule, and with what TASK-043 already shipped.
**Recommendation: ratify all nine as written**, with one clarifying note on
UX-D04 (folded into the owner-decision list in §7, since UX-D04 is the one
that directly triggers this ADR and deserves an explicit yes/no rather than
a bundled ratification).

## 5. Explicitly NOT superseded (verbatim carry-forward from the takeover brief and confirmed against the new pack, which agrees on every point)

- `RadioReducer` / `FloorEngine` — arbitration, grant/release, TOT, emergency
  pre-emption logic (PTS §8.2, §8.6).
- Session architecture / `RadioSessionController` composition and retune
  contracts (PTS §8.3–§8.4; new Technical §1 table explicitly says "preserve
  composition and retune contracts; fix only separately approved defects").
- LOCAL/AUTO/LINKED mode behavior and the AUTO policy (PTS §5.3, D9).
- Audio pipeline: `SfxEngine`/`SfxProjection`/`DeviceAudioSink`/character DSP
  chain, and the TASK-044 Android audio-session/routing fix.
- Discovery/signaling (mDNS/NSD, `SignalingService`) and LiveKit integration
  (`LinkedController`, `TokenClient`).
- Foreground service (`RadioForegroundService.kt`) and its notification
  contract.
- Identity (`peerId` derivation, callsigns) and settings persistence
  (`SettingsRepository`/`SettingsStore`).
- Privacy/security requirements: PTS §8.7 (room derivation, scrypt-stretched
  keyed channels, DTLS-SRTP/TLS 1.3, no server-side voice storage), P6, FR-046
  (force-LOCAL-only).
- The FR-025 emergency-preemption double-grant defect **stays PARKED** —
  explicit 2026-08-21T17:05Z owner decision, no successor task, not reopened
  by this ADR or the new pack (neither the pack nor CLAUDE.md asks for it).
- Two pieces of **pre-existing ORCH-owed debt**, both narrowly scoped and
  independent of the UX work, folded into the task list below rather than
  ignored or silently absorbed into a larger rewrite (per the takeover
  brief's instruction that a defect "should become a narrowly scoped task
  rather than triggering a rewrite of the communication engine"):
  - Token URL double-append (`/token/token` 404 on default LINKED path) —
    `lib/core/settings/settings_model.dart` + `lib/services/linked/token_client.dart`.
  - NFR-11 app size (114 MB vs ≤60 MB target) + the inert `abiFilters` line
    in `android/app/build.gradle.kts`.
- TASK-044's own disclosed gap (no `onTrack`/remote-stream handling in
  `RtcAdapter`, no real RX metering source) — matches the new Technical
  spec §5.3's own instruction to "remove the simulated amplitude meter's
  measurement semantics or use a verified real audio tap in a separately
  scoped telemetry task." Folded in as its own task, not conflated with
  the shell/navigation work.

## 6. Architecture migration — validated against current code

The new Technical spec's `RadioHost` direction is **confirmed correct and
necessary** by this session's independent implementation audit, not merely
assumed. Current reality (verified by reading `face_screen.dart` directly):
`_FaceScreenState` constructs `SessionHost`/`RadioSessionController`,
`FloorEngine` (via the session), `AudioSink`, `SfxEngine`, `SfxProjection`,
and `RadioServiceController` (Android foreground service) all inside
`initState`→`_boot()`, and tears every one of them down in `dispose()`.
Putting a disposable route between the app root and `FaceScreen` today would
kill the radio session on every navigation — exactly the failure mode both
the new pack and this audit identify.

Adopted migration shape (illustrative naming per the Technical spec, not a
mandate to use these exact class names):

```
KeryxApp (ProviderScope, unchanged)
  └─ RadioHost  (NEW — persistent, constructed once, survives navigation)
       │   owns: identity/settings bootstrap, permission coordinator,
       │   SessionHost/RadioSessionController, FloorEngine (via session),
       │   SfxEngine/SfxProjection/AudioSink, RadioServiceController
       │   (Android foreground service), RadioState projection
       │   — this is exactly the block currently inside _FaceScreenState,
       │   hoisted out, unchanged in substance
       └─ MobileAppShell (NEW)
            ├─ Channels  (NEW screen)
            ├─ Talk      (REUSES: PttButton/edge_glow/emg_key from
            │             lib/features/ptt/**, KeryxLcdDisplay strip from
            │             lib/features/display/**, tuning steppers/keypad
            │             from lib/features/tuning/**)
            ├─ Stations  (REUSES: RosterScreen, already live-roster-driven,
            │             from lib/features/face/roster_screen.dart —
            │             wrap, don't rebuild)
            ├─ Radio controls (REUSES: key_row.dart secondary keys +
            │             emergency band from FaceView)
            ├─ Settings  (REUSES: BackPanelScreen content, re-themed to the
            │             new visual system per Design §2.6 — same
            │             SettingsRepository/model underneath)
            └─ Event QR  (REUSES: EventQrScanScreen/EventQrExportScreen
                          as-is, new framing only)
```

No new FloorEngine, no new session/audio/state-machine stack — every "REUSES"
line above is an existing, already-tested, already-frozen module being
wrapped or re-themed, not rebuilt. This directly satisfies the takeover
brief's "critical engine-preservation rule."

## 7. Owner decisions required (genuine ambiguity — not resolved by ORCH)

1. **UX-D04 exact scope.** The PRD says "retire the full-screen console as
   the mandatory home; an optional classic theme is a future initiative."
   Confirm: (a) the *old* `FaceView`/knob-era rendering path may be deleted
   outright once the new shell's tests pass real-device acceptance (matching
   Technical spec §9/§10's retirement gate), with no commitment to ever
   ship a "classic theme" toggle — or (b) you want the old rendering path
   kept dormant/reachable as a real, shippable option later. This changes
   whether the final task in the decomposition below is a deletion or a
   feature-flag.
2. **Relationship to TASK-041/042/043.** Confirm ORCH's read in §3.3/§6 above
   — that the merged hero-PTT disc, amplitude ring, roster screen and
   emergency band are the reusable *first increment* of this same redesign
   (wrapped into the new `Talk`/`Stations`/`Radio controls` screens), not
   thrown away and rebuilt to match the new pack's own illustrative mockups
   more literally. If you want the new pack's screens built fresh instead of
   wrapping TASK-043's work, task sizing in §8 changes substantially (larger).
3. **UX-D01–D09 bulk ratification** (§4 above) — confirm ORCH's
   recommendation to ratify all nine as written, or flag any you want
   changed before they're cited as Spec_References in PLAN.md tasks.

Everything else in this ADR (§2, §3.1–3.3, §5, §6) is ORCH's considered
judgment from direct spec/code reading, not a coin-flip — presented as a
decision, not a further question, per the takeover brief's own instruction
to only escalate genuine ambiguity.
