/// User-facing copy for the Contacts tab (Design §2.2, §2.5, §4, §5 —
/// plain language, sentence case; never "channel/tune/station/LOCAL/
/// LINKED/AUTO").
library;

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
  static const alertSent = 'Alert sent';
  static const alertCooldown = 'Alert is available again in 10 minutes';

  static const nearbyLabel = 'Nearby';
  static const talkingLabel = 'Talking';
  static const availableLabel = 'Available';
  static const busyLabel = 'Busy';
  static const dndLabel = 'Do Not Disturb';
  static const offlineLabel = 'Offline';
}
