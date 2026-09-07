# KERYX — Mobile UX Redesign Product Requirements

> **Version:** 1.0 | **Status:** Proposed for owner approval and DEVDepartment planning  
> **Date:** 2026-09-07 | **Owner:** Basileia Technologies  
> **Baseline:** `master` at `55c51da237c89767806969a52b30cc30e44025c9` (2026-09-06). Revalidate before decomposition.  
> **Companions:** `KERYX_Mobile_UX_Redesign_Design_v1.0.md`, `KERYX_Mobile_UX_Redesign_Technical_v1.0.md`, `KERYX_Mobile_UX_Redesign_Verification_v1.0.md`.  
> **Changelog:** v1.0 — initial successor specification for a modern mobile interface while retaining the existing communication implementation.

## 0. Authority and approval

The owner has requested a Zello-inspired transformation of the existing radio-console interface. This is a successor product direction, not permission to rebuild the communication backend. The existing product specification v1.1 expressly requires a hardware-radio face, prohibits bottom navigation and message history, and describes the product as not being a chat app. The existing UI specification v1.0 also locks the hardware design. These conflicts must be resolved explicitly by an owner-approved ADR before implementation.

After approval, this successor takes precedence only for the UI, navigation, presentation and interaction provisions explicitly replaced here. All other existing functional, security, privacy, audio, connectivity and performance requirements remain binding. ORCH must record any further conflict instead of silently overriding an existing requirement. The current prototype and golden tests are a historical baseline, not a mandate to reproduce the old appearance in the new shell.

This specification is a product input for the existing DEVDepartment process. It does not itself assign tasks, change PLAN.md, activate builders or authorize a merge. ORCH remains responsible for reconciliation, planning, ownership, review and integration.

## 1. Vision and success criteria

KERYX shall become a modern Android-first push-to-talk application that makes it easy to select a channel, see who is present or speaking, and transmit using one prominent control. Zello is an interaction and information-architecture benchmark, not a source of branding, proprietary assets, exact screen copies or a requirement to reproduce its entire feature set.

KERYX retains its distinctive local-first, accountless operation, numbered channels, privacy-code semantics, radio sound design, floor discipline and existing relay architecture. The primary experience shall remain useful on an isolated Wi-Fi network without internet access.

A successful R1 release allows a first-time user to identify the current channel, understand whether it is ready or busy, and communicate without learning an LCD instrument. A returning radio user must still have direct tuning, rapid PTT access and reliable screen-off behavior. The redesign must not compromise working audio or transport functionality.

## 2. Release boundaries

### 2.1 R1 — existing communication, new application experience

R1 includes the new application shell, Channels landing page, live Talk screen, channel selector, existing recent-channel recall, live station roster, modern Settings, existing Event QR flows, secondary radio controls, meaningful empty/error states, and a new visual system. Existing LOCAL/AUTO/LINKED, PTT, audio, permissions and background capabilities are retained. No new backend endpoint is required to make the principal workflow usable.

### 2.2 R2 — optional future expansion

Saved contacts, direct one-to-one communication, a richer channel directory, persistent conversation history, text messaging, media sharing, cloud message synchronization and managed teams are separate product initiatives. They require explicit privacy, identity, storage, retention, abuse-prevention and backend specifications. R1 may provide only genuinely implemented features. Do not populate future tabs with fake contacts, messages, unread counts, histories or presence.

### 2.3 Out of scope

No mandatory account, public global directory, social feed, contact sync, new messaging backend, cloud voice archive, server-side recording, automatic location sharing, new subscription model, replacement transport protocol, replacement floor engine or new recording retention policy is authorized. R1 does not require a legacy hardware-face toggle. Existing features that are not implemented must not be presented as functional.

## 3. Decisions for owner ratification

| ID | Decision | Proposed resolution |
|---|---|---|
| UX-D01 | Default landing | Channels, with the last-used channel immediately accessible. |
| UX-D02 | Primary navigation | Channels and Settings are required. Recents may be a separate tab or a section based on actual stored data. No empty Contacts tab in R1. |
| UX-D03 | PTT | Hold-to-talk remains default. Existing optional latch behavior is retained with an explicit indicator and release action. |
| UX-D04 | Hardware face | Retire the full-screen console as the mandatory home. An optional classic theme is a future initiative, not an R1 dependency. |
| UX-D05 | History | Six-entry channel recall is not message or audio history. No persistent history is introduced. |
| UX-D06 | Emergency | Preserve existing priority/floor semantics, with a distinct guarded emergency control. |
| UX-D07 | Connectivity | Preserve actual LOCAL/AUTO/LINKED behavior and LOCAL-only privacy guarantees. No unimplemented dual-homing claim. |
| UX-D08 | Appearance | Original KERYX visual identity, modern mobile layout, light/dark support and explicit state colors. |
| UX-D09 | New services | R1 does not add contacts, messaging or account infrastructure. Any future expansion requires a separate approved spec. |

## 4. User journeys

### 4.1 First launch

The existing identity and permissions bootstrap completes. The user arrives at Channels, sees the default channel and can open Talk without signing in. No tutorial carousel or internet connection is required. A microphone denial provides a persistent actionable explanation and does not show a usable transmit state.

### 4.2 Select and talk

The user selects a channel, optionally enters a privacy code, and sees its live Talk screen. The selected channel, effective route, connection condition and known presence are visible. A PTT press requests the floor. The screen distinguishes requesting from granted TX; release returns the floor through the existing engine. Busy lockout provides explicit feedback rather than pretending the microphone is live.

### 4.3 Receive and navigate

A receiving station is identified by its known callsign where available. Unknown identities have a neutral fallback. Visiting Settings, Stations or another secondary view must not silently power off the radio or create a second session. Returning to Talk shows the current state. A deliberate channel change invokes the actual retune workflow.

### 4.4 Join an event

Scan an existing Event QR or open an existing supported deep link. Validate the payload and expiry using existing contracts. If the current route cannot join, explain the required connectivity change and provide a cancel path before a network-affecting transition. A failure must not leave a falsely selected channel or an apparently connected session. Export retains the existing expiry choices and does not expose private passphrases unnecessarily.

### 4.5 Configure and recover

The user can configure radio, audio, identity, connectivity and appearance settings in conventional screens. Session-affecting changes are applied through the authoritative controller. On connection loss, the app displays the real condition and existing fallback behavior. It must never advertise LAN/WAN simultaneous bridging if not implemented.

## 5. Functional requirements

All R1 requirements below are Must unless marked Should. The verification specification defines their acceptance evidence.

### 5.1 Navigation and channels

| ID | Requirement |
|---|---|
| UX-FR-001 | Provide a modern app shell with Channels and Settings destinations. Route changes must not own or destroy the radio session. |
| UX-FR-002 | Display current channel, privacy code, configured mode and actual/effective connection condition without conflating them. |
| UX-FR-003 | Support direct entry for channels 01–99 and privacy codes 00–38 with validation, Apply and Cancel. |
| UX-FR-004 | Present existing six-entry channel memory truthfully; selecting an entry invokes authoritative tuning. |
| UX-FR-005 | Preserve the current channel when navigating between screens. Navigation alone cannot retune. |
| UX-FR-006 | Preserve implemented private/keyed-channel access. Do not claim that numeric privacy codes provide encryption. |
| UX-FR-007 | Keep the current channel identifiable when a keyboard, sheet or secondary page is displayed. |
| UX-FR-008 | Do not display unsupported contacts, members, messages, history or unread counts. |
| UX-FR-009 | Offer a clear channel-selection result: pending, connected, failed or unavailable, with a safe retry/cancel path. |
| UX-FR-010 | Use the existing actual channel/code namespace; cosmetic labels or favorites must not redefine room identity. |

### 5.2 Talk and floor control

| ID | Requirement |
|---|---|
| UX-FR-020 | PTT is prominent, thumb-accessible and visible in portrait without scrolling. |
| UX-FR-021 | Preserve the current request/grant/release path. Pointer-down alone must never indicate granted transmission or publish audio. |
| UX-FR-022 | Distinguish ready, requesting, TX granted, receiving, denied/busy, unavailable/off, degraded connection and latched states with text/icon as well as color. |
| UX-FR-023 | Preserve busy lockout, TOT, grant/deny/release feedback, emergency arbitration and existing audio behavior. |
| UX-FR-024 | Pointer cancellation, lost gesture and disposal of a held PTT surface safely release ordinary hold intent, with no accidental latch. |
| UX-FR-025 | Latch mode remains explicitly indicated and reliably releasable. Navigation must not create a latch or inadvertently release an intentionally latched session. |
| UX-FR-026 | Display the active speaker using a real roster mapping where available. Never present a peer ID as a verified human name. |
| UX-FR-027 | Do not label simulated activity as a measured mic or network level. Decorative animation is allowed if explicitly non-telemetric. |
| UX-FR-028 | Preserve screen-off and notification PTT behavior, native service ownership, routing and audio focus. |
| UX-FR-029 | The UI must not expose a live transmit action while booting, permission-denied, powered off or lacking a usable floor engine. |
| UX-FR-030 | A channel or route change during TX must be serialized safely; ordinary navigation must not interrupt TX. |

### 5.3 Stations, controls and emergency

| ID | Requirement |
|---|---|
| UX-FR-040 | Reuse live station presence, with join/depart updates, on a dedicated screen or sheet. |
| UX-FR-041 | Move secondary functions into clearly labeled Radio controls while preserving their actual semantics, including monitor hold behavior. |
| UX-FR-042 | Preserve emergency activation and clear behavior. Emergency is visually distinct, explicitly labeled and protected against accidental initiation. |
| UX-FR-043 | Display monitor, scan, VOX, replay and emergency indicators only when authoritative state says they are active. |
| UX-FR-044 | Preserve entitlements; unsupported or locked capabilities cannot silently appear enabled. |
| UX-FR-045 | Show measured quality only when real telemetry is available. Otherwise show unavailable/unknown, not synthetic full-strength bars. |
| UX-FR-046 | Distinguish local station count from any unavailable LINKED member count; never imply the roster is complete when it is not. |

### 5.4 Settings and integrations

| ID | Requirement |
|---|---|
| UX-FR-060 | Reorganize existing settings into Radio, Audio, Connectivity, Identity, Appearance and About where applicable. |
| UX-FR-061 | Preserve stored settings, defaults, validation, migration and channel-memory behavior. |
| UX-FR-062 | Clearly expose LOCAL-only privacy and actual route state. No WAN operation may be initiated contrary to the existing force-LOCAL policy. |
| UX-FR-063 | Retain Event QR scan/export and supported deep-link handling, including expiry and error feedback. |
| UX-FR-064 | Preserve permissions, foreground-service fault handling, notification actions and device audio routing. |
| UX-FR-065 | Retain KERYX branding. Do not copy Zello artwork, logo, exact visual compositions or proprietary assets. |
| UX-FR-066 | Preserve existing sound preferences and radio feedback; no unapproved replacement of radio SFX with generic messaging sounds. |

## 6. Quality requirements

Existing audio latency, battery, background operation, privacy, floor exclusivity and network requirements remain binding. The redesign must not introduce a hot-mic window, duplicate floor ownership, reconnect regressions or arbitrary session teardown. All primary touch targets are at least 48 dp. Text and controls meet WCAG AA contrast, with TalkBack, scalable text, reduced motion and keyboard/switch access. Essential content must be usable on small phones and landscape and respect system safe-area insets.

## 7. Product acceptance

R1 requires: an approved successor ADR; a signed-off design baseline; an accountless LOCAL launch/tune/talk workflow; bidirectional voice on two real devices; supported LINKED operation; navigation without session duplication; safe PTT release; truthful connection/presence/quality indicators; complete existing tests without unexplained regressions; and an owner-reviewed release candidate. Adding contacts or messaging cannot substitute for any of these gates.

## 8. DEVDepartment intake

ORCH must read current PLAN.md, REVIEW.md, AGENTS.md, the coordination protocol, active branches/worktrees and all specifications before decomposition. The current source snapshot has frozen territories and uses `master` as the configured integration branch. Revalidate both facts before planning. Any frozen path requiring modification must be reopened through explicit successor tasks and non-overlapping ownership. Do not modify PLAN.md or dispatch builders as part of the spec-import operation. Owner approval of the decisions and a versioned ADR are required before implementation.
