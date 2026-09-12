/// Design §2.6 / §5 copy for first-run onboarding. Sentence case.
///
/// Design §5: "Write these 12 words down and keep them safe. They are
/// the only way to get your KERYX ID back." The confirmation label is
/// V2-FR-002's "I've written it down".
abstract final class OnboardingCopy {
  static const String callsignTitle = 'Choose a callsign';
  static const String callsignHint = '2–12 letters, digits or hyphens';
  static const String callsignFieldLabel = 'Callsign';
  static const String continueLabel = 'Continue';

  static const String phraseTitle = 'Recovery phrase';
  static const String phraseBody =
      'Write these 12 words down and keep them safe. '
      'They are the only way to get your KERYX ID back.';
  static const String writtenDown = "I've written it down";

  static String wordSemantics(int oneBasedIndex, String word) =>
      'Word $oneBasedIndex, $word';
}
