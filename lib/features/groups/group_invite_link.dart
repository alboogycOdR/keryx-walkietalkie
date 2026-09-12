/// Group invite deep link encode/decode (Technical §5.2).
///
/// Format: `keryx://join?v=2&g=<groupId>&t=<inviteToken>&s=<base64url(groupSecret)>[&exp=<unix>]`.
/// The secret rides in the link so the server never sees it (Technical
/// §5.2's own trust-model note: "Anyone who has the link has the secret —
/// same trust model as a WhatsApp invite link, rotation is the remedy").
///
/// Independent of the retired v1 numbered Event QR scheme. Expiry presets
/// match Technical §5.2 ("expiry presets reused from `event_link.dart`")
/// and now live here so `lib/features/event_qr/**` can be deleted.
library;

import 'dart:convert';

/// FR-044 expiry presets, kept as the group-invite expiry choices
/// (Technical §5.2). Name preserved so existing group-invite call sites
/// do not churn.
enum EventLinkExpiryPreset {
  fourHours(Duration(hours: 4), 'Session (4 h)'),
  twentyFourHours(Duration(hours: 24), '24 hours'),
  sevenDays(Duration(days: 7), '7 days'),
  noExpiry(null, 'No expiry');

  const EventLinkExpiryPreset(this.duration, this.label);

  /// `null` means "never expires" (the [noExpiry] preset).
  final Duration? duration;

  final String label;

  bool get requiresExplicitConfirmation =>
      this == EventLinkExpiryPreset.noExpiry;

  DateTime? expiresAtFrom(DateTime now) {
    final d = duration;
    return d == null ? null : now.add(d);
  }
}

/// FR-044's stated default: "Default expiry: 24 h".
const defaultEventLinkExpiryPreset = EventLinkExpiryPreset.twentyFourHours;

const groupInviteLinkScheme = 'keryx';
const groupInviteLinkHost = 'join';
const groupInviteLinkVersion = 2;

/// A decoded/encodable group invite payload.
class GroupInviteLink {
  const GroupInviteLink({
    required this.groupId,
    required this.token,
    required this.secret,
    this.expiresAt,
  });

  final String groupId;
  final String token;

  /// The raw (opened) 32-byte group secret.
  final List<int> secret;

  /// Local, client-side expiry hint — a fast pre-check only; the server's
  /// invite-token expiry is authoritative (mirrors
  /// `event_link.dart`'s own `EventLinkDecoded.isExpired` disclosed
  /// decision).
  final DateTime? expiresAt;

  bool isExpired({DateTime? now}) {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return !(now ?? DateTime.now()).isBefore(expiry);
  }
}

/// Result of [decodeGroupInviteLink].
sealed class GroupInviteDecodeResult {
  const GroupInviteDecodeResult();
}

final class GroupInviteDecoded extends GroupInviteDecodeResult {
  const GroupInviteDecoded(this.link);
  final GroupInviteLink link;
}

final class GroupInviteDecodeFailure extends GroupInviteDecodeResult {
  const GroupInviteDecodeFailure(this.reason);
  final String reason;
}

/// Encodes [link] as a `keryx://join?v=2&...` deep link, honouring
/// [preset] for the `exp` param (omitted entirely for
/// [EventLinkExpiryPreset.noExpiry]).
Uri encodeGroupInviteLink(
  GroupInviteLink link, {
  EventLinkExpiryPreset? preset,
}) {
  final params = <String, String>{
    'v': '$groupInviteLinkVersion',
    'g': link.groupId,
    't': link.token,
    's': base64Url.encode(link.secret).replaceAll('=', ''),
  };
  final expiresAt = link.expiresAt;
  if (expiresAt != null) {
    params['exp'] = (expiresAt.millisecondsSinceEpoch ~/ 1000).toString();
  }
  return Uri(
    scheme: groupInviteLinkScheme,
    host: groupInviteLinkHost,
    queryParameters: params,
  );
}

/// Decodes a `keryx://join?v=2&...` deep link (scanned QR or pasted/tapped
/// link). Never throws — malformed input is a typed failure, since a
/// scan/paste is untrusted external input.
GroupInviteDecodeResult decodeGroupInviteLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) {
    return const GroupInviteDecodeFailure('malformed URI');
  }
  if (uri.scheme != groupInviteLinkScheme) {
    return GroupInviteDecodeFailure('unsupported scheme "${uri.scheme}"');
  }
  if (uri.host != groupInviteLinkHost) {
    return GroupInviteDecodeFailure('unsupported action "${uri.host}"');
  }
  final params = uri.queryParameters;
  if (params['v'] != '$groupInviteLinkVersion') {
    return GroupInviteDecodeFailure('unsupported version "${params['v']}"');
  }
  final groupId = params['g'];
  final token = params['t'];
  final secretParam = params['s'];
  if (groupId == null || groupId.isEmpty) {
    return const GroupInviteDecodeFailure('missing group id');
  }
  if (token == null || token.isEmpty) {
    return const GroupInviteDecodeFailure('missing invite token');
  }
  if (secretParam == null || secretParam.isEmpty) {
    return const GroupInviteDecodeFailure('missing secret');
  }
  final List<int> secret;
  try {
    secret = base64Url.decode(_padBase64Url(secretParam));
  } on FormatException {
    return const GroupInviteDecodeFailure('malformed secret');
  }
  if (secret.length != 32) {
    return const GroupInviteDecodeFailure('secret is not 32 bytes');
  }

  DateTime? expiresAt;
  final expRaw = params['exp'];
  if (expRaw != null) {
    final expSeconds = int.tryParse(expRaw);
    if (expSeconds == null) {
      return const GroupInviteDecodeFailure('malformed exp');
    }
    expiresAt = DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000, isUtc: true);
  }

  return GroupInviteDecoded(
    GroupInviteLink(groupId: groupId, token: token, secret: secret, expiresAt: expiresAt),
  );
}

String _padBase64Url(String value) {
  final remainder = value.length % 4;
  if (remainder == 0) return value;
  return value + ('=' * (4 - remainder));
}
