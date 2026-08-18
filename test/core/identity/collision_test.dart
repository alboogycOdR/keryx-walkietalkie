import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

void main() {
  test('first keeper of a name is unsuffixed; later joiners get (2), (3)', () {
    final names = displayNames([
      (peerId: 'aaaaaaaaaa', callsign: 'BRAVO-7'),
      (peerId: 'bbbbbbbbbb', callsign: 'SIERRA-19'),
      (peerId: 'cccccccccc', callsign: 'BRAVO-7'),
      (peerId: 'dddddddddd', callsign: 'BRAVO-7'),
    ]);
    expect(names, {
      'aaaaaaaaaa': 'BRAVO-7',
      'bbbbbbbbbb': 'SIERRA-19',
      'cccccccccc': 'BRAVO-7 (2)',
      'dddddddddd': 'BRAVO-7 (3)',
    });
  });

  test('suffixing follows join order, not peerId sort order', () {
    final names = displayNames([
      (peerId: 'zzzzzzzzzz', callsign: 'MIKE-1'),
      (peerId: 'aaaaaaaaaa', callsign: 'MIKE-1'),
    ]);
    expect(names['zzzzzzzzzz'], 'MIKE-1');
    expect(names['aaaaaaaaaa'], 'MIKE-1 (2)');
  });

  test('distinct callsigns never suffix each other', () {
    final names = displayNames([
      (peerId: 'aaaaaaaaaa', callsign: 'ALPHA-1'),
      (peerId: 'bbbbbbbbbb', callsign: 'ALPHA-2'),
    ]);
    expect(names.values, ['ALPHA-1', 'ALPHA-2']);
  });

  test('does not enforce uniqueness — two identical names both render', () {
    final names = displayNames([
      (peerId: 'aaaaaaaaaa', callsign: 'KILO-3'),
      (peerId: 'bbbbbbbbbb', callsign: 'KILO-3'),
    ]);
    expect(names.length, 2);
    expect(names.values.toSet(), {'KILO-3', 'KILO-3 (2)'});
  });

  test('peerIds in the output are unchanged from the input', () {
    const peers = <ChannelPeer>[
      (peerId: 'wvuni74syc', callsign: 'BRAVO-7'),
      (peerId: 'z3ucgb7gvv', callsign: 'BRAVO-7'),
    ];
    expect(displayNames(peers).keys, peers.map((p) => p.peerId));
  });

  test('duplicate peerId is rejected (they never collide)', () {
    expect(
      () => displayNames([
        (peerId: 'aaaaaaaaaa', callsign: 'A-1'),
        (peerId: 'aaaaaaaaaa', callsign: 'B-2'),
      ]),
      throwsArgumentError,
    );
  });

  test('empty join list is empty', () {
    expect(displayNames(const []), isEmpty);
  });
}
