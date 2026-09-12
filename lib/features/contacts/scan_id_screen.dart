import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/ux_tokens.dart';
import 'contact_view_models.dart';
import 'contacts_copy.dart';
import 'contacts_keys.dart';

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
/// send (V2-FR-010; V2-VT-003).
class ScanIdScreen extends StatefulWidget {
  const ScanIdScreen({
    super.key,
    required this.onRaw,
    this.scannerBuilder = defaultIdScanner,
  });

  final ValueChanged<String> onRaw;
  final IdScannerBuilder scannerBuilder;

  @override
  State<ScanIdScreen> createState() => _ScanIdScreenState();
}

class _ScanIdScreenState extends State<ScanIdScreen> {
  String? _error;
  bool _consumed = false;

  void _onRaw(String raw) {
    if (_consumed) return;
    final parsed = parseContactId(raw);
    if (parsed is ContactIdInvalid) {
      setState(() => _error = parsed.reason);
      return;
    }
    _consumed = true;
    widget.onRaw(raw);
    if (mounted) Navigator.of(context).maybePop();
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
          Expanded(
            child: KeyedSubtree(
              key: ContactsKeys.scanView,
              child: widget.scannerBuilder(onRaw: _onRaw),
            ),
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
