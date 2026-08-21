import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'event_link.dart';

/// Exports a channel as a QR + `keryx://` deep link (FR-043, FR-044).
///
/// This widget owns only the expiry-preset UI and QR rendering; it does not
/// know how to reach the currently-tuned channel or a keyed-channel
/// passphrase — that is host state this feature has no business owning.
/// [payloadBuilder] is called every time the preset changes (fed the
/// resolved `expiresAt`, or `null` for no-expiry) and must return the
/// concrete [EventLinkPayload] to encode. For a numbered channel this is
/// synchronous (`NumberedEventLink(...)`); for a keyed channel the host
/// must have already resolved the roomId via [buildKeyedEventLink] (its
/// `compute()` isolate hop cannot happen inside this widget's synchronous
/// `build()`) and hand in a `(expiresAt) => KeyedEventLink(roomId: ..., expiresAt: expiresAt)`
/// closure.
class EventQrExportScreen extends StatefulWidget {
  const EventQrExportScreen({
    super.key,
    required this.payloadBuilder,
    this.initialPreset = defaultEventLinkExpiryPreset,
    this.now,
  });

  final EventLinkPayload Function(DateTime? expiresAt) payloadBuilder;
  final EventLinkExpiryPreset initialPreset;

  /// Injection seam for deterministic tests; production leaves this unset.
  final DateTime Function()? now;

  @override
  State<EventQrExportScreen> createState() => _EventQrExportScreenState();
}

class _EventQrExportScreenState extends State<EventQrExportScreen> {
  late EventLinkExpiryPreset _preset = widget.initialPreset;
  bool _noExpiryPendingConfirmation = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  void _selectPreset(EventLinkExpiryPreset preset) {
    if (preset == _preset) return;
    if (preset.requiresExplicitConfirmation) {
      // FR-044: "no expiry — the last requiring an explicit extra tap" —
      // selecting it only arms a confirmation; it does not take effect yet.
      setState(() => _noExpiryPendingConfirmation = true);
      return;
    }
    setState(() {
      _preset = preset;
      _noExpiryPendingConfirmation = false;
    });
  }

  void _confirmNoExpiry() {
    setState(() {
      _preset = EventLinkExpiryPreset.noExpiry;
      _noExpiryPendingConfirmation = false;
    });
  }

  void _cancelNoExpiryConfirmation() {
    setState(() => _noExpiryPendingConfirmation = false);
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = _preset.expiresAtFrom(_now());
    final payload = widget.payloadBuilder(expiresAt);
    final link = encodeEventLink(payload).toString();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: QrImageView(
            data: link,
            version: QrVersions.auto,
            size: 240,
            semanticsLabel: 'Event QR code',
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(link, textAlign: TextAlign.center, key: const Key('event_qr_link_text')),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in EventLinkExpiryPreset.values)
              ChoiceChip(
                label: Text(preset.label),
                selected: _preset == preset,
                onSelected: (_) => _selectPreset(preset),
              ),
          ],
        ),
        if (_noExpiryPendingConfirmation) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                key: const Key('event_qr_confirm_no_expiry'),
                onPressed: _confirmNoExpiry,
                child: const Text('Confirm: no expiry'),
              ),
              TextButton(
                onPressed: _cancelNoExpiryConfirmation,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
