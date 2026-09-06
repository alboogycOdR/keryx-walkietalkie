import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

import 'roster.dart';

/// FR-067's successor: a full-screen station roster, matching the approved
/// Phase 2 canvas's `Roster.dc.html` — replacing the old flip-panel
/// treatment (`station_panel.dart`/`GlassFlipper`, both retired by this
/// task; see the dossier).
///
/// [stations] is a [ValueListenable] rather than a plain snapshot so the
/// screen keeps reflecting live join/depart while it is open, the same
/// guarantee the old flip panel gave for free by staying mounted under
/// `FaceView` — see `FaceScreen._stationsNotifier`.
class RosterScreen extends StatelessWidget {
  const RosterScreen({
    super.key,
    required this.stations,
    this.onScan,
    this.onExport,
  });

  final ValueListenable<List<StationInfo>> stations;

  /// FR-043/FR-044 Event QR entry points, surfaced in this screen's app bar
  /// — the roster is now the face's "flip to a secondary screen" home.
  /// `null` disables the corresponding button (e.g. no session yet).
  final VoidCallback? onScan;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KeryxTheme.shell700,
      appBar: AppBar(
        backgroundColor: KeryxTheme.shell900,
        title: const Text('Stations'),
        actions: <Widget>[
          IconButton(
            key: const Key('keryx-roster-scan'),
            tooltip: 'Scan event QR',
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            key: const Key('keryx-roster-export'),
            tooltip: 'Export event QR',
            onPressed: onExport,
            icon: const Icon(Icons.qr_code),
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<List<StationInfo>>(
          valueListenable: stations,
          builder: (context, list, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'NO OTHER STATIONS',
                      style: KeryxTheme.panelBody.copyWith(
                        color: KeryxTheme.legend.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const Key('keryx-roster-list'),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _RosterRow(station: list[index]),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({required this.station});

  final StationInfo station;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('keryx-roster-row-${station.peerId}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KeryxTheme.shell500,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              station.callsign,
              style: KeryxTheme.panelBody.copyWith(color: KeryxTheme.legend),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(9, (index) {
              final lit = index < station.signalQuality;
              return Container(
                width: 2.5,
                height: 5 + index.toDouble() * 0.7,
                margin: const EdgeInsets.only(left: 1),
                color: lit
                    ? KeryxTheme.rx
                    : KeryxTheme.legend.withValues(alpha: 0.18),
              );
            }),
          ),
        ],
      ),
    );
  }
}
