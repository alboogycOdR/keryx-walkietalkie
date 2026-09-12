# Contacts (v2 tab)

Embedded Contacts tab body for TASK-093 to mount. No app bar of its own.

- `ContactsTab` listens to `ContactsListController` (which wraps TASK-086's
  `ContactsController` + `DirectoryClient.sendAlert`).
- Sections: incoming **Requests** (Accept / Decline / Block) then
  alphabetical **Contacts** with Design §3 presence cues.
- Row tap → `onSelectTarget`; long-press → Alert / Remove / Block.
- Alert is disabled in the UI for 10 minutes after use (V2-FR-050).
- Block requires a second tap (Design §2.5).
- Add contact sheet: scan (`mobile_scanner`, injectable for tests), show
  my code (callback), paste an ID. Tampered QRs are refused locally
  (`KeryxIdLink.parse`) before any network call.
- Nearby / Talking are injected `Set<String>`s — this territory has no
  session dependency.
