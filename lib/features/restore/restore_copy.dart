/// Design §2.7 Restore-from-phrase copy.
abstract final class RestoreCopy {
  static const String title = 'Restore from phrase';
  static const String body =
      'Enter the 12 words from your recovery phrase, in order.';
  static const String restore = 'Restore';
  static const String invalidWord = 'Not a recovery word';
  static const String checksumFailed =
      'That phrase is not valid. Check each word.';
  static const String incomplete = 'Enter all 12 words to restore.';

  static String wordLabel(int oneBasedIndex) => 'Word $oneBasedIndex';
}
