import 'package:flutter/material.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'bip39_suggest.dart';
import 'restore_copy.dart';
import 'restore_keys.dart';

/// 12-word restore entry (Design §2.7, V2-FR-003, V2-VT-027).
///
/// Per-word validation against the BIP-39 English list with prefix
/// suggestions. A checksum-valid phrase derives the same key as the
/// original install and is handed to [onRestored].
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({
    super.key,
    required this.onRestored,
    this.restore,
    this.placeholderCallsign = 'RESTORED',
  });

  /// Called with the reconstructed identity after a valid phrase.
  final void Function(DeviceIdentity identity) onRestored;

  /// Optional override (tests inject a spy; production derives the key).
  final Future<DeviceIdentity> Function(RecoveryPhrase phrase)? restore;

  /// Display callsign until TASK-093 re-fetches the directory profile.
  final String placeholderCallsign;

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final List<TextEditingController> _controllers =
      List<TextEditingController>.generate(
        recoveryPhraseWordCount,
        (_) => TextEditingController(),
      );
  final List<FocusNode> _focus = List<FocusNode>.generate(
    recoveryPhraseWordCount,
    (_) => FocusNode(),
  );
  int? _activeIndex;
  String? _checksumError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _focus.length; i++) {
      _focus[i].addListener(() {
        if (_focus[i].hasFocus) {
          setState(() => _activeIndex = i);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  List<String> get _words =>
      _controllers.map((c) => c.text.trim().toLowerCase()).toList();

  bool get _allListed => _words.every(isBip39Word);

  String? _wordError(int index) {
    final text = _controllers[index].text.trim();
    if (text.isEmpty) return null;
    if (isBip39Word(text)) return null;
    return RestoreCopy.invalidWord;
  }

  void _setWord(int index, String word) {
    _controllers[index].text = word;
    setState(() {
      _activeIndex = index;
      _checksumError = null;
    });
    if (index + 1 < _focus.length) {
      _focus[index + 1].requestFocus();
    } else {
      _focus[index].unfocus();
    }
  }

  Future<void> _submit() async {
    if (!_allListed || _busy) return;
    setState(() {
      _checksumError = null;
      _busy = true;
    });
    try {
      final phrase = RecoveryPhrase.parse(_words.join(' '));
      final identity = await (widget.restore ?? _defaultRestore)(phrase);
      if (!mounted) return;
      widget.onRestored(identity);
    } on InvalidRecoveryPhraseException {
      if (!mounted) return;
      setState(() => _checksumError = RestoreCopy.checksumFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<DeviceIdentity> _defaultRestore(RecoveryPhrase phrase) async {
    final keyPair = await phrase.deriveKeyPair();
    return DeviceIdentity(
      installUuid: '00000000-0000-4000-8000-000000000001',
      peerId: derivePeerId(keyPair.publicKey),
      shortCode: deriveShortCode(keyPair.publicKey),
      callsign: Callsign.parse(widget.placeholderCallsign),
      keyPair: keyPair,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    final suggestions = _activeIndex == null
        ? const <String>[]
        : suggestBip39(_controllers[_activeIndex!].text);

    return Scaffold(
      key: RestoreKeys.screen,
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(
        title: Text(
          RestoreCopy.title,
          style: KeryxUxTypography.screenTitle.copyWith(
            color: tokens.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                RestoreCopy.body,
                style: KeryxUxTypography.body.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: KeryxUxSpacing.cardSpacing),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < recoveryPhraseWordCount; i++) ...[
                        _WordField(
                          index: i,
                          controller: _controllers[i],
                          focusNode: _focus[i],
                          error: _wordError(i),
                          onChanged: () => setState(() {
                            _activeIndex = i;
                            _checksumError = null;
                          }),
                        ),
                        if (_activeIndex == i && suggestions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: KeryxUxSpacing.controlGap,
                            ),
                            child: Wrap(
                              spacing: KeryxUxSpacing.controlGap,
                              runSpacing: KeryxUxSpacing.controlGap,
                              children: [
                                for (final word in suggestions)
                                  ActionChip(
                                    key: RestoreKeys.suggestion(word),
                                    label: Text(word),
                                    onPressed: () => _setWord(i, word),
                                  ),
                              ],
                            ),
                          ),
                      ],
                      if (_checksumError != null) ...[
                        const SizedBox(height: KeryxUxSpacing.cardSpacing),
                        Text(
                          _checksumError!,
                          key: RestoreKeys.checksumError,
                          style: KeryxUxTypography.body.copyWith(
                            color: tokens.stateTx,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: KeryxUxSpacing.minTarget,
                child: FilledButton(
                  key: RestoreKeys.submit,
                  onPressed: _allListed && !_busy ? _submit : null,
                  child: const Text(RestoreCopy.restore),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordField extends StatelessWidget {
  const _WordField({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.onChanged,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KeryxUxSpacing.controlGap),
      child: TextField(
        key: RestoreKeys.word(index),
        controller: controller,
        focusNode: focusNode,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: index == recoveryPhraseWordCount - 1
            ? TextInputAction.done
            : TextInputAction.next,
        decoration: InputDecoration(
          labelText: RestoreCopy.wordLabel(index + 1),
          error: () {
            final message = error;
            if (message == null) return null;
            return Text(message, key: RestoreKeys.wordError(index));
          }(),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}
