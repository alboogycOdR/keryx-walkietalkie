/// Centralised strings for the Radio Controls screen (Design §2.5) — same
/// `abstract final class` copy-constant convention as
/// `ChannelSelectorCopy`/`StationsCopy`, kept here so wording is
/// consistent and independently testable rather than inlined at each
/// call site.
abstract final class RadioControlsCopy {
  static const String title = 'Radio Controls';

  static const String monitorLabel = 'Monitor';
  static const String monitorDescription =
      'Hold to open the squelch and listen without transmitting.';

  /// Text-equivalent of the monitor indicator's colour so the open/closed
  /// state is never colour-only (Design §5; UX-FR-022).
  static const String monitorOpenState = 'Open';
  static const String monitorClosedState = 'Closed';
  static const String monitorHoldTargetHint =
      'Press and hold to open the squelch; release to close it.';

  static const String scanLabel = 'Scan';
  static const String scanDescription = 'Scan the channel for activity.';

  /// Text-equivalent of the scan indicator's colour (Design §5; UX-FR-022).
  static const String scanningState = 'Scanning';
  static const String scanIdleState = 'Idle';

  static const String emergencyLabel = 'Emergency';
  static const String emergencyHoldTargetHint =
      'Press and hold to arm; release early to cancel.';

  /// Verification §8: no automatic location transmission, no
  /// emergency-service claim.
  static const String emergencyDescription =
      'Hold to alert other stations on this channel. No emergency services '
      'are contacted and no location is transmitted automatically.';

  static const String emergencyArmingHint = 'Keep holding to confirm…';
  static const String emergencyActiveBanner = 'EMERGENCY ACTIVE';
  static const String emergencyClearAction = 'Clear emergency';

  /// Shown when emergency is pinned by a different station — clear is
  /// owner-only, matching `FloorEngine.clearEmergency`'s existing rule.
  static const String emergencyClearedByOwnerOnly =
      'Only the station that raised this emergency can clear it.';

  static const String controlUnavailableNoRadio =
      'Radio is not ready — control unavailable.';
  static const String controlUnavailableBusy =
      'Unavailable while transmitting or tuning.';
  static const String controlUnavailableNoEngine =
      'Emergency control unavailable — no active session.';
}
