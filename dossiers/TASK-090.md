# TASK-090 — v2 Contacts tab — requests, contacts list with presence, add-contact sheet, Alert/Remove/Block

## Brief

The Contacts tab body, `embedded`-style like TASK-075/076: no app bar of its own. Sections: Requests (Accept / Decline / Block on the row) then Contacts alphabetical with the presence dot + word, callsign, mono short code, derived Nearby/Talking text. Row tap → `onSelectTarget(contact)`; long-press sheet → Alert (calls the directory client), Remove, Block (second-tap confirm). Floating 'Add contact' → sheet with Scan a code (use `mobile_scanner`), Show my code (`onShowMyCode` callback), Paste an ID. Incoming request modal per Design §2.5. Reads `ContactsController` from TASK-086; no session or shell dependencies.

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §2.2, §2.5, §3 (presence visuals), §4 (request/alert states), §5 copy; PRD V2-FR-010..014, V2-FR-030..033, V2-FR-050; Verification V2-VT-025, V2-VT-030 (contacts goldens)
- Owned_Paths: lib/features/contacts/**, test/features/contacts/**, dossiers/TASK-090.md
- Depends_On: TASK-086

## Work Log

- [2026-09-12T06:12:00Z] [GB] Claimed. Preflight: `lib/features/contacts/**` and `test/features/contacts/**` are NEW territory; dossier exists. Implementing embedded Contacts tab (no app bar, no shell/session): Requests + alphabetical Contacts, Design §3 presence cues, add-contact sheet (scan/paste/show-my-code), incoming-request modal, Alert 10-min UI cooldown, Block second-tap confirm. Nearby/Talking injected as pk sets.
- [2026-09-12T06:45:00Z] [GB] Implementation complete. `ContactsTab` + presentational `ContactsScreen`, add/incoming/actions sheets, `ScanIdScreen` with injectable scanner, `ContactsListController` over TASK-086 store + `DirectoryClient.sendAlert`. Nearby/Talking are injected pk sets (no session). ContactsTab HTTP widget tests omitted: dart:io inside testWidgets fake-async never completes (same FakeDirectoryServer path works in `test()`). Controller + screen tests cover the criteria. Mutation: skipping local ID refuse makes the V2-VT-003 test throw. Full suite: 1760 passed, 2 failed (both `shell_frame_golden_test.dart`, TASK-093 territory, same TASK-092 disclosure), 40 skipped PARKED FR-025. Analyze clean.

