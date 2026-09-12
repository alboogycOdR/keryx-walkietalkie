import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/ux_tokens.dart';
import 'contact_view_models.dart';
import 'contacts_copy.dart';
import 'contacts_keys.dart';
import 'contacts_screen.dart';

/// Overridable scanner so widget tests can drive a payload without a
/// real camera (same seam as TASK-056's Event QR scan screen).
typedef IdScannerBuilder = Widget Function({
  required ValueChanged<String> onRaw,
});

Widget defaultIdScanner({required ValueChanged<String> onRaw}) {
  var consumed = false;
  return MobileScanner(
    onDetect: (capture) {
      if (consumed) return;
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue;
        if (raw == null || raw.isEmpty) continue;
        consumed = true;
        onRaw(raw);
        return;
      }
    },
  );
}

/// Full-screen ID scan. A tampered QR is refused locally and shown as
/// an error; a valid payload is handed to [onRaw] for the controller to
/// send (V2-FR-010; V2-VT-003). The screen does not pop until [onRaw]
/// reports success — a failed send stays here with the same error the
/// paste path already shows.
class ScanIdScreen extends StatefulWidget {
  const ScanIdScreen({
    super.key,
    required this.onRaw,
    this.scannerBuilder = defaultIdScanner,
    this.forceLocalOnly = false,
  });

  /// Called with a locally-valid payload. Return an error message to
  /// keep the screen open, or `null` on success (the screen then pops).
  /// Same contract as the paste-path callback: error string or `null`.
  final Future<String?> Function(String raw) onRaw;
  final IdScannerBuilder scannerBuilder;

  /// When true, show a dismissable notice that contacts/presence need
  /// the relay (Settings → This network only).
  final bool forceLocalOnly;

  @override
  State<ScanIdScreen> createState() => _ScanIdScreenState();
}

class _ScanIdScreenState extends State<ScanIdScreen> {
  String? _error;
  bool _consumed = false;
  bool _busy = false;
  bool _localOnlyDismissed = false;

  void _onRaw(String raw) {
    unawaited(_handleRaw(raw));
  }

  Future<void> _handleRaw(String raw) async {
    if (_consumed) return;
    final parsed = parseContactId(raw);
    if (parsed is ContactIdInvalid) {
      setState(() => _error = parsed.reason);
      return;
    }
    _consumed = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onRaw(raw);
    } catch (_) {
      error = ContactsCopy.requestFailed;
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _consumed = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Scaffold(
      key: ContactsKeys.scanScreen,
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(title: const Text(ContactsCopy.scanACode)),
      body: Column(
        children: [
          if (widget.forceLocalOnly && !_localOnlyDismissed)
            LocalOnlyContactsNotice(
              onDismiss: () => setState(() => _localOnlyDismissed = true),
            ),
          Expanded(
            child: KeyedSubtree(
              key: ContactsKeys.scanView,
              child: widget.scannerBuilder(onRaw: _onRaw),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(key: ContactsKeys.scanBusy),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                key: ContactsKeys.addError,
                style: TextStyle(color: tokens.stateEmergency),
              ),
            ),
        ],
      ),
    );
  }
}
