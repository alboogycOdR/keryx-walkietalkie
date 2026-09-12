import 'package:flutter/foundation.dart';

/// Widget keys for Restore tests.
abstract final class RestoreKeys {
  static const Key screen = Key('restore.screen');
  static const Key submit = Key('restore.submit');
  static const Key checksumError = Key('restore.checksum-error');

  static Key word(int zeroBasedIndex) => Key('restore.word.$zeroBasedIndex');

  static Key wordError(int zeroBasedIndex) =>
      Key('restore.word.$zeroBasedIndex.error');

  static Key suggestion(String word) => Key('restore.suggestion.$word');
}
