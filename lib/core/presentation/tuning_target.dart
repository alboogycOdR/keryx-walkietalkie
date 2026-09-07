/// A tune request in flight — the "requested target separate from the
/// authoritative current channel while tuning" Technical §6 requires: "Keep
/// a requested target separate from the authoritative current channel
/// while tuning; do not optimistically claim connection to a new channel."
///
/// Present only while a [RadioHost.tune] call has been submitted and not
/// yet resolved; `null` on [RadioViewState] means no tune is pending and
/// the current channel/code fields are fully authoritative.
class TuningTarget {
  const TuningTarget({required this.channel, required this.privacyCode})
    : assert(channel >= 1 && channel <= 99),
      assert(privacyCode >= 0 && privacyCode <= 38);

  final int channel;
  final int privacyCode;

  @override
  bool operator ==(Object other) =>
      other is TuningTarget &&
      other.channel == channel &&
      other.privacyCode == privacyCode;

  @override
  int get hashCode => Object.hash(channel, privacyCode);

  @override
  String toString() => 'TuningTarget(ch: $channel, code: $privacyCode)';
}
