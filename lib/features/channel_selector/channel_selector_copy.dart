/// Copy constants for the channel selector (Design §2.3/§5). Kept in one
/// place so wording has exactly one source, the same convention every
/// other Wave 4 feature in this plan follows.
abstract final class ChannelSelectorCopy {
  static const String title = 'Select channel';
  static const String directEntrySectionTitle = 'Direct entry';
  static const String channelFieldLabel = 'Channel (1–99)';
  static const String codeFieldLabel = 'Code (0–38)';
  static const String recentSectionTitle = 'Recent';
  static const String emptyRecent = 'No recent channels yet.';
  static const String apply = 'Apply';
  static const String cancel = 'Cancel';
  static const String retry = 'Retry';
  static const String tuningInProgress = 'Tuning…';
  static const String tuneQueuedDuringTx =
      'Transmission in progress — this tune will apply once it ends.';
  static const String tuneFailed =
      'Could not complete the retune. The active channel may be unchanged.';
  static const String tuneInvalid = 'That channel or code is not valid.';
  static const String tuneCancelled = 'Retune cancelled.';
  static const String currentChannelLabel = 'Current channel';
}
