# KERYX — Product & Technical Specification

**Working consumer name:** *Breaker* (naming decision D8, to be ratified)
**Internal codename:** KERYX (Greek: κῆρυξ, "herald")
**Owner:** Basileia Technologies (Cape Town, ZA)
**Document version:** 1.1 — *Ready for Build*
**Status:** Approved for Phase 1 execution (reviewer feedback incorporated)
**Change log:** v1.1 — ratified D9 (AUTO policy: LINKED-preferred for Phase 1, dual-homing → Phase 2); defined peer ID format, callsign collision rules and protocol timing constants (§8.6); clarified S-meter aggregate/per-station behaviour (FR-069); event QR default expiry (FR-044); privacy-sheet clarifications on LOCAL privacy codes, radio check, and token-service logging (§8.7); grant tone/haptic included in key-up measurement (NFR-03); battery bench elevated to hard release gate (KRX-086); 2026-08-21 — FR-108 (night dimming) ratified into this table from the UI Design Spec's proposed amendment (§9), pinned as Should-priority with default **auto**, closing PLAN.md TASK-030 follow-up (mm); §8.6 amended to close the late-joiner double-grant defect TASK-023's soak harness proved deterministically — `PRESENCE` gains optional `holder`/`lease_remaining_ms` fields and a one-heartbeat no-self-grant guard on join, closing PLAN.md finding (ll) (option A of the three costed alternatives).
**Audience:** Development team (solo dev + Claude Code + DEVDepartment execution model compatible)
**Supersedes:** Competitor-model draft PRD ("Walkie-Walkie response document")

---

## 0. One-liner

> **A software walkie-talkie that feels like hardware.** Zero-config on local Wi-Fi, one tap to extend over mobile data, and every pixel, click, hiss, and beep behaves like a real handheld radio.

---

## 1. Vision

KERYX is not a chat app with a big button. It is a faithful software recreation of the handheld PMR446/FRS/GMRS radio experience — tuning detents, squelch tails, roger beeps, callsigns, channel discipline — built on a modern low-latency voice stack.

Two connectivity worlds, one mental model:

1. **LOCAL** — same Wi-Fi network. Serverless, accountless, zero-config. Devices find each other automatically. Nothing leaves the LAN. This is the free, forever-private core.
2. **LINKED** — mobile data / cross-network. The same channels, extended through a lightweight self-hosted relay. Join by channel + privacy code, by passphrase, or by scanning a QR code at an event.

The differentiator is the **triple combination** no competitor holds simultaneously: authentic physical-radio interaction and sound design, genuine local-first serverless operation, and a clean internet extension that never breaks the radio metaphor.

**Design north star — the "FRS test":** anyone who has ever held a real walkie-talkie must be able to pick this app up and use it, screen-off included, without a tutorial.

---

## 2. Product Principles

These are binding. Every feature and ticket is evaluated against them.

| # | Principle | Meaning in practice |
|---|-----------|---------------------|
| **P1** | **Radio first, app second** | Deliberate skeuomorphism. Physical controls, LCD/segment displays, textured housings. No Material minimalism, no bottom nav bars, no hamburger menus on the main face. |
| **P2** | **Local-first, serverless by default** | LOCAL mode requires no internet, no server, no account, no analytics. It must work on an off-grid router in the bush. |
| **P3** | **Zero friction** | First transmission within 10 seconds of first launch on a shared LAN. No sign-up ever for core use. |
| **P4** | **Sound is the interface** | Every state change is audible. All SFX play from local assets on a dedicated bus — instant and identical regardless of network conditions. |
| **P5** | **One voice at a time** | PTT floor discipline is enforced, not simulated. No text chat, no emoji, no read receipts, no message history UI. Voice, presence, and channel — nothing else. |
| **P6** | **Private by default** | No public global channel directory at launch. Numbered channels are discoverable by design (like real radio); private channels are passphrase-keyed. Voice is never recorded server-side. |
| **P7** | **Honest signal** | Meters, bars, and quality indicators are driven by real network telemetry (RTT, loss, jitter), never faked. If the link is bad, the radio says so — like a real radio. |

---

## 3. Ratified Decisions

Direct answers to the open questions in the draft PRD, plus decisions the draft left implicit. These are locked for Phase 1; changes require a new ADR.

### D1 — Channel selector: hybrid rotary + steppers + keypad
The hero interaction is a **simulated rotary knob** with flywheel physics, per-channel detents, and a haptic tick on every detent (VibrationEffect composition primitive `CLICK`). Flanking **CH▲/CH▼ steppers** serve precision and accessibility. **Long-press the channel display** opens a keypad for direct entry (`1`–`99` + privacy code). All three write to the same tuning state machine. Rationale: the knob sells the fantasy; steppers and keypad make it usable one-handed, gloved, or with TalkBack.

### D2 — Internet path: server-assisted from day one; LOCAL stays serverless
LINKED mode uses a **self-hosted open-source SFU (LiveKit)** plus its signaling layer on a single VPS. Pure P2P internet mode is rejected for v1: NAT traversal failure rates, group fan-out cost on mobile uplinks, and battery burn outweigh the privacy gain — which we recover via an E2EE roadmap item (Phase 2, LiveKit insertable-streams E2EE for keyed channels). LOCAL mode remains genuinely peer-to-peer with **no server component at all**.

### D3 — Monetisation: free local core + one-time Pro unlock; Teams later; no ads, ever
- **Free, forever:** full LOCAL mode, one active LINKED channel, core sounds, default faceplate, roger beep, monitor.
- **Pro (one-time purchase, indicative $6.99 / R129, regional pricing):** unlimited LINKED channels, Scan, Dual Watch, instant-replay ("SAY AGAIN"), VOX, hardware/Bluetooth PTT mapping, faceplate packs, extended sound packs.
- **Teams (Phase 3 subscription):** managed private channels, admin console, priority relay region, dispatch view.
- **Ads are permanently ruled out** — an ad inside a radio destroys P1 and P4 irreparably.

### D4 — Beachhead users: families/home/events and outdoor/adventure first
These groups have LAN-or-nearby topologies, tolerate playfulness, and evangelise (kids adore walkie-talkies). Warehouses/small teams are the Phase 3 paid expansion once background reliability is battle-proven. General "fun radio" users are served incidentally, not targeted.

### D5 — Offline mesh: Phase 2, hotspot-first
Standard infrastructure Wi-Fi is the Phase 1 contract. Phase 2 adds a guided **Hotspot Mode** (one device hosts, works with zero external infrastructure — the true "radios in the bush" story) and evaluates **Wi-Fi Aware (NAN)** on supported devices. Wi-Fi Direct is deprioritised (fragile UX, OEM inconsistency).

### D6 — Sound design: commissioned early, treated as a core asset
The sound palette (§7) is a Phase 1 deliverable, not polish. Source: commissioned recordings of real PMR/CB/VHF hardware plus a licensed field-recording library; layered with runtime-generated noise for seamless loops. Budget line item, owned like code, versioned in-repo.

### D7 — Platform: Flutter, Android-first
Flutter aligns with existing Basileia capability (PocketClaw, Decimen port, church app) and gives an iOS path. Android-native fallbacks via platform channels where Flutter plugins fall short (NSD, foreground service, Bluetooth SCO, key events). iOS is Phase 3 with known compromises documented in §13.

### D9 — AUTO mode policy: LINKED-preferred for Phase 1; dual-homing deferred to Phase 2
Resolves the KRX-062 decision gate per architecture review. When any WAN member is present on a channel, **all members use the LINKED path** (LiveKit room); pure-LAN channels stay on serverless mesh. The elected-bridge dual-publish design (§8.4) is preserved as the Phase 2 target but is not built in Phase 1 — its edge cases (dual-path sync, bridge departure mid-TX, clock skew on presence, bridge-device battery burden) are not worth carrying before real demand is measured. The 20-device event field test (KRX-094) must capture whether users on a shared LAN notice or object to relay routing; that data drives the Phase 2 go/no-go.
Codename **KERYX** internally (repo, tickets `KRX-###`, server). Working consumer name **"Breaker"** (CB heritage: *"Breaker, breaker…"*). Final trademark/ASO check is ticket KRX-002; the spec is name-agnostic beyond branding assets.

---

## 4. Personas & Core Scenarios

| Persona | Scenario | Modes exercised |
|---|---|---|
| **The Household** — parents + 2 kids, one Wi-Fi network | "Dinner's ready" from kitchen to bedrooms; kids play "patrol" in the garden | LOCAL, faceplates, roger beep |
| **The Trail Group** — 4 hikers, mixed signal | Car-park convoy on mobile data → campsite hotspot mode | LINKED → Hotspot (Ph2), battery standby |
| **The Event Crew** — wedding/church/market volunteers | Coordinator prints a QR; 12 volunteers scan and land on CH 7 · code 21 | LINKED, Event QR join, TOT, busy lockout |
| **The Workshop** — small warehouse team (Phase 3) | All-day monitor on belt-clipped phones + Bluetooth PTT buttons | LOCAL, foreground service, hardware PTT, Teams |

Anti-persona for v1: the public-channel social user (Zello-style open lobbies). Deliberately unserved (P6).

---

## 5. Functional Specification

Requirements are numbered `FR-###`. Priority: **M** (must, Phase 1), **S** (should, Phase 1 if budget allows), **P2/P3** (later phase).

### 5.1 Channels, Tuning & Privacy Codes

| ID | Requirement | Pri |
|----|-------------|-----|
| FR-001 | 99 numbered channels (`CH 01`–`CH 99`), displayed in segment-style type. | M |
| FR-002 | **Privacy codes 00–38** per channel (CTCSS analogue). `00` = open. Devices only render audio matching their channel **and** code; on LINKED, code participates in room derivation (§8.7). Display as `CH 07 · 21`. | M |
| FR-003 | Rotary knob tuning with detents, flywheel fling, and haptic tick per detent (D1). | M |
| FR-004 | CH▲/CH▼ steppers with press-and-hold auto-repeat (accelerating). | M |
| FR-005 | Long-press channel display → keypad direct entry of channel + code. | M |
| FR-006 | Every channel change plays the **tuning burst**: squelch-break + static swell that ducks into the new channel's live audio or settles to the ambient hiss floor (§7). | M |
| FR-007 | **Keyed (named) channels**: user-created channels identified by a passphrase instead of a number; roomId derived from the passphrase (§8.7). These are the "actually private" tier. Rendered as `PRV` + user label on the display. | M |
| FR-008 | Region setting (region salt) partitions the numbered-channel namespace on LINKED so "CH 7" in Cape Town isn't "CH 7" in São Paulo by default; users can deliberately join another region. | S |
| FR-009 | Channel memory: last 6 tuned channels accessible via quick-recall (long-press CH▼). | S |

### 5.2 PTT & Floor Control

| ID | Requirement | Pri |
|----|-------------|-----|
| FR-020 | Hold-to-talk PTT as default. Press → TX request → grant → **TX attack ≤ 50 ms** from grant to live audio (pre-published muted track, §8.5). Release → roger beep (if enabled) → floor released. | M |
| FR-021 | **Latch mode** (double-tap to lock TX, tap to release) as a setting. | S |
| FR-022 | **Busy Channel Lockout**: if the floor is held, PTT press yields a *denied* buzz + short haptic and the TX LED does not light. Setting: on by default. | M |
| FR-023 | **Time-Out Timer (TOT)**: max continuous TX 60 s (configurable 30–120 s). Warning chirp at T-5 s, hard cut + penalty tone at 0, floor released. Prevents stuck-PTT and channel hogging. | M |
| FR-024 | **VOX mode** (voice-operated TX) with sensitivity slider and hang-time; clearly indicated on the display (`VOX` icon). Pro. | S |
| FR-025 | **Emergency / priority**: long-press dedicated orange key → pre-emption tone on the channel, overrides busy lockout, pins an `EMG` indicator until the sender clears it. No location sharing in v1. | S |
| FR-026 | Full haptic/visual TX feedback: red TX LED skeuomorph, screen edge-glow while transmitting, distinct grant/deny/timeout haptic compositions (§6.4). | M |

### 5.3 Connectivity Modes & Discovery

| ID | Requirement | Pri |
|----|-------------|-----|
| FR-040 | Three-position mode switch, styled as a physical slider: **LOCAL / AUTO / LINKED**. AUTO prefers LAN peers and transparently bridges to the relay when off-LAN members exist on the channel. Default: AUTO. | M |
| FR-041 | LOCAL discovery via mDNS/NSD, service type `_keryx._tcp`, TXT records: `cs` (callsign), `ch` (channel hash prefix), `v` (protocol version). MulticastLock acquired while radio is on. | M |
| FR-042 | LOCAL is fully serverless: LAN-internal signaling (§8.3), no packets leave the network, works with the internet down. | M |
| FR-043 | LINKED join methods: tune a numbered channel (+ code), enter a keyed-channel passphrase, or **scan an Event QR**. | M |
| FR-044 | **Event QR / link**: any channel can be exported as a QR code + `keryx://` deep link encoding region, channel, code (or keyed-channel token), and expiry. **Default expiry: 24 h**, with presets (4 h "session", 24 h, 7 d, no expiry — the last requiring an explicit extra tap). Expired tokens are refused by the token service so temporary event channels do not linger on the relay. Scanning tunes the radio instantly. | M |
| FR-045 | Graceful degradation: relay unreachable → radio drops to LOCAL with an audible "link lost" double-chirp and `NO LINK` display flag; never a modal error dialog. | M |
| FR-046 | A "force LOCAL only" privacy toggle that hard-disables all WAN traffic. | M |

### 5.4 Classic Radio Behaviours

| ID | Requirement | Pri |
|----|-------------|-----|
| FR-060 | **Monitor key**: hold to open squelch fully — raw channel bed, weak-signal artefacts and all. | M |
| FR-061 | **Squelch knob** (settings face): actually functions — sets RX gate threshold *and* the resting hiss level (from silent to faint bed). | M |
| FR-062 | **Roger beep**: off / classic K-tone / dual-tone / custom pack. Plays locally on TX end *and* transmits a 60 ms end-of-TX marker so receivers hear it in-band-style. | M |
| FR-063 | **Scan mode** (Pro): cycles channel memory or 1–99 with authentic scan ticks; halts on activity; resume after 3 s idle. Priority channel re-checked every 2 s. | S |
| FR-064 | **Dual Watch** (Pro): monitor a second channel; activity there plays at −6 dB with a distinct pre-tone. | P2 |
| FR-065 | **SAY AGAIN** (Pro): a ring buffer holds the **last 30 s of received audio in RAM only**. Tap the replay key to re-hear the last transmission (with a "replay" telltale on the display). Never written to disk; cleared on channel change or radio-off. | S |
| FR-066 | **Radio check**: press-and-hold MENU+PTT sends a check ping; each receiving station auto-responds with its measured link quality; sender's display shows `RCHK: 3 STN · S7` and plays a confirmation tone. Zero-voice way to verify the net. | S |
| FR-067 | Presence: `STN n` count on the display; tap to flip the display panel to the station list (callsigns + S-meter per station). Flip back automatically after 5 s (P5: the face stays a radio). | M |
| FR-068 | **Callsigns**: auto-generated NATO-phonetic callsigns on first run (e.g. `BRAVO-7`, `SIERRA-19`), editable, 2–12 chars. No accounts, no uniqueness enforcement beyond per-channel collision suffixing. | M |
| FR-069 | Signal meter (`S1–S9`) per §8.9 telemetry mapping. Honest (P7). The **status-strip meter is aggregate**: while a station transmits it shows that station's link; at idle it shows the worst active peer link (a net is only as good as its weakest station — like real radio). **Per-station meters** appear in the station-list panel flip (FR-067). | M |

### 5.5 Audio Devices & Hardware Inputs

| ID | Requirement | Pri |
|----|-------------|-----|
| FR-080 | Default output: speakerphone. Automatic routing to wired/Bluetooth when connected; SCO engaged for BT mic. | M |
| FR-081 | Wired headset button → PTT toggle. | S |
| FR-082 | Bluetooth PTT accessories (AINA-class buttons, media-button remotes) mappable to PTT (Pro). | S |
| FR-083 | Volume-key-as-PTT option while app foregrounded (screen-off limitation documented in-app). | S |
| FR-084 | Android Quick Settings tile + home-screen widget: shows channel, toggles radio power; tapping opens the face. | P2 |

### 5.6 Settings, Modes & Housekeeping

| ID | Requirement | Pri |
|----|-------------|-----|
| FR-100 | Settings rendered as the radio's **back panel / battery-hatch** screen — even configuration stays in-world (P1). | M |
| FR-101 | Faceplates: default "Field Black" free; packs (Military Olive, Retro CB Chrome, Marine VHF, Airband) — Pro. Pure cosmetics, zero layout changes. | S |
| FR-102 | **Standby economics**: with nobody transmitting, no media flows (PTT model) — only presence keepalives. Screen-off monitor target ≤ 2%/hr battery (§9). | M |
| FR-103 | Foreground service with a persistent radio-styled notification (channel, PTT action button on Android 14+ where permitted, power-off action). | M |
| FR-104 | First-run flow: mic + notifications + nearby-devices permission explainers in radio voice ("A radio needs a microphone…"), then land on CH 01 powered on. ≤ 3 screens, no account, no email. | M |
| FR-105 | In-app OEM battery-whitelisting guide (Samsung/Xiaomi/Huawei specifics, dontkillmyapp-style instructions) surfaced when the service is observed being killed. | M |
| FR-106 | Accessibility: full TalkBack labelling, stepper-first tuning path, haptic-only feedback profile, min 48 dp targets, WCAG AA contrast on all faceplates. | M |
| FR-107 | Localisation scaffold: EN at launch; AF and pt-BR strings files stubbed. | S |
| FR-108 | **Night dimming**: display and legend luminance follow an auto/manual dim setting (gate G4, "the dark test" — usable at night without the display becoming a torch). Auto/manual is user-selectable; default **auto**. No specific luminance percentage, lux threshold, or transition timing is prescribed by this requirement — implementations pin those as disclosed decisions. | S |

---

## 6. UX & Interaction Specification

### 6.1 The Face (single primary screen)

Portrait-first. The entire screen is the front of a handheld radio:

```
┌─────────────────────────────┐
│  ▂▄▆ S-meter   BAT ▮▮▮  STN 4│   ← status strip (in-display)
│ ┌─────────────────────────┐ │
│ │  CH 07 · 21     LINKED  │ │   ← segment LCD: channel · code, mode,
│ │  BRAVO-7 ► talking      │ │      active speaker line, telltales
│ └─────────────────────────┘ │      (VOX, EMG, NO LINK, PRV, replay)
│      ╔═══════════════╗      │
│      ║   SPEAKER     ║      │   ← grille; bars physically vibrate
│      ║   GRILLE      ║      │      with RX audio amplitude
│      ╚═══════════════╝      │
│   (CH▼)   ⟲ KNOB ⟳   (CH▲)  │   ← rotary + steppers
│  [MON] [SCAN] [SAY AGN] [⚙] │   ← secondary keys (Pro keys shown
│ ┌─────────────────────────┐ │      dimmed/locked when unowned)
│ │       P  T  T           │ │   ← ≥ 96 dp tall, bottom third,
│ └─────────────────────────┘ │      full-width, thumb-native
│         [ EMG ]  (side key) │
└─────────────────────────────┘
```

- Housing: subtly textured dark polymer; knurled knob; screws in corners. Skeuomorphic but crisp — think 2026 render of a radio, not 2009 leather-stitch iOS.
- The **speaker grille visualisation** is the only "animation for its own sake" allowed: grille bars tremble with incoming audio amplitude.
- Landscape supported (radio rotates to "brick on its side" layout); portrait is primary.

### 6.2 Knob Physics

- Drag along an arc; 1 detent = 1 channel; detent snap at ±12° with critically-damped settle.
- Fling → flywheel with exponential decay, detent ticks (audio + haptic) firing per channel crossed, capped at 12 ch/s so ticks stay perceptually discrete.
- Every detent fires: haptic `PRIMITIVE_CLICK`, 8 ms mechanical tick sample, LCD update — all in the same frame.

### 6.3 Display Language

- Segment/LCD typeface for channel + code; dot-matrix secondary line for callsigns/status.
- Telltale icons only — no toasts, no snackbars, no dialogs on the face. Errors are display flags + tones (FR-045).

### 6.4 Haptics Table

| Event | Composition |
|---|---|
| Knob detent | `PRIMITIVE_CLICK` (scale 0.6) |
| PTT grant | `PRIMITIVE_QUICK_RISE` |
| PTT denied (busy) | `PRIMITIVE_THUD` ×2 |
| TOT warning | `PRIMITIVE_TICK` ×3 |
| Link lost | `PRIMITIVE_LOW_TICK` ×2 |
| Emergency RX | strong pattern, repeats until acknowledged |

Fallback vibration patterns defined for devices without composition support.

---

## 7. Sound Design Specification

Sound is a first-class, versioned asset set (`/assets/sfx/v1/`), 48 kHz 16-bit WAV, loudness-normalised to −16 LUFS (SFX) with the emergency tone at −12 LUFS.

### 7.1 Asset Manifest

| Asset | Description | Notes |
|---|---|---|
| `squelch_open` / `squelch_tail` | Classic squelch crack on RX start/end | 40–80 ms |
| `static_bed_1/2/3` | Loopable hiss beds, three intensities | Seamless loop points; squelch knob crossfades |
| `tune_burst` | Channel-change static swell | Ducks under incoming audio |
| `scan_tick` | Per-channel tick during scan | ≤ 30 ms |
| `roger_k`, `roger_dual`, `roger_moto` | Roger beep variants | User-selectable |
| `deny_buzz` | Busy-lockout refusal | Pairs with THUD haptic |
| `tot_warn`, `tot_cut` | Time-out chirps | |
| `link_lost`, `link_up` | Relay connectivity chirps | |
| `emg_alert` | Priority pre-emption tone | Distinct, urgent, not painful |
| `rchk_ok` | Radio-check confirmation | |
| `key_click`, `knob_tick`, `slider_thunk` | Mechanical UI sounds | |
| `power_on`, `power_off` | Radio boot/shutdown sweep | First-run delight moment |

### 7.2 DSP & Mixing Rules

- **Two buses**: Voice bus (network audio) and SFX bus (local assets). SFX never traverses the network; it is therefore instant and identical for everyone (P4).
- Voice bus RX chain: jitter buffer → Opus decode → **radio character DSP** (300–3400 Hz band-pass, 3:1 soft-knee compression, +0…+6 dB makeup, optional hiss floor mixed at squelch-knob level) → output. Character DSP intensity: Off / Light / Full (default Light).
- SFX ducks voice by −3 dB during overlap ≤ 150 ms; voice never ducks for cosmetics.
- All tones must pass a "3-metre kitchen test": distinguishable from across a room on a phone speaker.

---

## 8. Technical Architecture

### 8.1 Stack Summary

| Layer | Choice | Rationale |
|---|---|---|
| App | **Flutter (Dart 3)**, Android-first, min SDK 26, target latest | Team capability; iOS path preserved |
| Voice engine | **WebRTC** via `flutter_webrtc` (LOCAL) and **`livekit_client`** (LINKED) | Opus, jitter buffer, PLC, AEC/NS/AGC (APM) for free; one codec pipeline both modes |
| Codec | Opus, mono, 16–24 kbps, 20 ms frames, in-band FEC on, DTX off during TX | Voice-optimised, loss-resilient |
| Local discovery | Android NSD (mDNS) via platform channel; `_keryx._tcp` | Native reliability > plugin roulette |
| Relay | **Self-hosted LiveKit** (single Docker compose: LiveKit + Redis + Caddy TLS + coturn) on one VPS (clawsrv-class, 4 vCPU/8 GB starts fine) | OSS, Flutter SDK, data channels for floor control, E2EE path, horizontal scaling later |
| Signaling glue | Tiny stateless token service (FastAPI, ~200 LOC): mints LiveKit JWTs from room derivations; no user DB | Keeps "no accounts" true on LINKED |
| State mgmt | Riverpod (or Bloc — dev's standing convention wins) | Deterministic radio state machine |
| Persistence | Local only: settings + channel memory in encrypted prefs. **No server-side persistence of anything.** | P6 |

### 8.2 Radio State Machine (authoritative)

```
OFF → BOOT → IDLE(RX) ⇄ TUNING
IDLE → TX_REQ → TX (granted) → IDLE
IDLE → RX_ACTIVE (remote floor) → IDLE
any → LINK_DEGRADED → IDLE|LOCAL_FALLBACK
```
One reducer owns this. UI, audio, haptics, and network are all projections of it — this is what makes the app testable (unit tests drive the reducer; golden tests drive the face).

### 8.3 LOCAL Path (serverless)

1. **Discover**: NSD registers + browses `_keryx._tcp`; TXT carries callsign, protocol version, and a *channel-hash prefix* (privacy: full channel/code never broadcast in plaintext).
2. **Signal**: each device runs a loopback-free LAN WebSocket (random high port, advertised in NSD). Peers on a matching channel hash perform WebRTC offer/answer over it. LAN candidates only (host candidates; mDNS ICE).
3. **Media**: full-mesh WebRTC audio. Mesh is safe here because PTT means at most one publisher at a time; N ≤ 16 peers per channel on LAN is the supported envelope (soft cap, warn beyond).
4. **Floor control**: over WebRTC data channels using the protocol in §8.6. Deterministic arbiter = lexicographically lowest peer ID currently in the channel (re-elected on churn); grants are idempotent and time-bounded, so arbiter loss self-heals within 500 ms.
5. **Fallbacks**: if mDNS is filtered (guest networks, AP isolation), a UDP broadcast beacon fallback runs at 2 s intervals for 30 s after tuning; if both fail the display shows `LAN?` and the troubleshooting card (still no dialog).

**Rejected alternative** — raw Opus/RTP over UDP multicast with a hand-rolled stack: more control, but re-implements jitter buffering, PLC, AEC and cross-router multicast is notoriously unreliable. WebRTC mesh wins on time-to-quality. Recorded here so it isn't relitigated.

### 8.4 LINKED Path

- Channel → deterministic `roomId` (§8.7) → token service issues a short-lived LiveKit JWT (identity = callsign + random suffix) → join room.
- One LiveKit room per channel; audio publish/subscribe mirrors PTT state; floor control messages ride LiveKit data messages (same schema as LOCAL).
- **AUTO mode (Phase 1, per D9)**: when any WAN member exists on the channel, all members route via the LiveKit room; otherwise pure LAN mesh. Transition plays the standard link chirps — no modal, no interruption of an in-progress transmission (switch occurs at floor-idle only).
- **Dual-homed bridging (Phase 2 target)**: LAN devices keep mesh audio locally while one elected LAN device dual-homes into the LiveKit room, re-publishing floor state both ways; the TX device publishes to both legs simultaneously (no transcoding). Defined behaviour if the bridge leaves mid-transmission: bridge role follows arbiter election (§8.6) — the new arbiter assumes the bridge within one presence interval (≤ 5 s); the in-flight transmission continues on the leg where it originated and the opposite leg hears a `link_lost`/`link_up` chirp pair. This contingency is specified now so the Phase 2 build inherits it rather than inventing it.
- TURN (coturn) bundled for hostile NATs; target ≥ 97% connection success.

### 8.5 TX Latency Design — the ≤ 50 ms attack

Dynamically publishing a track on PTT press costs 200–500 ms (negotiation). Instead: the audio track is **pre-published muted** on channel join; PTT grant flips `enabled=true`. Cost: a trickle of silent keepalive overhead; benefit: near-instant key-up — the single most "real radio" feeling in the app.

**Mouth-to-ear latency budget:**

| Stage | LAN | LINKED |
|---|---|---|
| Capture buffer | 20 ms | 20 ms |
| APM (AEC/NS/AGC) | 10 ms | 10 ms |
| Opus encode | 5 ms | 5 ms |
| Network | 5–15 ms | 40–120 ms |
| Jitter buffer | 40–60 ms | 60–100 ms |
| Decode + character DSP | 10 ms | 10 ms |
| Output buffer | 20 ms | 20 ms |
| **Total (target)** | **≤ 150 ms** | **≤ 300 ms p90** |

### 8.6 Floor Control Protocol v1 (JSON over data channels; protobuf reserved for v2)

| Msg | Fields | Semantics |
|---|---|---|
| `TX_REQ` | peer, prio, ts | Request the floor (prio: 0 normal, 1 emergency) |
| `TX_GRANT` | peer, lease_ms | Arbiter grants; lease = TOT + 2 s |
| `TX_DENY` | peer, reason | `BUSY` \| `LOCKOUT` |
| `TX_START` / `TX_END` | peer | Speaker announces; receivers gate audio + drive UI |
| `PRESENCE` | peer, cs, seq, holder?, lease_remaining_ms? | 5 s heartbeat; 3 misses = departed |
| `RCHK` / `RCHK_ACK` | peer, quality | Radio check (FR-066) |
| `EMG` / `EMG_CLR` | peer | Priority pre-emption (FR-025) |

Rules: emergency `TX_REQ(prio=1)` pre-empts an active lease. Grants expire; a crashed speaker frees the floor automatically at lease end. All messages carry protocol version; unknown versions are ignored (forward compatibility).

**Late-joiner floor-state blind spot (ratified 2026-08-21, closes PLAN.md TASK-023 finding (ll)).** A peer that joins mid-transmission has no record of the `TX_START`/`TX_GRANT` that preceded its arrival; if it also out-ranks the incumbent arbiter on election (peerId is the sole election input, per the normative rule below), it can grant itself the floor with no knowledge a lease is already live — a genuine double-grant, not a race. Closed by extending `PRESENCE` with two **optional** fields, both omittable and both ignored by any receiver on an older protocol version (the existing unknown-field-tolerance rule above already covers this — no version bump required): `holder` (the arbiter's current view of who holds the floor, `null`/absent when idle) and `lease_remaining_ms` (time left on that lease, absent when `holder` is absent). A peer MUST NOT grant itself the floor — on any `TX_REQ`, including the initial self-grant an arbiter issues on its own request — until it has observed at least one full `PRESENCE` cycle (`presenceHeartbeat`, 5 s) since joining the channel, UNLESS it already holds direct proof the floor is idle (e.g. it was present before any other peer joined). This bounds the blind window to at most one heartbeat interval and requires no new message type or round-trip; the ≤ 50 ms attack (§8.5) and the TX path are untouched, since the guard applies only to the join-then-immediate-grant sequence, not to normal in-channel PTT.

**Peer identity (normative).** `peerId = base32( SHA-256(installUUID) )[:10]` — a stable, device-derived ID generated once at install, independent of the user-editable callsign. It is the sole input to arbiter election (lexicographic minimum), giving a well-behaved, uniformly distributed ID space that avoids election thrashing on simultaneous joins. Callsigns are display-only; on a callsign collision within a channel, later joiners render with a numeric suffix (`BRAVO-7`, `BRAVO-7 (2)`) derived from join order — the underlying peerIds never collide, so protocol behaviour is unaffected.

**Timing constants (locked; asserted by the KRX-044 simulation harness).**

| Constant | Value |
|---|---|
| Presence heartbeat / departure | 5 s / 3 missed (15 s) |
| Grant lease | TOT + 2 s (default 62 s) |
| Arbiter re-election settle | ≤ 500 ms after churn detection |
| `TX_REQ` retry / give-up | 150 ms / 3 attempts |
| Floor-idle debounce before AUTO path switch | 750 ms |

### 8.7 Channel → Room Derivation & Threat Model

```
numbered:  roomId = b32( HMAC-SHA256("KERYX.v1", region | ch | code) )[:16]
keyed:     roomId = b32( HMAC-SHA256("KERYX.v1", "PRV" | scrypt(passphrase)) )[:16]
```

- **Numbered channels are radio-honest**: 99 × 39 combinations are enumerable by design — exactly like real FRS. The UI says so ("Numbered channels are open airwaves. For private talk, use a keyed channel.").
- **Keyed channels** get real entropy from the passphrase (scrypt-stretched) and are the E2EE target in Phase 2 (LiveKit insertable-streams; key derived from the same passphrase, never sent to the server).
- Transport security everywhere: DTLS-SRTP (both modes), TLS 1.3 to the relay. Server sees keyed-channel *room hashes* only, never passphrases; no voice is ever recorded or stored server-side; token service keeps no user records and **logs nothing beyond ephemeral, IP-scoped rate-limit counters** (no callsigns, no room-join histories; counters expire ≤ 1 h) — asserted by a logging-policy test in KRX-051. Additional plain-language disclosures required in the privacy sheet (KRX-118 → folded into KRX-093): (a) on pure LOCAL, privacy codes are **client-side filters only** — like real CTCSS, a determined party on the same network can ignore them; numbered channels are open airwaves, keyed channels are the private tier; (b) **radio check transmits no voice** — it exchanges only small link-quality measurements. POPIA/GDPR posture: LOCAL processes zero personal data off-device; LINKED processes ephemeral connection metadata only, documented in a plain-language privacy sheet (KRX-118).

### 8.8 Background & Battery

- Foreground service (`mediaPlayback` + `microphone` types), partial wake lock during RX/TX only, MulticastLock only while LOCAL discovery active.
- Idle economics: PTT model means **zero media packets when nobody talks** — standby cost is heartbeats + one muted track's keepalives. Measured targets in §9.
- Audio focus: transient-may-duck for RX; abandon on power-off. BT SCO brought up on PTT press when a BT mic is routed (SCO setup latency masked by the grant tone).
- OEM killers: detection heuristic (service death without user power-off) triggers FR-105 guidance.

### 8.9 Telemetry → S-Meter (P7)

`S = f(RTT, loss%, jitter)` — LAN: RTT via data-channel ping; LINKED: LiveKit `connectionQuality` + stats API. Mapping table fixed in code (S9 ≤ 30 ms/0% loss … S1 ≥ 400 ms or ≥ 15% loss) so the meter is reproducible in tests. **No product analytics in LOCAL mode, period.** LINKED: opt-in, anonymous, counts-only diagnostics (connect success, latency histograms) — off by default.

---

## 9. Non-Functional Requirements

| ID | Requirement | Target |
|---|---|---|
| NFR-01 | Mouth-to-ear latency, LAN | ≤ 150 ms p50, ≤ 200 ms p90 |
| NFR-02 | Mouth-to-ear latency, LINKED | ≤ 300 ms p90 |
| NFR-03 | PTT key-up, measured **press → grant tone + haptic rendered** (the perceived-response event, not just internal grant) | ≤ 80 ms; TX attack ≤ 50 ms post-grant |
| NFR-04 | LAN discovery success (same subnet, mDNS open) | ≥ 98% within 3 s |
| NFR-05 | LINKED connection success (with TURN) | ≥ 97% |
| NFR-06 | Standby battery (screen off, monitor, LOCAL) | ≤ 2%/hr on reference device (mid-range 2024 Android) |
| NFR-07 | Crash-free sessions | ≥ 99.5% |
| NFR-08 | Cold start → RX-ready | ≤ 2.5 s |
| NFR-09 | Relay footprint | 1 VPS serves ≥ 500 concurrent channel-joins; scale-out documented |
| NFR-10 | Test coverage | Reducer/state machine 100% branch; floor protocol simulation suite; golden tests for the face; ≥ 80% overall |
| NFR-11 | App size | ≤ 60 MB installed incl. sound pack v1 |

---

## 10. Phased Roadmap

Phases are scope boundaries, not calendar commitments. A phase ships when its exit criteria pass — effort ordering only.

### Phase 1 — "The Radio Works" (Android, ship to Play Store)
**Scope:** Face UI + knob/steppers/keypad, sound pack v1, LOCAL mesh (discovery, signaling, floor control), LINKED via LiveKit (numbered + keyed channels, Event QR), PTT + busy lockout + TOT, monitor, squelch, roger beep, callsigns, presence, radio check, S-meter, foreground service + battery guide, Pro purchase gate (Scan, SAY AGAIN, VOX, BT PTT, faceplates behind it), first-run flow, privacy sheet.
**Exit criteria:** all M-priority FRs pass; NFR-01/03/04/06/07 measured green on 3 reference devices + 2 hostile routers; 20-device event field test (church volunteer crew is the natural pilot) completes with zero coordinator interventions.

### Phase 2 — "Off the Grid & Deeper In-World"
Hotspot Mode (guided host flow), Wi-Fi Aware spike, E2EE for keyed channels, Dual Watch, LAN↔WAN dual-homed bridge (per D9, pending field-test signal), Quick Settings tile + widget, AF/pt-BR localisation, sound pack v2, Wear OS spike.

### Phase 3 — "Teams & the Second Platform"
iOS build (background-audio strategy, App Review dossier), Teams tier (managed channels, admin console, dispatch view, priority relay), Bluetooth accessory certification matrix, relay scale-out (multi-region LiveKit), enterprise pilots (warehouse persona).

### Delight backlog (unscheduled, in-philosophy)
NOAA-style weather channel (TTS on CH 99), Morse station-ID option, collectible event faceplates, radio "boot screen" customisation.

---

## 11. Build Breakdown — Epics & Seed Tickets

Ticket prefix `KRX-###`. This is the seed WBS for DEVDepartment ingestion; each ticket expands to spec-pack level at execution time.

### E1 · Foundations & Project Scaffold
- KRX-001 Repo scaffold: Flutter app + `relay/` (Docker compose) + `token-svc/` + `sfx/` asset pipeline; CLAUDE.md conventions; CI (analyze, test, build APK)
- KRX-002 Naming/trademark & ASO check ("Breaker" et al.)
- KRX-003 Radio state machine reducer + 100%-branch unit test suite
- KRX-004 Settings/persistence layer (encrypted prefs, channel memory)

### E2 · The Face (UI shell)
- KRX-010 Face layout, theming system, Field Black faceplate
- KRX-011 Rotary knob widget (arc drag, detents, flywheel, haptic hooks) + widget tests
- KRX-012 Segment LCD display component (channel/code, telltales, dot-matrix line)
- KRX-013 Steppers with auto-repeat; keypad direct-entry sheet
- KRX-014 Speaker-grille RX visualiser (amplitude-driven)
- KRX-015 PTT button (states, edge-glow, latch mode) + secondary key row
- KRX-016 Settings-as-back-panel screen
- KRX-017 Accessibility pass: TalkBack, targets, contrast, haptic-only profile
- KRX-018 Golden test suite for all face states

### E3 · Sound
- KRX-020 SFX asset commissioning brief + licensing; manifest v1 delivered per §7.1
- KRX-021 SFX engine: dual-bus mixer, ducking rules, loop-point static beds
- KRX-022 Radio character DSP (band-pass, compression, hiss floor) with Off/Light/Full
- KRX-023 Squelch knob ↔ gate threshold + bed level wiring
- KRX-024 Roger beep variants incl. in-band end marker

### E4 · LOCAL Networking
- KRX-030 NSD platform channel (register/browse, TXT records, MulticastLock lifecycle)
- KRX-031 LAN signaling WebSocket + peer session management
- KRX-032 WebRTC mesh audio (pre-published muted track, enable-on-grant)
- KRX-033 UDP broadcast discovery fallback + `LAN?` troubleshooting card
- KRX-034 Peer churn handling, 16-peer envelope soft cap
- KRX-035 LAN telemetry pings → S-meter mapping

### E5 · Floor Control
- KRX-040 Protocol v1 codec + versioning
- KRX-041 Arbiter election + lease lifecycle + self-heal
- KRX-042 Busy lockout, TOT (warn/cut), latch, deny paths
- KRX-043 Emergency pre-emption end-to-end
- KRX-044 Simulation test harness: 500-run randomized churn/loss soak, zero double-grants; asserts the locked timing constants and peerId election properties of §8.6

### E6 · LINKED Networking
- KRX-050 Relay deployment: LiveKit + Redis + coturn + Caddy compose; hardening checklist
- KRX-051 Token service (FastAPI, JWT mint from room derivation, rate limiting)
- KRX-052 `livekit_client` integration: join/publish/subscribe mirroring PTT state
- KRX-053 Room derivation lib (numbered/keyed/scrypt) + vectors test suite
- KRX-054 Event QR generate/scan + `keryx://` deep links
- KRX-055 Link loss/regain behaviour (chirps, `NO LINK`, auto-fallback to LOCAL)
- KRX-056 Region salt setting

### E7 · AUTO Mode & Bridging
- KRX-060 AUTO mode policy engine (prefer-LAN logic)
- KRX-061 Dual-publish TX (LAN mesh + room simultaneously) — **Phase 2 (per D9)**; spec retained in §8.4
- KRX-062 **Resolved by D9:** implement AUTO-prefers-LINKED policy for Phase 1; capture LAN-routing-preference signal in the field test (feeds Phase 2 dual-homing go/no-go ADR)

### E8 · Radio Behaviours
- KRX-070 Monitor key; KRX-071 Scan (Pro); KRX-072 SAY AGAIN RAM ring buffer (Pro); KRX-073 Radio check; KRX-074 Presence panel flip; KRX-075 Callsign generator/editor; KRX-076 VOX (Pro)

### E9 · Platform Hardening
- KRX-080 Foreground service + notification actions
- KRX-081 Audio routing matrix (speaker/wired/BT SCO) + device tests
- KRX-082 Wired-button PTT; KRX-083 BT PTT accessories (Pro); KRX-084 Volume-key PTT
- KRX-085 OEM-kill detection + battery guide (FR-105)
- KRX-086 Battery bench harness (automated standby-drain measurement) — **hard release gate**: Phase 1 does not ship with NFR-06 red

### E10 · Commercial & Launch
- KRX-090 Play Billing: Pro one-time unlock + feature gating
- KRX-091 Faceplate pack pipeline (asset format, 2 launch packs)
- KRX-092 First-run flow + permission explainers
- KRX-093 Store listing, screenshots (radio renders), privacy sheet (POPIA/GDPR)
- KRX-094 Field test protocol + 20-device event pilot playbook
- KRX-095 Opt-in LINKED diagnostics (off by default) + dashboards on relay host

---

## 12. Success Metrics

| Metric | Phase 1 target |
|---|---|
| First-TX time (install → first successful transmission, shared LAN) | ≤ 60 s median |
| D7 retention (activated = ≥ 1 TX) | ≥ 25% |
| TX per active session | ≥ 8 |
| LAN discovery success | ≥ 98% (NFR-04) |
| Pro conversion of users with ≥ 3 sessions | ≥ 4% |
| Play Store rating stabilised | ≥ 4.5 |
| Support themes | "It just worked at our event" > any single complaint theme |

---

## 13. Risks & Mitigations

| # | Risk | Sev | Mitigation |
|---|---|---|---|
| R1 | OEM background-kill breaks always-on monitor | High | Foreground service done right (KRX-080), kill detection + guided whitelisting (KRX-085), automated soak tests per OEM (KRX-086) |
| R2 | mDNS blocked on guest/AP-isolated networks | High | Broadcast fallback (KRX-033), `LAN?` card, Hotspot Mode in Phase 2 as the ultimate answer |
| R3 | LAN mesh degrades past ~16 peers | Med | Enforced soft cap + on-display guidance to split channels; Teams tier later moves big groups to relay |
| R4 | Relay cost/abuse on numbered channels | Med | Token-svc rate limits, per-room caps, no public directory (P6), regional salts fragment drive-by scanning |
| R5 | Latency variance on mobile data breaks the illusion | Med | Honest S-meter (P7), adaptive jitter buffer, FEC on, clear `NO LINK` degradation — the radio *admits* weakness like real radios do |
| R6 | Skeuomorphic UI polarises reviewers | Low | It is the product (P1); default faceplate kept restrained; contrast/accessibility guaranteed (FR-106) |
| R7 | iOS later: background mic + review friction | Med (Ph3) | Documented strategy ticketed in Phase 3; nothing in the architecture presumes Android-only APIs except isolated platform channels |
| R8 | Sound licensing gaps | Low | Commission-first policy (D6), licences archived in-repo with the assets |

---

## 14. Deliberately Deferred / Out of Scope

- Text chat, images, message history, read receipts — **permanently out** (P5).
- Public global channel directory — out until a moderation story exists (P6).
- Location sharing on emergency — revisit with explicit consent design, Phase 3 at earliest.
- Recording/exporting transmissions — conflicts with P6; SAY AGAIN stays RAM-only.
- Server-side voice storage of any kind — permanently out.
- Wi-Fi Direct — superseded by Hotspot Mode + Wi-Fi Aware evaluation.

---

## Appendix A — Traceability to the Draft PRD

Every element of the source draft is either matured here or explicitly rejected with rationale: networking & discovery → §5.3/§8.3–8.4; PTT core → §5.2/§8.5; radio metaphor & channels → §5.1/§5.4/§6; audio realism → §7; UI/UX → §6; architecture directions → §8 (incl. the recorded rejection of raw UDP multicast); challenges (latency, battery, permissions, privacy, scale, legal) → §8.5, §8.8, FR-104, §8.7, R3/R4, §1; competitive landscape → §1/§4 anti-persona; suggested Phase 1 scope → §10 Phase 1; all six closing discussion questions → §3 (D1–D6).

*End of specification — KERYX v1.0.*
