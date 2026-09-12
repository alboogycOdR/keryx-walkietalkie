import 'package:flutter/material.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'onboarding_copy.dart';
import 'onboarding_keys.dart';

/// 3×4 numbered mono grid of a 12-word recovery phrase.
///
/// Design §2.6 / §6: each cell is TalkBack-readable word by word. There
/// is no copy control; [SelectionContainer.disabled] blocks text
/// selection so the platform copy affordance cannot appear.
class RecoveryPhraseGrid extends StatelessWidget {
  const RecoveryPhraseGrid({super.key, required this.words});

  final List<String> words;

  static const TextStyle _mono = TextStyle(
    fontFamily: 'Share Tech Mono',
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w400,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    assert(words.length == 12, 'recovery phrase is 12 words');

    return SelectionContainer.disabled(
      child: Semantics(
        container: true,
        label: OnboardingCopy.phraseTitle,
        child: GridView.builder(
          key: OnboardingKeys.phraseGrid,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 12,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: KeryxUxSpacing.controlGap,
            crossAxisSpacing: KeryxUxSpacing.controlGap,
            childAspectRatio: 2.4,
          ),
          itemBuilder: (context, index) {
            final word = words[index];
            final n = index + 1;
            return Semantics(
              key: OnboardingKeys.phraseWord(index),
              label: OnboardingCopy.wordSemantics(n, word),
              readOnly: true,
              button: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tokens.borderDefault),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: ExcludeSemantics(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$n  $word',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _mono.copyWith(color: tokens.textPrimary),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
