# KERYX v2.0 — Verification & Acceptance Plan

> **Version:** 1.0 | **Date:** 2026-09-11 | **Companions:** PRD, Design, Technical v1.0
> **Principles carried from R1 §0:** a passing mocked test proves nothing about real audio or the real server; a wiring change needs a test on the real composition; historical tests are migrated, not deleted, when the behaviour survives.

## 1. Traceability

Every `V2-FR`/`V2-NFR` maps to at least one `V2-VT` below. PLAN.md acceptance criteria cite the VT, and the VT cites the FR.

## 2. Environment

Flutter 3.41.6 / Dart 3.11.4 on the build machine (record if different). Directory service tests run with `pytest` against a disposable Postgres (`testcontainers` or the compose file). Real-device rows use the Honor CRT-NX1 (Android 15) and Samsung A05s (Android 14) unless the owner supplies others.

## 3. Identity tests

- **V2-VT-001 Key generation and ID** — fresh install yields a valid Ed25519 pair; `peerId` and `shortCode` derive deterministically from the public key; two installs never collide in 10,000 trials (V2-FR-001).
- **V2-VT-002 Recovery phrase** — 12 valid BIP-39 words; phrase → seed → the same key; a one-word change restores a different key; the phrase screen blocks copy and screenshots (V2-FR-002/003).
- **V2-VT-003 ID QR and link** — encode/decode round-trip carries the key; a tampered key fails verification locally with no network (V2-FR-004).
- **V2-VT-004 Request signing** — a valid signature is accepted; stale timestamp (>120 s), replayed nonce, wrong key are each rejected with the enumerated error (Technical §3.3).

## 4. Directory service tests (pytest)

- **V2-VT-010 Contacts lifecycle** — request → accept creates a symmetric link; decline creates nothing; block prevents re-request; expiry at 7 days; 21st outstanding request refused (V2-FR-010–013).
- **V2-VT-011 Groups lifecycle** — create → invite → join → member list; 26th join refused; leave; last-admin succession; remove requires rotate; rotate bumps `key_version` and stores only the sealed copies supplied (V2-FR-020–024).
- **V2-VT-012 Secrets never plaintext** — a scan of every table after the lifecycle shows no group secret, no private key, no audio (V2-NFR-004/007).
- **V2-VT-013 Presence** — heartbeat keeps Online; 5 min silence → Offline; a status change reaches a connected contact within 5 s; non-contacts receive nothing (V2-FR-030–032, V2-NFR-003).
- **V2-VT-014 Token gate** — `/token` refuses a non-member and an unsigned caller; accepts a member (Technical §4.2).
- **V2-VT-015 Alerts rate limit** — second alert to the same target within 10 min is refused (V2-FR-050).
- **V2-VT-016 Storage budget** — after 1,000 users × 20 contacts × 3 groups, table size per user < 4 KB and per membership < 2 KB (V2-NFR-007).

## 5. Client tests (Flutter)

- **V2-VT-020 Room derivation** — group room from secret is stable; 1:1 room is identical from both sides; rotation changes the room (Technical §5).
- **V2-VT-021 Target switch** — `switchTarget` tears down and rebuilds within 1 s in the fake; `updateRoster` is called at start with the full member list; a solo station is refused at the presentation layer, never reaching `press()` (Technical §1.1, V2-FR-044).
- **V2-VT-022 Audience ready state** — matrix over {online, offline, DND, busy} × {contact, group} yields the correct ring treatment and reason string (V2-FR-041, Design §4).
- **V2-VT-023 Transport selection** — LAN-discovered listener → direct; otherwise relay; both at once in a mixed group; the header mark matches (V2-FR-043).
- **V2-VT-024 Floor unchanged** — the v1 VT-010–VT-015 suite passes unmodified in intent against v2 targets (V2-FR-042).
- **V2-VT-025 Contacts UI** — requests section, accept/decline/block flows, presence dots and words, long-press sheet (Design §2.2).
- **V2-VT-026 Groups UI** — list counts, detail, invite, admin actions, removal toast, rotation notice (Design §2.3).
- **V2-VT-027 Onboarding and restore** — first run reaches Talk no-target state only after the phrase gate; restore reproduces the ID (Design §2.6, V2-FR-003).
- **V2-VT-028 Removal audit** — repo-wide grep of `lib/` for `channel`, `privacy code`, `LOCAL`, `LINKED`, `AUTO`, `Stations` in user-facing strings returns nothing; deleted modules are absent (PRD §1, §5.5).
- **V2-VT-029 Shell** — tabs are Talk/Contacts/Groups; ⋮ has My code; Android back rules from TASK-077 still hold via real `handlePopRoute` (Design §1).
- **V2-VT-030 Goldens** — Talk (no-target, ready, nobody-listening, DND target, alert banner), Contacts (empty, populated, with requests), Groups (empty, populated), group detail, My code, phrase screen, in dark and light.

## 6. Real-device matrix (owner-run, recorded in `ops/FIELD_TEST_V2.md`)

| Row | What | Pass when |
|---|---|---|
| A | Meet and add by QR | Under 60 s from opening the scanner to hearing each other (V2-NFR-001) |
| B | Add by link over WhatsApp | Request arrives and accepts |
| C | Group of 5 across two networks | One speaker at a time, correct callsign on every screen, direct mark on LAN pairs, relay mark on remote |
| D | Presence | DND on one phone shows within 5 s on the other; talk is refused with the reason; Alert breaks through once |
| E | Rotation | Removed member cannot hear the group after removal |
| F | Restore | Wiped phone + phrase → same ID, contacts, groups |
| G | Background and lock | Talk continues with the screen locked; app switch and return keep the target |
| H | No internet, same Wi‑Fi | Two contacts on a router with no uplink still talk directly |
| I | Upgrade from v1 | Callsign kept, phrase shown, channel memory gone, no crash |

## 7. Safety and privacy regression

Carried from R1 §8: mic muted before publish and after release; floor exclusivity; no recording persistence (v2.0 stores no audio); no analytics; no contacts permission in the manifest; no unexpected network calls (the only hosts are the relay and directory). New: the directory logs contain no callsigns, keys or room IDs (extend `logging_policy.py`'s `PrivacyFilter`).

## 8. Exit gates

- **G1** Directory service green in CI with V2-VT-010–016.
- **G2** Client suite green, analyzer clean, goldens frozen.
- **G3** Real composition test boots the shell against a stubbed directory and reaches Talk.
- **G4** Device matrix rows A–I recorded with evidence; failures recorded as failures.
- **G5** Owner acceptance on the PRD §5 list; release build hashed and delivered.
