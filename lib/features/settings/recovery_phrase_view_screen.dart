import 'package:flutter/material.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'settings_copy.dart';
import 'settings_keys.dart';

/// v2 (Design §2.7 "Show recovery phrase behind device lock"): re-displays
/// the same 3×4 numbered mono grid `OnboardingScreen` showed at first run,
/// read back from wherever this shell persisted it
/// (`lib/app_shell/onboarding_gate.dart`'s `RecoveryPhraseVault` — this
/// screen only renders whatever [words] its caller hands it, it does not
/// know how they were stored). No copy affordance, matching Design §2.6's
/// own onboarding rule ("a Copy is deliberately absent").
class RecoveryPhraseViewScreen extends StatelessWidget {
  const RecoveryPhraseViewScreen({super.key, required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return Scaffold(
      key: SettingsKeys.recoveryPhraseView,
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: tokens.surfaceBase,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: const Text(SettingsCopy.recoveryPhraseTitle),
      ),
      body: SafeArea(
        child: SelectionContainer.disabled(
          child: Padding(
            padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  SettingsCopy.recoveryPhraseWarning,
                  style: KeryxUxTypography.body.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: KeryxUxSpacing.grid),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: KeryxUxSpacing.controlGap,
                    crossAxisSpacing: KeryxUxSpacing.controlGap,
                    childAspectRatio: 2.4,
                    children: List<Widget>.generate(words.length, (i) {
                      final int n = i + 1;
                      return Semantics(
                        label: 'Word $n, ${words[i]}',
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: tokens.borderDefault),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '$n. ${words[i]}',
                              style: KeryxUxTypography.body.copyWith(
                                fontFamily: 'Share Tech Mono',
                                color: tokens.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
