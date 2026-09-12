import 'package:flutter/foundation.dart';

/// Widget keys for onboarding tests (Design §2.6).
abstract final class OnboardingKeys {
  static const Key callsignScreen = Key('onboarding.callsign');
  static const Key callsignField = Key('onboarding.callsign.field');
  static const Key callsignError = Key('onboarding.callsign.error');
  static const Key continueButton = Key('onboarding.callsign.continue');

  static const Key phraseScreen = Key('onboarding.phrase');
  static const Key phraseGrid = Key('onboarding.phrase.grid');
  static const Key phraseBody = Key('onboarding.phrase.body');
  static const Key writtenDown = Key('onboarding.phrase.written-down');

  static Key phraseWord(int zeroBasedIndex) =>
      Key('onboarding.phrase.word.$zeroBasedIndex');
}
