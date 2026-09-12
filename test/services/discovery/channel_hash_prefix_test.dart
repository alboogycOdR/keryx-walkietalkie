import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/discovery/room_prefix.dart';

void main() {
  test('RoomPrefix is the first 8 characters of a room id', () {
    const roomId = 'M5MFIUI6TXTBOHBD';
    expect(RoomPrefix.compute(roomId), 'M5MFIUI6');
  });

  test('same room id is stable', () {
    const roomId = 'AUAW6KEXHGJU4XZB';
    expect(RoomPrefix.compute(roomId), RoomPrefix.compute(roomId));
  });

  test('empty or short room ids are rejected', () {
    expect(() => RoomPrefix.compute(''), throwsArgumentError);
    expect(() => RoomPrefix.compute('ABC'), throwsArgumentError);
  });
}
