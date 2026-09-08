import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioMode;
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

import 'station_copy.dart';
import 'station_identity.dart';

/// Keys for widget tests (Design §2.4 content, UX-FR-045/046 honesty).
abstract final class StationsScreenKeys {
  static const Key title = Key('stations.title');
  static const Key channelContext = Key('stations.channel-context');
  static const Key empty = Key('stations.empty');
  static const Key list = Key('stations.list');
  static const Key localCount = Key('stations.local-count');
  static const Key linkedCount = Key('stations.linked-count');
  static const Key quality = Key('stations.quality');
  static const Key scan = Key('stations.scan');
  static const Key export = Key('stations.export');
  static const Key streamFault = Key('stations.stream-fault');

  static Key row(String peerId) => Key('stations.row.$peerId');
}

/// Design §2.4 Stations — full-screen live roster.
///
/// Reads TASK-046's [RadioViewState] and the host's existing station
/// stream (`RadioHostSnapshot.stations`, the same feed TASK-043's
/// `RosterScreen` consumed). Widget tree is new (ADR-001 §7 item 2);
/// no new data source is introduced. Event QR screens are TASK-056's —
/// this widget only launches them.
class StationsScreen extends ConsumerStatefulWidget {
  const StationsScreen({super.key, this.onScan, this.onExport});

  /// Opens TASK-056's scan flow. `null` disables the action.
  final VoidCallback? onScan;

  /// Opens TASK-056's export flow. `null` disables the action.
  final VoidCallback? onExport;

  @override
  ConsumerState<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends ConsumerState<StationsScreen> {
  StreamSubscription<RadioHostSnapshot>? _hostSub;
  RadioHostSnapshot _snapshot = const RadioHostSnapshot();
  bool _streamFault = false;

  @override
  void initState() {
    super.initState();
    final RadioHost host = ref.read(radioHostProvider);
    _snapshot = host.current;
    // Own subscription — live join/depart while open, without a
    // parent-screen rebuild (Design §2.4; UX-FR-040; VT-024).
    _hostSub = host.changes.listen(
      (RadioHostSnapshot snapshot) {
        if (!mounted) {
          return;
        }
        setState(() {
          _snapshot = snapshot;
          _streamFault = false;
        });
      },
      onError: (Object _, StackTrace _) {
        if (!mounted) {
          return;
        }
        // Stated-unavailable, not a stale last-good snapshot.
        setState(() {
          _snapshot = const RadioHostSnapshot();
          _streamFault = true;
        });
      },
    );
  }

  @override
  void dispose() {
    unawaited(_hostSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const KeryxSettings();
    final RadioViewState view = RadioViewState.project(
      radioState: ref.watch(radioStateProvider),
      hostSnapshot: _snapshot,
      settings: settings,
    );
    return StationsView(
      view: view,
      streamFault: _streamFault,
      onScan: widget.onScan,
      onExport: widget.onExport,
    );
  }
}

/// Pure presentation of a [RadioViewState].
///
/// [StationsScreen] owns the host subscription and projection; this
/// widget switches on the sealed honesty types so a measured quality
/// reading or a known roster count actually appears on screen
/// (UX-FR-045/046). Tests construct a [RadioViewState] directly when
/// the production projection cannot yet produce that variant.
class StationsView extends StatelessWidget {
  const StationsView({
    super.key,
    required this.view,
    this.streamFault = false,
    this.onScan,
    this.onExport,
  });

  final RadioViewState view;
  final bool streamFault;
  final VoidCallback? onScan;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    final String channelLabel = StationsCopy.channelContext(
      view.channel,
      view.privacyCode,
    );

    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: tokens.surfaceBase,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              StationsCopy.title,
              key: StationsScreenKeys.title,
              style: KeryxUxTypography.screenTitle.copyWith(
                color: tokens.textPrimary,
              ),
            ),
            Text(
              channelLabel,
              key: StationsScreenKeys.channelContext,
              style: KeryxUxTypography.compact.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          _QrAction(
            key: StationsScreenKeys.scan,
            icon: Icons.qr_code_scanner,
            label: StationsCopy.scanEventQr,
            tokens: tokens,
            onPressed: onScan,
          ),
          _QrAction(
            key: StationsScreenKeys.export,
            icon: Icons.qr_code,
            label: StationsCopy.exportEventQr,
            tokens: tokens,
            onPressed: onExport,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KeryxUxSpacing.pageMargin,
            KeryxUxSpacing.grid,
            KeryxUxSpacing.pageMargin,
            KeryxUxSpacing.pageMargin,
          ),
          children: <Widget>[
            if (streamFault)
              _StreamFault(tokens: tokens)
            else
              _CountRow(
                rosterCount: view.rosterCount,
                effectiveRoute: view.connection.effectiveRoute,
                tokens: tokens,
              ),
            const SizedBox(height: KeryxUxSpacing.controlGap),
            _QualityReading(quality: view.signalQuality, tokens: tokens),
            const SizedBox(height: KeryxUxSpacing.cardSpacing),
            if (!streamFault) ..._rosterBody(tokens),
          ],
        ),
      ),
    );
  }

  List<Widget> _rosterBody(KeryxUxTokens tokens) {
    final bool showVerifiedEmpty = switch (view.rosterCount) {
      KnownRosterCount() => view.stations.isEmpty,
      UnavailableRosterCount() => false,
    };
    if (showVerifiedEmpty) {
      return <Widget>[_EmptyState(tokens: tokens)];
    }
    if (view.stations.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[_StationList(stations: view.stations, tokens: tokens)];
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.rosterCount,
    required this.effectiveRoute,
    required this.tokens,
  });

  final RosterCount rosterCount;
  final RadioMode effectiveRoute;
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    return switch (rosterCount) {
      KnownRosterCount(:final int count) => Semantics(
        label: '${StationsCopy.localCountLabel}: $count',
        child: Text(
          StationsCopy.localCount(count),
          key: StationsScreenKeys.localCount,
          style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary),
        ),
      ),
      UnavailableRosterCount() => Semantics(
        label: StationsCopy.incompleteRoster(effectiveRoute),
        child: Text(
          StationsCopy.incompleteRoster(effectiveRoute),
          key: StationsScreenKeys.linkedCount,
          style: KeryxUxTypography.body.copyWith(color: tokens.stateWarning),
        ),
      ),
    };
  }
}

class _QualityReading extends StatelessWidget {
  const _QualityReading({required this.quality, required this.tokens});

  final SignalQuality quality;
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    final String label = StationsCopy.qualityLabel(quality);
    final IconData icon = switch (quality) {
      UnavailableSignalQuality() => Icons.signal_cellular_null,
      MeasuredSignalQuality() => Icons.network_check,
    };
    return Semantics(
      label: label,
      child: Row(
        key: StationsScreenKeys.quality,
        children: <Widget>[
          Icon(icon, color: tokens.textSecondary, size: 20),
          const SizedBox(width: KeryxUxSpacing.controlGap),
          Expanded(
            child: Text(
              label,
              style: KeryxUxTypography.secondary.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamFault extends StatelessWidget {
  const _StreamFault({required this.tokens});

  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: StationsCopy.streamUnavailable,
      child: Text(
        StationsCopy.streamUnavailable,
        key: StationsScreenKeys.streamFault,
        style: KeryxUxTypography.body.copyWith(color: tokens.stateWarning),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tokens});

  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KeryxUxSpacing.cardSpacing),
      child: Text(
        StationsCopy.empty,
        key: StationsScreenKeys.empty,
        style: KeryxUxTypography.body.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

class _StationList extends StatelessWidget {
  const _StationList({required this.stations, required this.tokens});

  final List<StationInfo> stations;
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: StationsScreenKeys.list,
      children: <Widget>[
        for (int i = 0; i < stations.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: KeryxUxSpacing.controlGap),
          _StationRow(station: stations[i], tokens: tokens),
        ],
      ],
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({required this.station, required this.tokens});

  final StationInfo station;
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    final String name = stationDisplayName(station);
    return Semantics(
      label: '$name, ${StationsCopy.presenceVisible}',
      child: Material(
        key: StationsScreenKeys.row(station.peerId),
        color: tokens.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KeryxUxSpacing.grid),
          side: BorderSide(color: tokens.borderDefault),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: KeryxUxSpacing.minTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KeryxUxSpacing.cardSpacing,
              vertical: KeryxUxSpacing.controlGap,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.cell_tower, color: tokens.actionPrimary, size: 20),
                const SizedBox(width: KeryxUxSpacing.controlGap),
                Expanded(
                  child: Text(
                    name,
                    style: KeryxUxTypography.body.copyWith(
                      color: tokens.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: KeryxUxSpacing.controlGap),
                Icon(
                  Icons.visibility_outlined,
                  color: tokens.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: KeryxUxSpacing.controlGap),
                Text(
                  StationsCopy.presenceVisible,
                  style: KeryxUxTypography.compact.copyWith(
                    color: tokens.textSecondary,
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

class _QrAction extends StatelessWidget {
  const _QrAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tokens,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final KeryxUxTokens tokens;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: KeryxUxSpacing.minTarget,
        minHeight: KeryxUxSpacing.minTarget,
      ),
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        color: tokens.textPrimary,
        icon: Icon(icon),
      ),
    );
  }
}
