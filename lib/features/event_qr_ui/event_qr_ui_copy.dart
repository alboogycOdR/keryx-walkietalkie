/// User-facing copy for the Event QR successor screens (Design §2.7).
///
/// Kept as a standalone `abstract final class` of `static const String`
/// (same convention as `RadioControlsCopy`, TASK-054) so tests can assert
/// against exact strings without importing the widget tree.
abstract final class EventQrUiCopy {
  // --- Scan screen: titles ------------------------------------------------

  static const String scanTitle = 'Scan event code';

  // --- Camera permission states (Design §2.7: "appropriate camera/
  // permission states") ----------------------------------------------------

  static const String permissionDeniedTitle = 'Camera access needed';
  static const String permissionDeniedBody =
      'KERYX needs camera access to scan an event code. Grant access to '
      'continue.';
  static const String permissionDeniedAction = 'Grant access';

  static const String permissionPermanentlyDeniedTitle = 'Camera access blocked';
  static const String permissionPermanentlyDeniedBody =
      'Camera access was previously denied. Open Settings to allow KERYX '
      'to use the camera.';
  static const String permissionPermanentlyDeniedAction = 'Open Settings';

  static const String permissionUnavailableTitle = 'Camera unavailable';
  static const String permissionUnavailableBody =
      'No usable camera was found on this device. Scanning an event code '
      'is not possible here.';

  // --- Scan outcomes --------------------------------------------------

  static const String scanExpired = 'This event code has expired.';
  static const String scanInvalid = 'That code is not a valid event code.';

  // --- Route transition (Technical §8, Design §2.7) -----------------------

  static const String routeTransitionTitle = 'Switch to linked connection?';
  static const String routeTransitionBody =
      'This event needs a linked connection. Joining will switch KERYX '
      'from local-only to linked mode, which reconnects the radio.';
  static const String routeTransitionConfirm = 'Switch and join';
  static const String routeTransitionCancel = 'Cancel';

  static const String forceLocalBlocked =
      'Local-only mode is on, so this event (which needs a linked '
      'connection) is unavailable. Turn off local-only in Settings to '
      'join it.';

  static const String joinCancelled = 'Join cancelled.';
  static const String joinFailed =
      'Could not join this event. The previous connection was kept.';
  static const String settingsUnavailable =
      'Settings are still loading — try scanning again in a moment.';

  // --- Export screen -------------------------------------------------

  static const String exportTitle = 'Share event code';
  static const String exportSettingsUnavailable =
      'Settings are still loading — export is unavailable right now.';
  static const String keyedExportUnavailableTitle = 'Keyed export unavailable';
  static const String keyedExportUnavailableBody =
      'Exporting a keyed (passphrase-protected) channel as an event code '
      'is not available yet. Share the passphrase directly instead.';
}
