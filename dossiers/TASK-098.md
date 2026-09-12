# TASK-098 — Scan contact-request failures + local-only honesty

## Brief

QR-scan add-contact silently swallowed `sendRequest` failures (screen
popped before the request finished; callback was `unawaited`). Paste
already handled this. Settings' "This network only" copy did not name
contacts/presence as blocked.

## Spec pointers

- Owner field reports 2026-09-12 (PLAN.md TASK-098)
- Paste-path precedent: `contacts_tab.dart` `_onPaste`
- Settings copy conventions: `settings_copy.dart` (sentence case)

## Approach

1. `ScanIdScreen.onRaw` is `Future<String?> Function(String)` — pop only
   on `null`; stay and show the error otherwise. Catch throws as
   `ContactsCopy.requestFailed`.
2. `ContactsTab._openScan` reuses `_onPaste` (same try/catch).
3. `add_contact_sheet.dart` / `_onPaste` untouched.
4. `SettingsCopy.forceLocalBlocksWan` names contacts and presence.
5. Dismissable `LocalOnlyContactsNotice` on Contacts list + Scan when
   `forceLocalOnly` is on. `ContactsTab` reads `settingsProvider` (or a
   test override); does not write settings.

## Work Log

- [2026-09-12T13:52:19Z] [GB] Claimed. Preflight: contacts/** existing,
  settings_screen + settings_copy existing, dossier NEW. `add_contact_sheet.dart`
  in-territory but out of scope.
- [2026-09-12T14:05:00Z] [GB] Implementation in progress: scan await/catch,
  Settings copy, local-only notice, widget tests.
- [2026-09-12T14:31:10Z] [GB] Ready for review. Scan path awaits `_onPaste`
  (same try/catch). `forceLocalBlocksWan` names contacts/presence. Dismissable
  `LocalOnlyContactsNotice` on Contacts + Scan. `add_contact_sheet.dart`
  unmodified. Revert-mutation: popping before await failed both new scan
  tests; restored. `flutter analyze --no-pub` clean. Scoped
  `flutter test --no-pub test/features/contacts test/features/settings`
  **80/80**. Full parallel suite had 3 out-of-territory flakes
  (groups new_group/invite, mesh rx_gate) that pass in isolation;
  `--concurrency=1` OOM'd this machine.
