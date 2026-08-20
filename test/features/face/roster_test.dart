import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/face/roster.dart';

void main() {
  group('aggregateSignalQuality', () {
    test('returns null when the roster is empty', () {
      expect(
        aggregateSignalQuality(stations: const [], activeSpeakerPeerId: null),
        isNull,
      );
    });

    test(
      'while a station transmits, returns THAT station\'s quality (FR-069)',
      () {
        const stations = [
          StationInfo(peerId: 'a', callsign: 'ALPHA-1', signalQuality: 9),
          StationInfo(peerId: 'b', callsign: 'BRAVO-2', signalQuality: 3),
          StationInfo(peerId: 'c', callsign: 'CHARLIE-3', signalQuality: 6),
        ];
        expect(
          aggregateSignalQuality(
            stations: stations,
            activeSpeakerPeerId: 'b',
          ),
          3,
        );
      },
    );

    test('at idle (no active speaker), returns the WORST peer link', () {
      const stations = [
        StationInfo(peerId: 'a', callsign: 'ALPHA-1', signalQuality: 9),
        StationInfo(peerId: 'b', callsign: 'BRAVO-2', signalQuality: 3),
        StationInfo(peerId: 'c', callsign: 'CHARLIE-3', signalQuality: 6),
      ];
      expect(
        aggregateSignalQuality(stations: stations, activeSpeakerPeerId: null),
        3,
      );
    });

    test(
      'falls back to worst-peer when the active speaker is not in the roster',
      () {
        const stations = [
          StationInfo(peerId: 'a', callsign: 'ALPHA-1', signalQuality: 9),
          StationInfo(peerId: 'b', callsign: 'BRAVO-2', signalQuality: 4),
        ];
        expect(
          aggregateSignalQuality(
            stations: stations,
            activeSpeakerPeerId: 'ghost',
          ),
          4,
        );
      },
    );

    test('single-station roster: talking and idle agree', () {
      const stations = [
        StationInfo(peerId: 'a', callsign: 'ALPHA-1', signalQuality: 7),
      ];
      expect(
        aggregateSignalQuality(stations: stations, activeSpeakerPeerId: 'a'),
        7,
      );
      expect(
        aggregateSignalQuality(stations: stations, activeSpeakerPeerId: null),
        7,
      );
    });
  });

  group('StationInfo', () {
    test('value equality', () {
      const a = StationInfo(peerId: 'x', callsign: 'X-1', signalQuality: 5);
      const b = StationInfo(peerId: 'x', callsign: 'X-1', signalQuality: 5);
      const c = StationInfo(peerId: 'x', callsign: 'X-1', signalQuality: 6);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('rejects out-of-domain signal quality', () {
      expect(
        () => StationInfo(peerId: 'x', callsign: 'X-1', signalQuality: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => StationInfo(peerId: 'x', callsign: 'X-1', signalQuality: 10),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
