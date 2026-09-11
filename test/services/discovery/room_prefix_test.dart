import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/rooms/rooms.dart';
import 'package:keryx/services/discovery/discovery.dart';

void main() {
  test('prefix is the first 8 characters of the room ID', () {
    final roomId = deriveKeyed(passphrase: 'correct horse battery staple');
    expect(RoomPrefix.compute(roomId), roomId.substring(0, 8));
    expect(RoomPrefix.compute(roomId), hasLength(8));
  });

  test('stable for the same room id', () {
    final roomId = deriveGroupRoom(List<int>.generate(32, (i) => i));
    expect(RoomPrefix.compute(roomId), RoomPrefix.compute(roomId));
  });

  test('different room ids yield different prefixes', () {
    final a = deriveGroupRoom(List<int>.generate(32, (i) => i));
    final b = deriveGroupRoom(List<int>.generate(32, (i) => i + 1));
    expect(RoomPrefix.compute(a), isNot(RoomPrefix.compute(b)));
  });

  test('rejects an empty or too-short room id', () {
    expect(() => RoomPrefix.compute(''), throwsArgumentError);
    expect(() => RoomPrefix.compute('SHORT'), throwsArgumentError);
  });
}
