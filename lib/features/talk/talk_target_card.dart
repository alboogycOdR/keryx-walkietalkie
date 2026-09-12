import 'package:flutter/material.dart';

import '../../core/presentation/talk_target.dart';
import '../../core/theme/ux_tokens.dart';
import 'talk_copy.dart';

/// v2 (Design §2.1) header card — replaces the v1 channel card. Purely
/// presentational: owns no directory/session state, issues no navigation of
/// its own beyond forwarding the caller-supplied callbacks (same contract
/// the v1 `TalkChannelCard` followed).
///
/// Rendered only when a [TalkTarget] is selected; [TalkNoTargetCard] below
/// covers the no-target state (Design §2.1 "the ring is replaced by a
/// card...").
class TalkTargetCard extends StatelessWidget {
  const TalkTargetCard({
    super.key,
    required this.target,
    required this.presenceLine,
    this.ownStatus,
    this.onSetOwnStatus,
    this.onOpenTargetDetail,
    this.onOpenPicker,
    this.onOpenStations,
  });

  final TalkTarget target;

  /// Design §2.1's presence line — e.g. "Ben · Available" or
  /// "Site crew · 4 of 12 online". Composed by the caller (this widget does
  /// not itself own a presence policy).
  final String presenceLine;

  /// The local user's own status, shown on the status control. `null`
  /// disables the control (matching the null-callback-disables convention
  /// used throughout this feature).
  final PeerPresence? ownStatus;

  final ValueChanged<PeerPresence>? onSetOwnStatus;

  /// Opens the target's detail sheet (Design §2.1's chevron). `null` renders
  /// the chevron disabled rather than throwing on tap.
  final VoidCallback? onOpenTargetDetail;

  /// v1 leftover, unused by Design §2.1's own layout — retained purely so
  /// `lib/app_shell/**` (TASK-093's territory, not yet rewired to the v2
  /// Contacts/Groups tabs) still has real buttons to drive its own
  /// interaction/layout/golden tests against until that task removes them.
  final VoidCallback? onOpenPicker;

  /// v1 leftover; see [onOpenPicker]'s dartdoc.
  final VoidCallback? onOpenStations;

  static String _avatarGlyph(TalkTarget target) {
    if (target.kind == TalkTargetKind.group) return 'G';
    final trimmed = target.name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  static String _statusLabel(PeerPresence status) => switch (status) {
    PeerPresence.online => 'Available',
    PeerPresence.busy => 'Busy',
    PeerPresence.dnd => 'Do Not Disturb',
    PeerPresence.offline => 'Appear offline',
  };

  static IconData _statusIcon(PeerPresence status) => switch (status) {
    PeerPresence.online => Icons.circle,
    PeerPresence.busy => Icons.circle,
    PeerPresence.dnd => Icons.nightlight_round,
    PeerPresence.offline => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Container(
      key: const Key('keryx-talk-channel-card'),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Text(
              _avatarGlyph(target),
              key: const Key('keryx-talk-target-avatar'),
              style: KeryxUxTypography.sectionTitle.copyWith(
                color: tokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  target.name,
                  key: const Key('keryx-talk-target-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KeryxUxTypography.body.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  presenceLine,
                  key: const Key('keryx-talk-target-presence'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KeryxUxTypography.compact.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (ownStatus != null)
            SizedBox(
              height: 48,
              child: PopupMenuButton<PeerPresence>(
                key: const Key('keryx-talk-own-status'),
                tooltip: TalkCopy.ownStatus,
                initialValue: ownStatus,
                enabled: onSetOwnStatus != null,
                onSelected: onSetOwnStatus,
                itemBuilder: (context) => PeerPresence.values
                    .map(
                      (status) => PopupMenuItem<PeerPresence>(
                        value: status,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(_statusIcon(status), size: 16),
                            const SizedBox(width: 8),
                            Text(_statusLabel(status)),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _statusIcon(ownStatus!),
                      size: 12,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: tokens.textSecondary),
                  ],
                ),
              ),
            ),
          if (onOpenPicker != null)
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                key: const Key('keryx-talk-picker'),
                onPressed: onOpenPicker,
                icon: Icon(Icons.dialpad, color: tokens.textSecondary),
              ),
            ),
          if (onOpenStations != null)
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                key: const Key('keryx-talk-stations'),
                onPressed: onOpenStations,
                icon: Icon(Icons.groups_outlined, color: tokens.textSecondary),
              ),
            ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              key: const Key('keryx-talk-target-detail'),
              tooltip: TalkCopy.openTargetDetail,
              onPressed: onOpenTargetDetail,
              icon: Icon(Icons.chevron_right, color: tokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Design §2.1's no-target state: replaces the header card and the PTT ring
/// alike with two entry points onto Contacts/Groups. Rendered by
/// [TalkScreen] instead of both [TalkTargetCard] and `TalkPttRing` — the
/// screen has "no target" as a whole, not a target-less ring.
class TalkNoTargetCard extends StatelessWidget {
  const TalkNoTargetCard({
    super.key,
    this.onAddContact,
    this.onCreateGroup,
    this.onOpenPicker,
    this.onOpenStations,
  });

  final VoidCallback? onAddContact;
  final VoidCallback? onCreateGroup;

  /// v1 leftover; see [TalkTargetCard.onOpenPicker]'s dartdoc.
  final VoidCallback? onOpenPicker;

  /// v1 leftover; see [TalkTargetCard.onOpenPicker]'s dartdoc.
  final VoidCallback? onOpenStations;

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Container(
      // Shares the legacy `keryx-talk-channel-card` key with
      // [TalkTargetCard] — the two are mutually exclusive branches of the
      // same header-card slot (never mounted simultaneously), and
      // `test/regression/layout_matrix_test.dart` (TASK-093's territory,
      // not yet rewired to pass a real target) locates "the header card"
      // by this key regardless of which state it's in.
      key: const Key('keryx-talk-channel-card'),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onOpenPicker != null || onOpenStations != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (onOpenPicker != null)
                  IconButton(
                    key: const Key('keryx-talk-picker'),
                    onPressed: onOpenPicker,
                    icon: Icon(Icons.dialpad, color: tokens.textSecondary),
                  ),
                if (onOpenStations != null)
                  IconButton(
                    key: const Key('keryx-talk-stations'),
                    onPressed: onOpenStations,
                    icon: Icon(
                      Icons.groups_outlined,
                      color: tokens.textSecondary,
                    ),
                  ),
              ],
            ),
          Icon(Icons.person_add_alt, size: 40, color: tokens.textSecondary),
          const SizedBox(height: 12),
          Text(
            TalkCopy.noTargetHeadline,
            textAlign: TextAlign.center,
            style: KeryxUxTypography.sectionTitle.copyWith(
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('keryx-talk-add-contact'),
            onPressed: onAddContact,
            child: const Text(TalkCopy.addFirstContact),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('keryx-talk-create-group'),
            onPressed: onCreateGroup,
            child: const Text(TalkCopy.createAGroup),
          ),
        ],
      ),
    );
  }
}
