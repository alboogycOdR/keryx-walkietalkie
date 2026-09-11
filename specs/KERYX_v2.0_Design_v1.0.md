# KERYX v2.0 — UX & Interaction Design

> **Version:** 1.0 | **Date:** 2026-09-11 | **Companion:** `KERYX_v2.0_PRD_v1.0.md`
> **Inherits:** the R1 design system (`KERYX_Mobile_UX_Redesign_Design_v1.0.md` §3 tokens, typography, spacing, motion) as amended by ADR-002 (amber accent, dark PTT ring, Talk-first shell, icon tab strip). Only what changes is written here.

## 1. Information architecture

```text
KERYX (Talk-first)
├── Talk            ← default tab; the ring for the *current target*
├── Contacts        ← people, with presence and pending requests
├── Groups          ← named groups, members online / total
└── ⋮  Settings · Radio controls · My code
```

The top app bar keeps the wordmark and the connection dot. The ⋮ menu gains **My code** (ID QR + link + share). The three tab icons become: mic (Talk), person (Contacts), groups (Groups). Tab strip behaviour, no-swipe rule and Android back rules carry from TASK-077.

**Current target.** Talk always has a target: the last contact or group talked to, or the first group, or "no target" on a fresh install. Tapping a contact or group anywhere makes it the current target and switches to Talk. The target is shown in the Talk header card in place of `CH NN · CC`.

## 2. Screen contracts

### 2.1 Talk
Header card: avatar (initials, or a group glyph with member count), name, presence line (*Ben · Available · Nearby* / *Site crew · 4 of 12 online*), a **status control** for your own status on the right, and a chevron that opens the target's detail sheet. Below: overlay banners (emergency, latched, permission, service fault, "nobody is listening"). The PTT ring (ADR-002 A3) is centred in the remaining space with the status text under it. The ring's ready state depends on V2-FR-041: accent when someone can hear, neutral otherwise, with the reason as the status line.

No-target state: the ring is replaced by a card with *Add your first contact* (QR scan / share my code) and *Create a group*.

### 2.2 Contacts
Sections: **Requests** (incoming, with Accept / Decline / Block on the row), then **Contacts** alphabetical. Row: initials avatar with a presence dot (green Available, amber Busy, grey DND with a moon glyph, hollow grey Offline), callsign, short code in mono, derived state text (*Nearby*, *Talking*). Row tap → Talk with this target. Long-press → sheet: Alert, Remove, Block. Floating action: **Add contact** → sheet with *Scan a code*, *Show my code*, *Paste an ID*.

### 2.3 Groups
Rows: group glyph, name, *n online · m members*. Tap → Talk with this target. Chevron → group detail: member list with presence, admins marked, invite QR/link (admins and members alike can invite unless the admin turns it off), Leave, and for admins: Rename, Remove member, Rotate key, Make admin. Floating action: **New group** / **Join with a code**.

### 2.4 My code
Full-screen QR of the ID with the callsign and code beneath, a *Share link* button, and a copy affordance. The screen brightens to maximum while shown.

### 2.5 Contact request
A modal sheet: *Add BEN·4R2M?* with the sender's callsign and code (never a photo, there are none), Accept (accent), Decline, Block (destructive, requires a second tap).

### 2.6 First run
Callsign entry → recovery-phrase screen (12 words in a 3×4 grid, mono, numbered; a *Copy* is deliberately absent; *I've written it down* is the only way forward; screenshots are blocked on Android) → Talk in the no-target state.

### 2.7 Settings
Sections: Radio (Monitor, Scan, latch, TOT as before), Audio, Identity (callsign, *Show recovery phrase* behind device lock, *Restore from phrase*), Connectivity (relay address, prefer direct on Wi‑Fi), Messages (retention default 7 days, greyed with "used from v2.1"), Appearance, About.

## 3. Presence visuals

| State | Dot | Text |
|---|---|---|
| Available | `state/rx` green | Available |
| Busy | `state/warning` amber | Busy |
| Do Not Disturb | `text/secondary` grey with moon glyph | Do Not Disturb |
| Offline | hollow `border/default` | Offline · 2 h ago |
| Talking (derived) | pulsing ring around the dot | Talking |
| Nearby (derived) | small Wi‑Fi glyph | Nearby |

Colour is never the only cue: every state has a word.

## 4. State catalogue additions

| State | Main label | Treatment |
|---|---|---|
| No target | Add your first contact | Card replaces the ring |
| Nobody listening | Nobody is listening | Neutral ring; press refused with a 1.5 s flash |
| Target on DND | Ben is on Do Not Disturb · Alert? | Neutral ring; Alert control shown |
| Alert received | BEN·4R2M alerted you | Full-width accent banner, 10 s, with *Reply* |
| Request pending | Waiting for Ben to accept | Contact row with an hourglass |
| Key rotated | Site crew's key changed; you're still in | Toast |
| Removed from group | You were removed from Site crew | Toast; group disappears from the list |

All v1 floor states (Requesting, TX, Receiving, Latched, Emergency, TOT) keep their ADR-002 treatments.

## 5. Copy

Plain language, sentence case. "Nobody is listening." "Ben is on Do Not Disturb." "Add BEN·4R2M?" "You were removed from Site crew." "Write these 12 words down and keep them safe. They are the only way to get your KERYX ID back." Never "channel", "tune", "station", "LOCAL", "LINKED" or "AUTO" anywhere in the user-facing copy.

## 6. Accessibility

Carries R1 §5 and ADR-002 A4. Additions: the presence dot has a semantic label with the state word; the recovery-phrase grid is readable word by word by TalkBack; QR screens have a "Share as link" alternative for users who cannot scan.
