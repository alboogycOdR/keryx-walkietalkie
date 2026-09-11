# TASK-091 — v2 Groups tab — list, detail with members and presence, invites, admin actions, join with a code

## Brief

The Groups tab body and the group detail screen. List rows: glyph, name, `n online · m members`; tap → `onSelectTarget(group)`; chevron → detail. Detail: member list with presence and admin marks, invite (QR + link per Technical §5.2 with the expiry presets reused from `event_link.dart`), Leave, and admin-only Rename, Remove member (which triggers rotation through the groups store), Rotate key, Make admin. Floating: New group (name → create → invite screen) and Join with a code (scan or paste). Toasts for 'key changed' and 'you were removed'. Uses the TASK-086 groups store and TASK-087 room derivation; no shell dependencies.

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §2.3, §4 (key rotated / removed states); PRD V2-FR-020..025; Technical §5.2 (invite link); Verification V2-VT-026, V2-VT-030 (groups goldens)
- Owned_Paths: lib/features/groups/**, test/features/groups/**, dossiers/TASK-091.md
- Depends_On: TASK-086, TASK-087

## Work Log
