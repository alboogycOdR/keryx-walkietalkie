import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

import 'tuning_physics.dart';

/// Fired once with a fully validated channel + privacy code. Never fired
/// with an out-of-domain value — [KeypadSheetState] rejects those inline.
typedef DirectTuneCallback = void Function(int channel, int privacyCode);

/// Long-press-channel-display keypad direct-entry sheet (FR-005, D1).
///
/// **"Rendered in-world, not a Material dialog" (task Description; DS §6
/// "No state may use a dialog, toast, or snackbar (P1)").** PT has no keypad
/// at all (grep-confirmed absent), so there is no ratified visual reference
/// — this is a disclosed engineering resolution, non-blocking, same class as
/// TASK-013/015's PT-gap precedents. [showKeryxKeypadSheet] presents
/// [KeypadSheet] via `showModalBottomSheet` (a bottom sheet, not an
/// `AlertDialog`/`Dialog`) with the default Material chrome fully stripped —
/// transparent barrier-less background, no drag handle, no rounded
/// M3-white-card — and the content itself styled as `KeryxTheme.shell700`
/// housing material with the glass-style segment-font echo, so the surface
/// reads as part of the radio rather than an app dialog.
///
/// Digits are entered sequentially: up to 2 for the channel, then up to 2
/// for the privacy code (an explicit "next" advances early, e.g. entering a
/// single-digit channel like `7` for `CH 07`). Confirm validates both fields
/// against [TuningPhysics] bounds (channel 1-99, code 00-38 — the *same*
/// CLAMP-ruling domain the reducer enforces, TASK-004/027) and rejects
/// out-of-domain values inline (an in-world error line, never a dialog)
/// rather than clamping silently — a direct-entry field is exactly where a
/// user should be told "no" rather than have their typed number silently
/// changed.
class KeypadSheet extends StatefulWidget {
  const KeypadSheet({
    super.key,
    required this.onConfirm,
    this.onCancel,
    this.initialChannel,
    this.initialPrivacyCode,
  });

  /// Fired with a validated `(channel, privacyCode)` pair.
  final DirectTuneCallback onConfirm;

  /// Fired when the sheet is dismissed without confirming.
  final VoidCallback? onCancel;

  /// Pre-fills the channel field (e.g. the currently tuned channel).
  final int? initialChannel;

  /// Pre-fills the privacy-code field.
  final int? initialPrivacyCode;

  @override
  State<KeypadSheet> createState() => KeypadSheetState();
}

enum _KeypadField { channel, code }

/// Public so widget tests can drive digit entry directly.
class KeypadSheetState extends State<KeypadSheet> {
  static const int _maxDigitsPerField = 2;

  _KeypadField _field = _KeypadField.channel;
  String _channelDigits = '';
  String _codeDigits = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialChannel != null) {
      _channelDigits = widget.initialChannel!.toString().padLeft(2, '0');
    }
    if (widget.initialPrivacyCode != null) {
      _codeDigits = widget.initialPrivacyCode!.toString().padLeft(2, '0');
    }
  }

  /// Exposed for widget tests.
  @visibleForTesting
  String get channelDigits => _channelDigits;

  /// Exposed for widget tests.
  @visibleForTesting
  String get codeDigits => _codeDigits;

  /// Exposed for widget tests.
  @visibleForTesting
  String? get error => _error;

  void _onDigit(String digit) {
    setState(() {
      _error = null;
      if (_field == _KeypadField.channel) {
        if (_channelDigits.length < _maxDigitsPerField) {
          _channelDigits += digit;
        }
        if (_channelDigits.length == _maxDigitsPerField) {
          _field = _KeypadField.code;
        }
      } else {
        if (_codeDigits.length < _maxDigitsPerField) _codeDigits += digit;
      }
    });
  }

  void _onNext() {
    setState(() {
      _error = null;
      if (_field == _KeypadField.channel && _channelDigits.isNotEmpty) {
        _field = _KeypadField.code;
      }
    });
  }

  void _onBackspace() {
    setState(() {
      _error = null;
      if (_field == _KeypadField.code) {
        if (_codeDigits.isNotEmpty) {
          _codeDigits = _codeDigits.substring(0, _codeDigits.length - 1);
        } else {
          _field = _KeypadField.channel;
          if (_channelDigits.isNotEmpty) {
            _channelDigits = _channelDigits.substring(
              0,
              _channelDigits.length - 1,
            );
          }
        }
      } else if (_channelDigits.isNotEmpty) {
        _channelDigits = _channelDigits.substring(
          0,
          _channelDigits.length - 1,
        );
      }
    });
  }

  void _onConfirm() {
    if (_channelDigits.isEmpty) {
      setState(() => _error = 'Enter a channel, 1 to 99.');
      return;
    }
    final channel = int.parse(_channelDigits);
    final code = _codeDigits.isEmpty ? 0 : int.parse(_codeDigits);
    if (!TuningPhysics.isValidChannel(channel)) {
      setState(() => _error = 'Channel must be 1 to 99.');
      return;
    }
    if (!TuningPhysics.isValidPrivacyCode(code)) {
      setState(() => _error = 'Code must be 00 to 38.');
      return;
    }
    widget.onConfirm(channel, code);
  }

  String get _channelEcho => _channelDigits.padRight(2, '_');
  String get _codeEcho => _codeDigits.padRight(2, '_');

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('keryx-keypad-sheet'),
      padding: EdgeInsets.only(
        left: KeryxTheme.grid * 2,
        right: KeryxTheme.grid * 2,
        top: KeryxTheme.grid * 2,
        bottom: KeryxTheme.grid * 2 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: KeryxTheme.shell700,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 16),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            label:
                'Direct entry. Channel $_channelEcho, code $_codeEcho'
                '${_error != null ? '. ${_error!}' : ''}',
            child: Text(
              'CH $_channelEcho · $_codeEcho',
              style: KeryxTheme.channelNumerals.copyWith(
                fontSize: 32,
                color: KeryxTheme.lcd,
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            SizedBox(height: KeryxTheme.grid),
            Text(
              _error!,
              style: KeryxTheme.panelBody.copyWith(color: KeryxTheme.emergency),
            ),
          ],
          SizedBox(height: KeryxTheme.grid * 2),
          _KeypadGrid(
            onDigit: _onDigit,
            onNext: _onNext,
            onBackspace: _onBackspace,
          ),
          SizedBox(height: KeryxTheme.grid),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              TextButton(
                key: const Key('keryx-keypad-cancel'),
                onPressed: () {
                  widget.onCancel?.call();
                  Navigator.of(context).maybePop();
                },
                child: Text(
                  'CANCEL',
                  style: KeryxTheme.legendLabel.copyWith(
                    color: KeryxTheme.legend,
                  ),
                ),
              ),
              TextButton(
                key: const Key('keryx-keypad-confirm'),
                onPressed: _onConfirm,
                child: Text(
                  'CONFIRM',
                  style: KeryxTheme.legendLabel.copyWith(color: KeryxTheme.rx),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeypadGrid extends StatelessWidget {
  const _KeypadGrid({
    required this.onDigit,
    required this.onNext,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onNext;
  final VoidCallback onBackspace;

  static const List<String> _rows = <String>[
    '123',
    '456',
    '789',
    '⌫0·',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _rows
          .map(
            (row) => Padding(
              padding: EdgeInsets.symmetric(vertical: KeryxTheme.grid / 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row
                    .split('')
                    .map((glyph) => _KeypadKey(glyph: glyph, onTap: _onTap))
                    .toList(growable: false),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  void _onTap(String glyph) {
    switch (glyph) {
      case '⌫':
        onBackspace();
      case '·':
        onNext();
      default:
        onDigit(glyph);
    }
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({required this.glyph, required this.onTap});

  final String glyph;
  final void Function(String glyph) onTap;

  String get _semanticsLabel => switch (glyph) {
    '⌫' => 'Backspace',
    '·' => 'Next field',
    _ => 'Digit $glyph',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _semanticsLabel,
      child: Material(
        color: KeryxTheme.shell500,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('keryx-keypad-key-$glyph'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(glyph),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Text(
                glyph,
                style: KeryxTheme.glassSecondary.copyWith(
                  color: KeryxTheme.legend,
                  fontFamily: 'Barlow Condensed',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Presents [KeypadSheet] as an in-world bottom sheet (see class dartdoc for
/// why `showModalBottomSheet` rather than a `Dialog`/`AlertDialog`). Intended
/// caller: TASK-017's face assembly, wired to a long-press on the channel
/// display (`lib/features/display/**`, frozen, out of this task's territory
/// — the *trigger gesture* is composed by the assembly, not owned here).
Future<void> showKeryxKeypadSheet(
  BuildContext context, {
  required DirectTuneCallback onConfirm,
  VoidCallback? onCancel,
  int? initialChannel,
  int? initialPrivacyCode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.6),
    isScrollControlled: true,
    builder: (sheetContext) => KeypadSheet(
      onConfirm: (channel, code) {
        onConfirm(channel, code);
        Navigator.of(sheetContext).maybePop();
      },
      onCancel: onCancel,
      initialChannel: initialChannel,
      initialPrivacyCode: initialPrivacyCode,
    ),
  );
}
