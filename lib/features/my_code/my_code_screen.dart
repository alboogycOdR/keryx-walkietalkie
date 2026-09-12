import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'keryx_id_link.dart';
import 'my_code_copy.dart';
import 'my_code_keys.dart';
import 'screen_brightness.dart';

/// Full-screen ID QR (Design §2.4, V2-FR-004, V2-VT-003).
///
/// Standalone: the shell injects callsign + public key and optional
/// [onShare]. Brightness is raised for the lifetime of the route.
class MyCodeScreen extends StatefulWidget {
  const MyCodeScreen({
    super.key,
    required this.callsign,
    required this.publicKey,
    this.onShare,
    this.brightness,
    this.clipboard,
  });

  final String callsign;
  final List<int> publicKey;

  /// Shell-provided share action (no `share_plus` in pubspec). Tests spy.
  final Future<void> Function(String url)? onShare;

  final ScreenBrightnessController? brightness;

  /// Override for clipboard writes in tests.
  final Future<void> Function(String text)? clipboard;

  @override
  State<MyCodeScreen> createState() => _MyCodeScreenState();
}

/// Thin wrapper so tests can read the encoded payload. `QrImageView.data`
/// is private in qr_flutter 4.1.
class KeryxIdQr extends StatelessWidget {
  const KeryxIdQr({super.key, required this.payload, this.size = 240});

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: payload,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      semanticsLabel: MyCodeCopy.qrSemantics,
    );
  }
}

class _MyCodeScreenState extends State<MyCodeScreen> {
  late final ScreenBrightnessController _brightness =
      widget.brightness ?? MethodChannelScreenBrightness();
  late final KeryxIdLink _link = KeryxIdLink(
    callsign: widget.callsign,
    publicKey: Uint8List.fromList(widget.publicKey),
  );
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _brightness.setMaximum();
  }

  @override
  void dispose() {
    _brightness.restore();
    super.dispose();
  }

  Future<void> _share() async {
    final share = widget.onShare;
    if (share != null) {
      await share(_link.shareUrl);
      return;
    }
    await _copy();
  }

  Future<void> _copy() async {
    final writer = widget.clipboard ?? _defaultClipboard;
    await writer(_link.shareUrl);
    if (!mounted) return;
    setState(() => _copied = true);
  }

  Future<void> _defaultClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Scaffold(
      key: MyCodeKeys.screen,
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(
        title: Text(
          MyCodeCopy.title,
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
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: KeryxIdQr(
                              key: MyCodeKeys.qr,
                              payload: _link.qrPayload,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: KeryxUxSpacing.cardSpacing),
                      Text(
                        _link.displayId,
                        key: MyCodeKeys.displayId,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Share Tech Mono',
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w400,
                        ).copyWith(color: tokens.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: KeryxUxSpacing.controlGap),
              SizedBox(
                height: KeryxUxSpacing.minTarget,
                child: FilledButton(
                  key: MyCodeKeys.share,
                  onPressed: _share,
                  child: const Text(MyCodeCopy.shareLink),
                ),
              ),
              const SizedBox(height: KeryxUxSpacing.controlGap),
              SizedBox(
                height: KeryxUxSpacing.minTarget,
                child: OutlinedButton(
                  key: MyCodeKeys.copy,
                  onPressed: _copy,
                  child: Text(_copied ? MyCodeCopy.copied : MyCodeCopy.copy),
                ),
              ),
              const SizedBox(height: KeryxUxSpacing.controlGap),
              Semantics(
                button: true,
                label: MyCodeCopy.shareAsLink,
                onTap: _share,
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
