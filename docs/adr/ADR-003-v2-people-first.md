# ADR-003: KERYX v2 — people-first model supersedes the numbered-channel radio

**Status:** ACCEPTED (owner decisions D1–D11, 2026-09-11)
**Date:** 2026-09-11
**Author:** ORCH
**Supersedes:** the channel/privacy-code model and the "public lobbies are the anti-persona" clause of `KERYX_Product_Technical_Spec_v1.1.md` (FR-001 family, §4, §8.4/§8.7 numbered derivation); the channel-first information architecture and the "no Contacts or History destination" rule of `KERYX_Mobile_UX_Redesign_Design_v1.0.md` §1 and PRD §2.3; ADR-001 §3 items that assumed channels.
**Keeps:** ADR-001 §5 (floor, audio, security contracts), ADR-002 (visual system, Talk-first shell, PTT ring, A7 transient deny), Verification §8's privacy commitments (no address-book upload, no analytics).

## Context
The owner tested the R2 build alone and found the channel model meaningless to a real user: a numbered channel with nobody on it, refused presses, and "Channel busy" with no one there. The owner chose a people-first model (contacts, groups, presence, voice delivered later) with AI in the talk path, and set a five-year goal of overtaking Zello. The full model is `specs/KERYX_v2_Product_Model_v0.2.md`; the v2.0 requirements are the `KERYX_v2.0_*` pack.

## Decision
Build v2.0 as specified. Concretely:
1. Identity is an Ed25519 key pair with a 12-word recovery phrase; no phone numbers.
2. Contacts are mutual, added by QR or link. Groups are keyed rooms with a member list, capped at 25.
3. Presence (Available / Busy / DND / Offline, plus derived Talking / Nearby) is served by the directory over WebSocket.
4. Numbered channels, privacy codes, the mode setting and the Stations screen are deleted. LAN direct talk stays as an automatic transport.
5. The token service grows into the directory service with Postgres; the relay stack is unchanged.
6. No pricing assumption anywhere until the full version ships (D8).

## Consequences
- Every v1 spec sentence about channels is void; builders must cite `V2-FR`/`V2-VT` IDs.
- The floor engine is untouched; its solo join-guard becomes moot because the roster is known at session start.
- TASK-059/060's remaining rows are superseded by the v2 device matrix (Verification §6); TASK-061's deletion scope folds into the v2.0 wave; TASK-062 is re-baselined to v2.0.
- The store-and-forward voice message (v2.1) is the answer to the lone-press question; v2.0 refuses honestly in the meantime.
