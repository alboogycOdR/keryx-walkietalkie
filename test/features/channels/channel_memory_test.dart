import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/features/channels/channel_memory.dart';

void main() {
  const TunedChannel a = TunedChannel(channel: 7, privacyCode: 3);
  const TunedChannel b = TunedChannel(channel: 1, privacyCode: 0);
  const TunedChannel c = TunedChannel(channel: 12, privacyCode: 38);
  const TunedChannel d = TunedChannel(channel: 2, privacyCode: 1);
  const TunedChannel e = TunedChannel(channel: 3, privacyCode: 2);
  const TunedChannel f = TunedChannel(channel: 4, privacyCode: 4);
  const TunedChannel g = TunedChannel(channel: 5, privacyCode: 5);

  test('preserves newest-first order and drops duplicates (VT-020)', () {
    expect(visibleChannelMemory(<TunedChannel>[a, b, a, c]), <TunedChannel>[a, b, c]);
  });

  test('caps at the existing six-entry memory (Technical §6)', () {
    expect(
      visibleChannelMemory(<TunedChannel>[a, b, c, d, e, f, g]),
      <TunedChannel>[a, b, c, d, e, f],
    );
  });

  test('does not invent entries when memory is empty', () {
    expect(visibleChannelMemory(const <TunedChannel>[]), isEmpty);
  });
}
