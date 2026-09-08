import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/stations/stations.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

void main() {
  test('known callsign is returned as-is (UX-FR-026)', () {
    const StationInfo station = StationInfo(
      peerId: 'abcdefghij',
      callsign: 'ALPHA-1',
    );
    expect(stationDisplayName(station), 'ALPHA-1');
  });

  test('empty callsign uses the neutral fallback', () {
    const StationInfo station = StationInfo(
      peerId: 'abcdefghij',
      callsign: '  ',
    );
    expect(stationDisplayName(station), StationsCopy.unknownStation);
    expect(stationDisplayName(station), isNot('abcdefghij'));
  });

  test('callsign equal to peerId is not presented as a name (UX-FR-026)', () {
    const StationInfo station = StationInfo(
      peerId: 'abcdefghij',
      callsign: 'abcdefghij',
    );
    expect(stationDisplayName(station), StationsCopy.unknownStation);
    expect(stationDisplayName(station), isNot(station.peerId));
  });

  test('a peer-ID-shaped callsign is not presented as a name (UX-FR-026)', () {
    const StationInfo station = StationInfo(
      peerId: 'abcdefghij',
      callsign: 'klmnopqrst',
    );
    expect(stationDisplayName(station), StationsCopy.unknownStation);
    expect(stationDisplayName(station).contains('klmnopqrst'), isFalse);
    expect(stationDisplayName(station).contains('abcdefghij'), isFalse);
  });

  test('non-callsign junk falls back; peerId is never the result', () {
    const StationInfo station = StationInfo(
      peerId: 'abcdefghij',
      callsign: 'not a name!!!',
    );
    expect(stationDisplayName(station), StationsCopy.unknownStation);
    expect(stationDisplayName(station), isNot(station.peerId));
  });
}
