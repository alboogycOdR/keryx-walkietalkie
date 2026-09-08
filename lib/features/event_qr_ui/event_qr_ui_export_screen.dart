import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/settings/settings_repository.dart'
    show KeryxSettings, settingsProvider;
import 'package:keryx/core/state/radio_state.dart' show RadioState;
import 'package:keryx/core/state/radio_state_controller.dart' show radioStateProvider;
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/event_qr/event_qr.dart'
    show EventQrExportScreen, NumberedEventLink;

import 'event_qr_ui_copy.dart';

/// Keys for widget tests (Design §2.7).
abstract final class EventQrUiExportKeys {
  static const Key title = Key('event-qr-ui.export.title');
  static const Key unavailable = Key('event-qr-ui.export.unavailable');
  static const Key numberedExport = Key('event-qr-ui.export.numbered');
}

/// Design §2.7 — modern framing over the existing export logic
/// (`lib/features/event_qr/**`, unmodified, ADR-001 §6).
///
/// Only the currently-tuned **numbered** channel can be exported here.
/// Technical §1.1/§8 flag keyed export as requiring additional
/// server-side wiring that does not exist yet (no `EVENT_TOKEN_SECRET`
/// config seam — see `lib/features/event_qr/README.md`), so a keyed
/// -channel session surfaces an explicit "not available yet" state
/// instead of being presented as working (honesty rule, UX-FR-044's
/// sibling applied to export).
class EventQrUiExportScreen extends ConsumerWidget {
  const EventQrUiExportScreen({super.key, this.now});

  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final radioState = ref.watch(radioStateProvider);
    final tokens = KeryxUxTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(EventQrUiCopy.exportTitle, key: EventQrUiExportKeys.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
          // TASK-057 round 2: the embedded `EventQrExportScreen` (frozen
          // legacy territory, `lib/features/event_qr/**` — not edited here,
          // ADR-001 §6) has a fixed-height Column that genuinely overflows
          // at a small landscape height (reproduced by the responsive-
          // matrix test). Scrolling at this wrapper layer fixes the
          // clipping without touching the frozen widget's own layout.
          child: SingleChildScrollView(
            child: _body(settings, radioState, tokens),
          ),
        ),
      ),
    );
  }

  Widget _body(KeryxSettings? settings, RadioState radioState, KeryxUxTokens tokens) {
    if (settings == null) {
      return _unavailable(EventQrUiCopy.exportSettingsUnavailable, tokens);
    }
    if (radioState.isPrivate) {
      return _unavailable(
        EventQrUiCopy.keyedExportUnavailableBody,
        tokens,
        title: EventQrUiCopy.keyedExportUnavailableTitle,
      );
    }
    return EventQrExportScreen(
      key: EventQrUiExportKeys.numberedExport,
      payloadBuilder: (expiresAt) => NumberedEventLink(
        region: settings.region,
        channel: radioState.channel,
        code: radioState.privacyCode,
        expiresAt: expiresAt,
      ),
      now: now,
    );
  }

  Widget _unavailable(String body, KeryxUxTokens tokens, {String? title}) {
    return Semantics(
      liveRegion: true,
      label: title ?? body,
      child: Center(
        key: EventQrUiExportKeys.unavailable,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: KeryxUxTypography.sectionTitle.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: KeryxUxSpacing.controlGap),
            ],
            Text(
              body,
              textAlign: TextAlign.center,
              style: KeryxUxTypography.body.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
