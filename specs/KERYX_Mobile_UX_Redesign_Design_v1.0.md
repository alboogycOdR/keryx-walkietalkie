# KERYX — Mobile UX Redesign & Interaction Specification

> **Version:** 1.0 | **Status:** Proposed design baseline | **Date:** 2026-09-07  
> **Companion:** `KERYX_Mobile_UX_Redesign_PRD_v1.0.md`  
> **Changelog:** v1.0 — defines the original KERYX mobile application experience and replaces the mandatory hardware-face visual direction upon owner approval.

## 0. Design authority

This document specifies the mobile UI direction for R1. It does not override the legacy communication, floor, audio or security contracts. Existing faceplate tokens, seven-segment LCD styling, housing proportions, grille and large industrial disc are not mandatory in the successor UI. Retain the old implementation and golden evidence until the new design and regression suite are approved. Existing state colors and assets may be reused only when they meet the new design's semantics and accessibility criteria.

The design is inspired by the clarity of established PTT applications, not a pixel-for-pixel reproduction of Zello. No third-party logo, icon set, proprietary screenshot or copyrighted asset may be copied into production.

## 1. Information architecture

R1 is channel-first. Do not introduce an empty Contacts or History destination to imitate another product.

```text
KERYX
├── Channels (default)
│   ├── Current channel
│   ├── Recent channels (existing memory)
│   ├── Select / direct tune
│   └── Talk
│       ├── Live channel status
│       ├── PTT
│       ├── Stations
│       ├── Radio controls
│       └── Event QR / share
└── Settings
    ├── Radio
    ├── Audio
    ├── Connectivity
    ├── Identity
    ├── Appearance
    └── About
```

Use two persistent primary destinations: Channels and Settings. Recent channels belong on Channels for R1. Talk is a dedicated route or nested channel destination, but its presentation lifecycle must not own the radio session. Secondary screens and sheets return to the previous context without changing the current channel.

## 2. Screen contracts

### 2.1 Channels — landing

Content order: brand/title and current connection indicator; current channel card; primary Open Talk action; recent channel list; Select channel action; persistent navigation. Current channel card shows formatted channel/code, configured mode and a concise actual status. A current-channel shortcut must be reachable with one tap.

Recent entries show their actual channel/code values and remain selectable. Empty memory uses a neutral explanatory message and a direct tune action. Do not show a fake online count. A channel row may show presence only when verified for that channel; no new background subscriptions to all 99 channels are authorized.

### 2.2 Talk — primary communication

Content order: compact back/channel header; connection and presence line; active speaker/ready status; primary PTT; secondary action row; safe-area footer. The Talk screen does not need a scrolling conversation transcript.

The PTT area must remain visible at the bottom portion of the safe content area. Use responsive constraints rather than a fixed 320 dp disc or viewport-height percentages. The normal control is a large rounded circular or pill-shaped surface, with a minimum 96 dp primary dimension and a 48 dp minimum hit target for every secondary action. The design shall be tested on a small Android phone before the size is frozen.

The header identifies the current channel and code, offers a clear channel picker, and distinguishes effective route from configured preference. Tapping Stations opens the live roster. The active speaker region shows a known callsign, otherwise a neutral identifier or “Someone is speaking.” When idle it shows “Channel clear” and “Hold to talk.” A disconnected screen must not show “Ready.”

The primary PTT must expose an accessible hold action and a non-drag alternative. Optional latch is clearly labeled. Ordinary PTT and Emergency are separate controls; the emergency feature must never be hidden behind a destructive-looking ordinary PTT label.

### 2.3 Channel selector

Provide a searchable/selectable numbered list or direct numeric entry. Users can enter channel 1–99 and code 0–38, with labels formatted as two digits. The existing six-entry recall appears as a separate recent section. Apply is disabled for invalid values. Cancel leaves the current channel untouched.

Do not treat a cosmetic channel name as a new room. A pending retune shows progress and prevents competing tune actions. The user must receive clear success/failure feedback. The currently active channel remains authoritative until the selected operation succeeds or a documented rollback/recovery policy applies.

### 2.4 Stations

Use a full-screen list or sheet with known callsigns and actual presence. It must update while open without relying on a parent-screen rebuild. Include an empty state, current-channel context and existing Event QR actions. Do not turn local station presence into a global contacts directory. Quality information is omitted or marked unavailable unless a real metric exists. If LINKED roster support is incomplete, explicitly state that a complete member list is unavailable rather than displaying zero as a verified count.

### 2.5 Radio controls

Provide labeled rows or controls for available Monitor, Scan, Latch, Replay/VOX where implemented, and Emergency. Monitor retains hold-to-open semantics; a toggle may be offered only if an approved separate latch behavior exists. Scan shows authoritative active state and eligibility. Locked/unsupported actions must explain their status rather than pretend to work.

Emergency requires a separate orange/priority treatment, a clear activation affordance and an explicit clear action. Preserve the existing emergency hold duration and floor behavior unless a separate ADR changes them. No automatic location transmission is introduced.

### 2.6 Settings

Use ordinary mobile settings with sections and readable descriptions. Retain every existing setting and its validation. Connectivity shows the configured mode, effective route and LOCAL-only privacy toggle. Audio includes current sound and available routing options. Identity includes current callsign editing. Appearance includes theme and optional night-dimming controls. About includes version and relevant diagnostics.

A setting that rebuilds the communication session must not look like a harmless appearance-only toggle. Show an explanatory confirmation when applying it could interrupt transmission or change network connectivity. Non-session settings must not needlessly reconnect.

### 2.7 Event QR

Preserve existing scan and export components, with modern framing and appropriate camera/permission states. The scan result must not silently fail in LOCAL mode when a LINKED session is required. Provide a clear explanation and explicit route transition, or keep the operation unavailable with a reason. Do not invent keyed-channel UI behavior that the current session implementation cannot execute.

## 3. Visual design system

### 3.1 Direction

Original, calm, modern and functional. Use a dark-first interface with a complete light theme. Surfaces are flat or subtly elevated, with restrained borders and no simulated screws, molded textures, seven-segment glass or faux hardware housing. The radio character comes from channel terminology, sound and reliable PTT behavior, not from making every screen resemble equipment.

### 3.2 Proposed tokens

These are design tokens to be ratified in the prototype; do not scatter literal color values across widgets.

| Token | Dark | Light | Role |
|---|---|---|---|
| `surface/base` | `#101318` | `#F7F8FA` | Screen background |
| `surface/card` | `#1B2028` | `#FFFFFF` | Cards and sheets |
| `surface/raised` | `#252C36` | `#E9EDF3` | Secondary controls |
| `text/primary` | `#F4F6F8` | `#18202A` | Main text |
| `text/secondary` | `#A7B0BD` | `#566272` | Supporting text |
| `border/default` | `#343D49` | `#D5DCE5` | Separators |
| `action/primary` | `#4D8DFF` | `#2467D9` | Ready and interactive action |
| `state/tx` | `#E45A52` | `#B52F2B` | Granted local transmission |
| `state/rx` | `#55C39A` | `#167D58` | Receiving |
| `state/warning` | `#F0B44C` | `#936000` | Busy, request warning |
| `state/emergency` | `#F28C45` | `#A94A09` | Emergency priority |

Color values must pass contrast verification. Use color only as a redundant state cue; every state also needs text or an icon. Red TX treatment is reserved for actual local transmission; emergency has its own distinct indication and may coexist with a TX state.

### 3.3 Typography and spacing

Use the existing Inter asset or an appropriate platform font, with normal sentence case for app labels. Recommended scale: screen title 24/30 semibold, section title 18/24 semibold, body 16/24, secondary 14/20, compact metadata 12/16. Support system text scaling without truncating critical state labels. Eight-dp base grid, 16-dp horizontal page margins on normal phones, 12–16-dp card spacing, and 8–12-dp internal control gaps. Minimum touch target 48 × 48 dp. Avoid a fixed full-screen height allocation.

### 3.4 Icons and motion

Use a consistent icon family with accessible labels, not mixed decorative emoji. Motion is functional: 120–200 ms for state changes and 200–300 ms for page/sheet transitions. Reduced-motion settings remove decorative animation but retain critical state changes and audio/haptic feedback where allowed by settings. No continuously animated fake waveform presented as real audio telemetry.

## 4. State presentation catalogue

| State | Main label | Primary treatment | Interaction |
|---|---|---|---|
| Off | Radio off | Neutral disabled | Power-on/recovery |
| Boot | Starting radio | Neutral progress | TX unavailable |
| Ready | Hold to talk | Primary blue | Hold begins request |
| Requesting | Requesting channel | Pending/amber | No duplicate request |
| TX granted | Transmitting | Red + timer if authoritative | Release to end |
| Receiving | [Callsign] speaking | Green + speaker icon | Busy lockout applies |
| Denied/busy | Channel busy | Amber transient + reason | No false TX |
| No link | Connection unavailable | Neutral/warning | Retry or LOCAL fallback |
| Tuning | Changing channel | Progress + target | Prevent competing tune |
| Latched | Transmission locked | Red + explicit release | Tap release |
| Emergency | Emergency active | Orange priority banner | Explicit clear |
| Permission denied | Microphone required | Persistent actionable message | Open permission recovery |
| Service fault | Background service unavailable | Warning + recovery | Foreground use as supported |

State precedence is not a single skin switch. Emergency is an overlay, not a replacement for floor phase. A denied flash cannot override a currently granted TX, and a global connection error cannot conceal an active floor state. Implement a documented composite presentation model with independent fields and deliberate priorities.

## 5. Copy and accessibility

Use plain language: “Channel clear. Hold to talk.”, “Requesting channel…”, “Channel busy”, “Connection lost”, “Microphone permission required”, “No other stations are currently visible”. Do not show raw exceptions or internal service names to ordinary users. A technical-details affordance may expose sanitized diagnostics.

Every action has a semantic label and state. TalkBack must announce meaningful floor transitions without repeating every animation frame. Provide a switch-accessible alternative to mechanical hold where the chosen behavior is safe and explicit. Keyboard and screen-reader users must be able to tune, cancel, open Stations, navigate Settings and release a latched TX. Do not require color, sound or haptics alone to understand a state.

## 6. Design deliverables and gates

The design sprint must produce an original high-fidelity prototype for Channels, Talk, Channel selector, Stations, Radio controls, Settings, QR entry and all significant states. Include dark/light themes, small-phone and landscape layouts, typography and token documentation. Design sign-off precedes production implementation and replaces the old hardware-face golden baseline only for the approved successor surfaces.

Owner approval gate: review the landing navigation, PTT size and placement, channel-selection flow, emergency control, Settings hierarchy and state catalogue. Do not implement a Contacts/History product based solely on a visually appealing mockup. Once ratified, golden tests shall freeze the approved compositions.
