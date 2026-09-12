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
- Scan waits for `sendRequestFromId` (same try/catch as paste) and stays
  open with `Couldn't send that request.` on failure; it does not pop on
  parse alone.
- When Settings → This network only is on, a dismissable notice on the
  Contacts list and Scan screen says contacts and presence need the relay.
- Nearby / Talking are injected `Set<String>`s — this territory has no
  session dependency.
