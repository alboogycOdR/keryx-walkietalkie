import 'package:keryx/core/settings/settings_repository.dart'
    show SettingsMemoryCap, TunedChannel;

/// Renders the existing six-entry recall truthfully: first-seen order
/// preserved, duplicates dropped, hard-capped at the stored capacity
/// (Technical §6; UX-FR-004; VT-020). Does not invent entries or rewrite
/// channel/code identity (UX-FR-010).
List<TunedChannel> visibleChannelMemory(List<TunedChannel> source) {
  final Set<TunedChannel> seen = <TunedChannel>{};
  final List<TunedChannel> out = <TunedChannel>[];
  for (final TunedChannel entry in source) {
    if (!seen.add(entry)) {
      continue;
    }
    out.add(entry);
    if (out.length >= SettingsMemoryCap.channelMemoryCapacity) {
      break;
    }
  }
  return List<TunedChannel>.unmodifiable(out);
}
