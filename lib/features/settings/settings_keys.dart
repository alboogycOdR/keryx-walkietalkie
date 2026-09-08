import 'package:flutter/foundation.dart';

/// Keys for widget tests (Design §2.6 sections and VT-003/005/022).
abstract final class SettingsKeys {
  static const Key title = Key('settings.title');
  static const Key loadFailed = Key('settings.load-failed');
  static const Key deferredBanner = Key('settings.deferred-banner');
  static const Key deferredCancel = Key('settings.deferred-cancel');

  static const Key radioSection = Key('settings.section.radio');
  static const Key audioSection = Key('settings.section.audio');
  static const Key connectivitySection = Key('settings.section.connectivity');
  static const Key identitySection = Key('settings.section.identity');
  static const Key appearanceSection = Key('settings.section.appearance');
  static const Key aboutSection = Key('settings.section.about');

  static const Key tot = Key('settings.tot');
  static const Key latch = Key('settings.latch');
  static const Key lockout = Key('settings.lockout');
  static const Key region = Key('settings.region');
  static const Key squelch = Key('settings.squelch');
  static const Key roger = Key('settings.roger');
  static const Key dsp = Key('settings.dsp');
  static const Key audioRouting = Key('settings.audio-routing');
  static const Key mode = Key('settings.mode');
  static const Key effectiveRoute = Key('settings.effective-route');
  static const Key forceLocal = Key('settings.force-local');
  static const Key forceLocalNote = Key('settings.force-local-note');
  static const Key relayUrl = Key('settings.relay-url');
  static const Key tokenUrl = Key('settings.token-url');
  static const Key callsign = Key('settings.callsign');
  static const Key theme = Key('settings.theme');
  static const Key dim = Key('settings.dim');
  static const Key version = Key('settings.version');
  static const Key diagnostics = Key('settings.diagnostics');
  static const Key technicalDetails = Key('settings.technical-details');
  static const Key reconnectBadge = Key('settings.reconnect-badge');

  static const Key confirmDialog = Key('settings.confirm-dialog');
  static const Key confirmApply = Key('settings.confirm-apply');
  static const Key confirmCancel = Key('settings.confirm-cancel');
}
