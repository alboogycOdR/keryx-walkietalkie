import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sound projection remains host-agnostic', () {
    final source = File(
      'lib/services/sound/sfx_projection.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('package:flutter_')));
    expect(source, isNot(contains('flutter_riverpod')));
  });
}
