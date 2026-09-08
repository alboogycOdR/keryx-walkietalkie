import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/radio_host/radio_host.dart' show RadioHost;
import 'package:keryx/core/settings/settings_repository.dart' show settingsProvider;
import 'package:keryx/core/state/radio_state_controller.dart' show radioStateProvider;
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/event_qr/event_qr.dart'
    show EventLinkPayload, EventQrScanScreen;

import 'event_qr_join_coordinator.dart';
import 'event_qr_permission_gate.dart';
import 'event_qr_ui_copy.dart';

/// Keys for widget tests (Design §2.7).
abstract final class EventQrUiScanKeys {
  static const Key title = Key('event-qr-ui.scan.title');
  static const Key permissionAction = Key('event-qr-ui.scan.permission-action');
  static const Key permissionUnavailable = Key('event-qr-ui.scan.permission-unavailable');
  static const Key scanner = Key('event-qr-ui.scan.scanner');
  static const Key routeTransitionDialog = Key('event-qr-ui.scan.route-transition-dialog');
  static const Key routeTransitionConfirm = Key('event-qr-ui.scan.route-transition-confirm');
  static const Key routeTransitionCancel = Key('event-qr-ui.scan.route-transition-cancel');
}

/// Builds the inner scanning widget. Overridable in tests so a widget test
/// can drive [EventQrUiScanScreen]'s join/permission logic without a real
/// `mobile_scanner` platform channel — production always uses the default,
/// which wraps the existing, unmodified `EventQrScanScreen`
/// (`lib/features/event_qr/**`, ADR-001 §6).
typedef EventQrScannerBuilder =
    Widget Function({
      Key? key,
      required void Function(EventLinkPayload payload) onTuned,
      void Function(String reason)? onInvalid,
    });

Widget _defaultScannerBuilder({
  Key? key,
  required void Function(EventLinkPayload payload) onTuned,
  void Function(String reason)? onInvalid,
}) {
  return EventQrScanScreen(key: key, onTuned: onTuned, onInvalid: onInvalid);
}

/// Design §2.7 — modern framing over the existing scan logic, closing
/// Technical §1.1's behavioural gap: a scan that needs a LINKED session
/// while the app is in LOCAL now explains why and offers an explicit,
/// cancellable, user-approved route transition instead of silently
/// failing (Technical §8; PRD §4.4).
///
/// [host] is injected by the caller (`lib/app_shell/**`); `lib/features/**`
/// never imports `lib/app_shell/**` (mirrors TASK-054's `RadioControlsScreen`).
class EventQrUiScanScreen extends ConsumerStatefulWidget {
  const EventQrUiScanScreen({
    super.key,
    required this.host,
    this.permissionGate = const PermissionHandlerEventQrPermissionGate(),
    this.joinCoordinator = const EventQrJoinCoordinator(),
    this.scannerBuilder = _defaultScannerBuilder,
  });

  final RadioHost host;
  final EventQrPermissionGate permissionGate;
  final EventQrJoinCoordinator joinCoordinator;
  final EventQrScannerBuilder scannerBuilder;

  @override
  ConsumerState<EventQrUiScanScreen> createState() => _EventQrUiScanScreenState();
}

class _EventQrUiScanScreenState extends ConsumerState<EventQrUiScanScreen> {
  EventQrPermissionState? _permission;
  int _scanGeneration = 0;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final state = await widget.permissionGate.checkCamera();
    if (!mounted) return;
    setState(() => _permission = state);
  }

  Future<void> _requestPermission() async {
    final state = await widget.permissionGate.requestCamera();
    if (!mounted) return;
    setState(() => _permission = state);
  }

  void _resumeScanning() {
    if (!mounted) return;
    setState(() {
      _scanGeneration++;
      _busy = false;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  Future<bool> _confirmRouteTransition() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: EventQrUiScanKeys.routeTransitionDialog,
        title: const Text(EventQrUiCopy.routeTransitionTitle),
        content: const Text(EventQrUiCopy.routeTransitionBody),
        actions: [
          TextButton(
            key: EventQrUiScanKeys.routeTransitionCancel,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(EventQrUiCopy.routeTransitionCancel),
          ),
          TextButton(
            key: EventQrUiScanKeys.routeTransitionConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(EventQrUiCopy.routeTransitionConfirm),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  Future<void> _handleTuned(EventLinkPayload payload) async {
    if (_busy) return;
    setState(() => _busy = true);

    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) {
      _showMessage(EventQrUiCopy.settingsUnavailable);
      _resumeScanning();
      return;
    }
    final effectiveRoute = ref.read(radioStateProvider).mode;

    final result = await widget.joinCoordinator.join(
      host: widget.host,
      payload: payload,
      effectiveRoute: effectiveRoute,
      settings: settings,
      requestRouteTransitionApproval: _confirmRouteTransition,
    );
    if (!mounted) return;

    switch (result.outcome) {
      case EventQrJoinOutcome.success:
        Navigator.of(context).maybePop(true);
      case EventQrJoinOutcome.cancelled:
        _showMessage(EventQrUiCopy.joinCancelled);
        _resumeScanning();
      case EventQrJoinOutcome.forceLocalBlocked:
        _showMessage(EventQrUiCopy.forceLocalBlocked);
        _resumeScanning();
      case EventQrJoinOutcome.routeTransitionFailed:
      case EventQrJoinOutcome.joinFailed:
        _showMessage(EventQrUiCopy.joinFailed);
        _resumeScanning();
    }
  }

  void _handleInvalid(String reason) {
    if (reason == 'expired') {
      _showMessage(EventQrUiCopy.scanExpired);
      _resumeScanning();
    } else {
      _showMessage(EventQrUiCopy.scanInvalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not just read-on-demand) so the async settings load is
    // already warmed up and resolved by the time a scan needs it in
    // `_handleTuned` — a provider that has only ever been `ref.read` from
    // a callback is still `AsyncLoading` the first time that callback
    // fires, since nothing started it earlier.
    ref.watch(settingsProvider);
    final tokens = KeryxUxTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(EventQrUiCopy.scanTitle, key: EventQrUiScanKeys.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildBody(tokens)),
              if (_message != null) ...[
                const SizedBox(height: KeryxUxSpacing.cardSpacing),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    style: KeryxUxTypography.secondary.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(KeryxUxTokens tokens) {
    switch (_permission) {
      case null:
        return const Center(child: CircularProgressIndicator());
      case EventQrPermissionState.granted:
        return widget.scannerBuilder(
          key: ValueKey('event-qr-ui.scanner.$_scanGeneration'),
          onTuned: _handleTuned,
          onInvalid: _handleInvalid,
        );
      case EventQrPermissionState.denied:
        return _permissionState(
          title: EventQrUiCopy.permissionDeniedTitle,
          body: EventQrUiCopy.permissionDeniedBody,
          actionLabel: EventQrUiCopy.permissionDeniedAction,
          onAction: _requestPermission,
        );
      case EventQrPermissionState.permanentlyDenied:
        return _permissionState(
          title: EventQrUiCopy.permissionPermanentlyDeniedTitle,
          body: EventQrUiCopy.permissionPermanentlyDeniedBody,
          actionLabel: EventQrUiCopy.permissionPermanentlyDeniedAction,
          onAction: widget.permissionGate.openAppSettings,
        );
      case EventQrPermissionState.unavailable:
        return _permissionState(
          title: EventQrUiCopy.permissionUnavailableTitle,
          body: EventQrUiCopy.permissionUnavailableBody,
          unavailable: true,
        );
    }
  }

  Widget _permissionState({
    required String title,
    required String body,
    String? actionLabel,
    Future<void> Function()? onAction,
    bool unavailable = false,
  }) {
    return Center(
      key: unavailable ? EventQrUiScanKeys.permissionUnavailable : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: KeryxUxSpacing.controlGap),
          Text(body, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: KeryxUxSpacing.cardSpacing),
            SizedBox(
              height: KeryxUxSpacing.minTarget,
              child: ElevatedButton(
                key: EventQrUiScanKeys.permissionAction,
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
