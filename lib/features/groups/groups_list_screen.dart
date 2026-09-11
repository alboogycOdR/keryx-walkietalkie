import 'package:flutter/material.dart';

import '../../core/theme/ux_tokens.dart';
import 'group_view_models.dart';
import 'groups_copy.dart';

/// The Groups tab body (Design §2.3): rows of glyph/name/"n online · m
/// members"; tap selects the group as the Talk target, chevron opens
/// detail. Purely presentational — owns no store, only renders [rows] and
/// forwards callbacks (matches `TalkChannelCard`'s convention).
class GroupsListScreen extends StatelessWidget {
  const GroupsListScreen({
    super.key,
    required this.rows,
    this.onSelectTarget,
    this.onOpenDetail,
    this.onNewGroup,
    this.onJoinWithCode,
  });

  final List<GroupListRow> rows;

  /// Row tap — Design §2.3: "Tap → Talk with this target."
  final void Function(GroupListRow row)? onSelectTarget;

  /// Chevron tap — opens group detail.
  final void Function(GroupListRow row)? onOpenDetail;

  final VoidCallback? onNewGroup;
  final VoidCallback? onJoinWithCode;

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      body: rows.isEmpty ? _EmptyState(tokens: tokens) : _GroupsList(rows: rows, tokens: tokens, onSelectTarget: onSelectTarget, onOpenDetail: onOpenDetail),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            key: const Key('keryx-groups-join-with-code'),
            heroTag: 'keryx-groups-join-with-code',
            onPressed: onJoinWithCode,
            label: const Text(GroupsCopy.joinWithCodeAction),
            icon: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            key: const Key('keryx-groups-new'),
            heroTag: 'keryx-groups-new',
            onPressed: onNewGroup,
            label: const Text(GroupsCopy.newGroupAction),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tokens});
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('keryx-groups-empty'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 48, color: tokens.textSecondary),
            const SizedBox(height: 12),
            Text(
              GroupsCopy.emptyStateTitle,
              style: KeryxUxTypography.sectionTitle.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              GroupsCopy.emptyStateBody,
              textAlign: TextAlign.center,
              style: KeryxUxTypography.body.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupsList extends StatelessWidget {
  const _GroupsList({required this.rows, required this.tokens, this.onSelectTarget, this.onOpenDetail});
  final List<GroupListRow> rows;
  final KeryxUxTokens tokens;
  final void Function(GroupListRow row)? onSelectTarget;
  final void Function(GroupListRow row)? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('keryx-groups-list'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        return _GroupRow(
          key: Key('keryx-groups-row-${row.id}'),
          row: row,
          tokens: tokens,
          onTap: onSelectTarget == null ? null : () => onSelectTarget!(row),
          onChevron: onOpenDetail == null ? null : () => onOpenDetail!(row),
        );
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({super.key, required this.row, required this.tokens, this.onTap, this.onChevron});
  final GroupListRow row;
  final KeryxUxTokens tokens;
  final VoidCallback? onTap;
  final VoidCallback? onChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: tokens.surfaceRaised,
                child: Text(row.glyph, style: TextStyle(color: tokens.textPrimary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.name,
                      key: Key('keryx-groups-row-name-${row.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      GroupsCopy.memberCountLabel(online: row.onlineCount, total: row.totalCount),
                      key: Key('keryx-groups-row-count-${row.id}'),
                      style: KeryxUxTypography.compact.copyWith(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: Key('keryx-groups-row-chevron-${row.id}'),
                onPressed: onChevron,
                icon: Icon(Icons.chevron_right, color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
