import 'package:flutter/material.dart';
import 'package:keryx/core/settings/settings_repository.dart' show TunedChannel;
import 'package:keryx/core/theme/theme.dart';

/// Long-press-CH▼ channel-memory quick-recall surface (FR-009).
///
/// Reuses TASK-008's `TunedChannel` value type directly (`lib/core/settings/`,
/// frozen) — a plain, immutable data class, imported read-only, not a
/// dependency on that territory's storage/Riverpod machinery. Per the task
/// dossier: "list injected; persistence is TASK-008's" — this widget never
/// reads or writes the settings repository itself, it only renders whatever
/// [entries] its caller (TASK-017) supplies.
///
/// Same "in-world, not a Material dialog" resolution as [KeypadSheet]
/// (DS §6 "No state may use a dialog, toast, or snackbar (P1)") — presented
/// via [showChannelRecallPanel] as a stripped-chrome `showModalBottomSheet`.
/// PT implements no channel memory at all (grep-confirmed absent), so this
/// is again a disclosed engineering resolution, non-blocking.
class ChannelRecallPanel extends StatelessWidget {
  const ChannelRecallPanel({
    super.key,
    required this.entries,
    required this.onSelect,
    this.onDismiss,
  });

  /// Up to `TASK-008`'s `channelMemoryCapacity` (6) most-recently-tuned
  /// channels, most-recent first. An empty list renders an in-world empty
  /// state, never an error.
  final List<TunedChannel> entries;

  /// Fired when the user taps a memory row.
  final ValueChanged<TunedChannel> onSelect;

  /// Fired when the panel is dismissed without a selection.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('keryx-channel-recall'),
      padding: EdgeInsets.only(
        left: KeryxTheme.grid * 2,
        right: KeryxTheme.grid * 2,
        top: KeryxTheme.grid * 2,
        bottom: KeryxTheme.grid * 2 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: KeryxTheme.shell700,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 16),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'CHANNEL MEMORY',
            style: KeryxTheme.legendLabel.copyWith(color: KeryxTheme.legend),
          ),
          SizedBox(height: KeryxTheme.grid * 2),
          if (entries.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: KeryxTheme.grid * 2),
              child: Text(
                'No channels remembered yet.',
                style: KeryxTheme.panelBody.copyWith(color: KeryxTheme.legend),
              ),
            )
          else
            ...entries.map(
              (entry) => _RecallRow(
                entry: entry,
                onTap: () => onSelect(entry),
              ),
            ),
          SizedBox(height: KeryxTheme.grid),
          TextButton(
            key: const Key('keryx-recall-dismiss'),
            onPressed: () {
              onDismiss?.call();
              Navigator.of(context).maybePop();
            },
            child: Text(
              'DISMISS',
              style: KeryxTheme.legendLabel.copyWith(color: KeryxTheme.legend),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecallRow extends StatelessWidget {
  const _RecallRow({required this.entry, required this.onTap});

  final TunedChannel entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label =
        'CH ${entry.channel.toString().padLeft(2, '0')} '
        '· ${entry.privacyCode.toString().padLeft(2, '0')}';
    return Semantics(
      button: true,
      label: 'Recall $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(vertical: KeryxTheme.grid),
            child: Text(
              label,
              style: KeryxTheme.glassSecondary.copyWith(
                color: KeryxTheme.lcd,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Presents [ChannelRecallPanel] as an in-world bottom sheet (see class
/// dartdoc). Intended caller: TASK-017, wired to `ChStepperButton`'s
/// `onLongPress` on the CH▼ instance.
Future<void> showChannelRecallPanel(
  BuildContext context, {
  required List<TunedChannel> entries,
  required ValueChanged<TunedChannel> onSelect,
  VoidCallback? onDismiss,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.6),
    isScrollControlled: true,
    builder: (sheetContext) => ChannelRecallPanel(
      entries: entries,
      onSelect: (entry) {
        onSelect(entry);
        Navigator.of(sheetContext).maybePop();
      },
      onDismiss: onDismiss,
    ),
  );
}
