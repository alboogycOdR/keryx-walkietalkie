import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/discovery/discovery.dart';

void main() {
  test('prefix is 8 lowercase hex chars and stable', () {
    final a = ChannelHashPrefix.compute(
      region: 'ZA',
      channel: '07',
      code: '12',
    );
    final b = ChannelHashPrefix.compute(
      region: 'ZA',
      channel: '07',
      code: '12',
    );
    expect(a, hasLength(DiscoveryConstants.channelHashPrefixLength));
    expect(a, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(a, b);
    // Frozen so a later rooms-lib swap can be compared, not silently drifted.
    expect(a, '899593ba');
  });

  test('region, channel and code all participate', () {
    final base = ChannelHashPrefix.compute(
      region: 'ZA',
      channel: '07',
      code: '12',
    );
    expect(
      ChannelHashPrefix.compute(region: 'NA', channel: '07', code: '12'),
      isNot(base),
    );
    expect(
      ChannelHashPrefix.compute(region: 'ZA', channel: '08', code: '12'),
      isNot(base),
    );
    expect(
      ChannelHashPrefix.compute(region: 'ZA', channel: '07', code: '00'),
      isNot(base),
    );
  });

  test('rejects empty region or channel', () {
    expect(
      () => ChannelHashPrefix.compute(region: '', channel: '01', code: '00'),
      throwsArgumentError,
    );
    expect(
      () => ChannelHashPrefix.compute(region: 'ZA', channel: '', code: '00'),
      throwsArgumentError,
    );
  });
}
