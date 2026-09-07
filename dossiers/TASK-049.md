# TASK-049 — Channels landing screen

## Brief

The default landing screen, built fresh against the new Design spec's mockup:
connection indicator, current-channel card, Open Talk, recent-channel recall,
Select channel, persistent nav. Reads only TASK-046's projection and dispatches
only its typed intents. Two easy-to-violate prohibitions carry most of the risk:
no fake online count, and no background subscription sweep across the 99-channel
space to populate presence.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.1 (content order, card
  contents, recents, empty state, the two prohibitions), §1.
- PRD UX-D01, UX-D05 (recall is not history), UX-FR-002/004/005/008/010.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §6 — channel-memory writes
  stay serialized and deduplicated; no schema expansion for R1.
- Verification VT-020 (recall order/deduplication).

## Approach

New widgets per ADR-001 §7 item 2 — nothing from TASK-043 is wrapped. Configured
mode and actual status are separate fields on the card. Recent entries route
through the authoritative tune intent; the selector flow itself is TASK-050's,
this screen only launches it. Widget tests run against fake host/projection —
no sockets, no native plugins (Verification §2).

## Work Log
