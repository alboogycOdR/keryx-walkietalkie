/// `keryx://join?...` deep-link encode/decode (FR-043, FR-044, KRX-054).
///
/// A link/QR carries **the room identifier**, never a raw keyed-channel
/// passphrase — TASK-007's own contract ("the passphrase never leaves this
/// function") already forbids that, and it would be pointless besides: the
/// scanning device needs a `roomId` to join, not the means to re-derive one
/// itself. For a numbered channel the roomId is re-derived locally on scan
/// (cheap HMAC, deterministic, no isolate offload needed — mirrors
/// `LinkedController.joinNumbered`'s own comment on this). For a keyed
/// channel the *exporting* device must already have called [deriveKeyed]
/// (TASK-007's ~1-3s synchronous scrypt stretch) to reach the currently
/// tuned room in the first place; [buildKeyedEventLink] is the sanctioned
/// way to redo that derivation from a fresh passphrase input (e.g. an
/// export flow that doesn't have live radio state to hand) and it runs
/// that derivation off the UI isolate via `compute()`, exactly like
/// `LinkedController.joinKeyed` does — this file's own MANDATORY
/// acceptance criterion (TASK-007 follow-up (dd)).
library;

import 'package:flutter/foundation.dart' show compute;
import 'package:keryx/core/rooms/rooms.dart';

/// URI scheme for Event QR / deep links.
const eventLinkScheme = 'keryx';

/// URI host component naming the join action (`keryx://join?...`).
const eventLinkHost = 'join';

/// Deep-link payload version. Bump and branch on parse when the wire
/// format changes; this file only ever emits/accepts `1`.
const eventLinkVersion = 1;

/// FR-044 expiry presets. `twentyFourHours` is the spec default; `noExpiry`
/// is the one preset that "requir[es] an explicit extra tap" before it can
/// take effect — see `EventQrExportScreen`'s two-step confirmation.
enum EventLinkExpiryPreset {
  fourHours(Duration(hours: 4), 'Session (4 h)'),
  twentyFourHours(Duration(hours: 24), '24 hours'),
  sevenDays(Duration(days: 7), '7 days'),
  noExpiry(null, 'No expiry');

  const EventLinkExpiryPreset(this.duration, this.label);

  /// `null` means "never expires" (the [noExpiry] preset).
  final Duration? duration;

  final String label;

  /// FR-044: "no expiry — the last requiring an explicit extra tap".
  bool get requiresExplicitConfirmation => this == EventLinkExpiryPreset.noExpiry;

  /// Resolves this preset to an absolute expiry instant relative to [now],
  /// or `null` for [noExpiry].
  DateTime? expiresAtFrom(DateTime now) {
    final d = duration;
    return d == null ? null : now.add(d);
  }
}

/// FR-044's stated default: "Default expiry: 24 h".
const defaultEventLinkExpiryPreset = EventLinkExpiryPreset.twentyFourHours;

/// A decoded/encodable Event QR payload: "region, channel, code (or
/// keyed-channel token), and expiry" per FR-044.
sealed class EventLinkPayload {
  const EventLinkPayload({this.expiresAt});

  /// `null` means no expiry (the explicit-tap preset was chosen/decoded).
  final DateTime? expiresAt;

  /// The TS §8.7 roomId this payload resolves to.
  String get roomId;
}

/// A numbered-channel Event QR: region + channel + privacy code, resolved
/// to a roomId via [deriveNumbered] (cheap, deterministic — safe to call on
/// every [roomId] read, including on the scanning device).
final class NumberedEventLink extends EventLinkPayload {
  const NumberedEventLink({
    required this.region,
    required this.channel,
    required this.code,
    super.expiresAt,
  });

  final String region;
  final int channel;
  final int code;

  @override
  String get roomId => deriveNumbered(region: region, channel: channel, code: code);
}

/// A keyed-channel Event QR. Carries the already-derived roomId, never the
/// passphrase (see this library's top-level dartdoc).
final class KeyedEventLink extends EventLinkPayload {
  const KeyedEventLink({required String roomId, super.expiresAt}) : _roomId = roomId;

  final String _roomId;

  @override
  String get roomId => _roomId;
}

/// Result of [decodeEventLink].
sealed class EventLinkDecodeResult {
  const EventLinkDecodeResult();
}

/// A successfully parsed, structurally valid payload. [isExpired] is a
/// client-side convenience check only — the token service is the
/// authoritative enforcer (see `token-svc/README.md`'s Event-QR token
/// contract); this flag exists so a scan of an expired code can surface an
/// immediate in-world flag/tone rather than round-tripping to the server
/// first.
final class EventLinkDecoded extends EventLinkDecodeResult {
  const EventLinkDecoded({required this.payload, required this.isExpired});
  final EventLinkPayload payload;
  final bool isExpired;
}

/// Malformed, wrong-scheme, wrong-version, or out-of-domain input. [reason]
/// is a short, non-user-facing diagnostic (log/debug use); the host decides
/// how (or whether) to surface a failed scan.
final class EventLinkDecodeFailure extends EventLinkDecodeResult {
  const EventLinkDecodeFailure(this.reason);
  final String reason;
}

/// Encodes [payload] as a `keryx://join?...` deep link.
///
/// Format: `keryx://join?v=1&r=<region>&ch=<2-digit>&pc=<2-digit>&exp=<unix>`
/// (numbered) or `keryx://join?v=1&k=<roomId>&exp=<unix>` (keyed). `exp` is
/// omitted entirely for no-expiry.
Uri encodeEventLink(EventLinkPayload payload) {
  final params = <String, String>{'v': '$eventLinkVersion'};
  switch (payload) {
    case NumberedEventLink(:final region, :final channel, :final code):
      params['r'] = region;
      params['ch'] = _twoDigits(channel);
      params['pc'] = _twoDigits(code);
    case KeyedEventLink(:final roomId):
      params['k'] = roomId;
  }
  final expiresAt = payload.expiresAt;
  if (expiresAt != null) {
    params['exp'] = (expiresAt.millisecondsSinceEpoch ~/ 1000).toString();
  }
  return Uri(scheme: eventLinkScheme, host: eventLinkHost, queryParameters: params);
}

/// Decodes a `keryx://join?...` deep link (from a scanned QR or a tapped
/// Android intent URI). Never throws — malformed/out-of-domain input
/// returns [EventLinkDecodeFailure] instead, since a scan is untrusted
/// external input.
///
/// [now] is an injection seam for deterministic expiry tests; production
/// callers should leave it `null` (defaults to `DateTime.now()`).
EventLinkDecodeResult decodeEventLink(String raw, {DateTime? now}) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) {
    return const EventLinkDecodeFailure('malformed URI');
  }
  if (uri.scheme != eventLinkScheme) {
    return EventLinkDecodeFailure('unsupported scheme "${uri.scheme}"');
  }
  if (uri.host != eventLinkHost) {
    return EventLinkDecodeFailure('unsupported action "${uri.host}"');
  }

  final params = uri.queryParameters;
  if (params['v'] != '$eventLinkVersion') {
    return EventLinkDecodeFailure('unsupported version "${params['v']}"');
  }

  DateTime? expiresAt;
  final expRaw = params['exp'];
  if (expRaw != null) {
    final expSeconds = int.tryParse(expRaw);
    if (expSeconds == null) {
      return const EventLinkDecodeFailure('malformed exp');
    }
    expiresAt = DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000, isUtc: true);
  }

  final EventLinkPayload payload;
  final keyedToken = params['k'];
  if (keyedToken != null) {
    if (!isRoomId(keyedToken)) {
      return const EventLinkDecodeFailure('malformed keyed-channel token');
    }
    payload = KeyedEventLink(roomId: keyedToken, expiresAt: expiresAt);
  } else {
    final region = params['r'];
    final channel = int.tryParse(params['ch'] ?? '');
    final code = int.tryParse(params['pc'] ?? '');
    if (region == null || region.isEmpty || channel == null || code == null) {
      return const EventLinkDecodeFailure('missing region/channel/code');
    }
    if (channel < minChannel || channel > maxChannel) {
      return const EventLinkDecodeFailure('channel out of range');
    }
    if (code < minPrivacyCode || code > maxPrivacyCode) {
      return const EventLinkDecodeFailure('privacy code out of range');
    }
    payload = NumberedEventLink(region: region, channel: channel, code: code, expiresAt: expiresAt);
  }

  final effectiveNow = now ?? DateTime.now();
  final isExpired = expiresAt != null && !effectiveNow.isBefore(expiresAt);
  return EventLinkDecoded(payload: payload, isExpired: isExpired);
}

/// Top-level (required by `compute()` — a closure will not marshal) so
/// [buildKeyedEventLink] can run [deriveKeyed]'s scrypt stretch off the UI
/// isolate. Mirrors `LinkedController._deriveKeyedOffUiIsolate` exactly.
String _deriveKeyedRoomIdOffUiIsolate(String passphrase) => deriveKeyed(passphrase: passphrase);

/// Derives a [KeyedEventLink] for [passphrase], running the scrypt stretch
/// off the UI isolate via `compute()` — MANDATORY per this task's own
/// acceptance criterion (TASK-007 follow-up (dd)): `deriveKeyed` is ~1-3s
/// of **synchronous** pure-Dart work, so an inline call would starve the
/// event loop for that entire window.
Future<KeyedEventLink> buildKeyedEventLink({
  required String passphrase,
  DateTime? expiresAt,
}) async {
  final roomId = await compute(_deriveKeyedRoomIdOffUiIsolate, passphrase);
  return KeyedEventLink(roomId: roomId, expiresAt: expiresAt);
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');
