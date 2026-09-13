/// User-facing copy for the Contacts tab (Design §2.2, §2.5, §4, §5 —
/// plain language, sentence case; never "channel/tune/station/LOCAL/
/// LINKED/AUTO").
library;

import 'package:keryx/services/directory/directory.dart'
    show DirectoryErrorCode, DirectoryException;

abstract final class ContactsCopy {
  static const emptyStateTitle = 'No contacts yet';
  static const emptyStateBody = 'Scan a code, show yours, or paste an ID.';
  static const addContactAction = 'Add contact';
  static const scanACode = 'Scan a code';
  static const showMyCode = 'Show my code';
  static const pasteAnId = 'Paste an ID';
  static const pasteHint = 'keryx://id?… or https://keryx.app/c/…';
  static const sendRequestAction = 'Send request';
  static const requestsSection = 'Requests';
  static const contactsSection = 'Contacts';
  static const acceptAction = 'Accept';
  static const declineAction = 'Decline';
  static const blockAction = 'Block';
  static const blockConfirmAction = 'Tap again to block';
  static const alertAction = 'Alert';
  static const removeAction = 'Remove';
  static const stopScanning = 'Stop scanning';

  /// Design §2.5 incoming-request prompt. [displayId] is `CALLSIGN·CODE`.
  static String addRequestPrompt(String displayId) => 'Add $displayId?';

  /// Design §4 outgoing pending row.
  static String waitingToAccept(String callsign) => 'Waiting for $callsign to accept';

  static const invalidId = "That isn't a valid KERYX ID.";
  static const tamperedId = 'That code is damaged or has been tampered with.';
  static const requestFailed = "Couldn't send that request.";

  /// The directory's own reason for refusing a contact request, in the
  /// user's terms (Design §5: persistent, actionable, never colour-only).
  /// One line per `token-svc` code (`directory.py:send_request`); a
  /// transport failure or an unrecognised code falls back to
  /// [requestFailed], with the raw code appended for the latter so a field
  /// report can name it — the relay path already surfaces its codes this
  /// way, and a generic sentence here cost a day of misdiagnosis.
  static String requestRefused(DirectoryException error) {
    if (error.isTransportFailure) return requestFailed;
    return switch (error.code) {
      DirectoryErrorCode.notFound =>
        "They haven't registered with the relay yet — they need the app "
            'open with the Relay URL set, then try again.',
      DirectoryErrorCode.unknownIdentity =>
        "This phone isn't registered with the relay yet — check the Relay "
            'URL in Settings, then reopen the app.',
      DirectoryErrorCode.selfRequest => "That's your own KERYX ID.",
      DirectoryErrorCode.alreadyContacts => "You're already contacts.",
      DirectoryErrorCode.alreadyPending =>
        'Request already sent — waiting for them to accept.',
      DirectoryErrorCode.tooManyOutstanding =>
        'Too many requests waiting — wait for some to be answered first.',
      DirectoryErrorCode.blocked => requestFailed,
      _ => '$requestFailed (${error.rawCode ?? error.code.name})',
    };
  }

  /// Shown on Contacts and Scan while Settings → This network only is on.
  static const localOnlyWarning =
      'This network only is on. Adding contacts and seeing presence needs the '
      'relay, so they will not work until you turn it off in Settings.';
  static const alertSent = 'Alert sent';
  static const alertCooldown = 'Alert is available again in 10 minutes';

  static const nearbyLabel = 'Nearby';
  static const talkingLabel = 'Talking';
  static const availableLabel = 'Available';
  static const busyLabel = 'Busy';
  static const dndLabel = 'Do Not Disturb';
  static const offlineLabel = 'Offline';
}
