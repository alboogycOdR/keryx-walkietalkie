import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/theme.dart';

import 'settings_copy.dart';
import 'widgets/panel_picker_row.dart';
import 'widgets/panel_section.dart';
import 'widgets/panel_stepper_row.dart';
import 'widgets/panel_text_row.dart';
import 'widgets/panel_toggle_row.dart';

/// Route name a host may register for [BackPanelScreen], invoked from the
/// face's `⚙` key (`PttSecondaryKey.settings` /
/// `lib/features/ptt/key_row.dart`'s `onSettings` callback). Wiring
/// `onSettings` in `lib/features/face/face_screen.dart` to actually
/// navigate here is host-level plumbing outside `lib/features/settings_panel/**`
/// — the same convention TASK-017/024 established for their own host-wiring
/// gaps — so this stays a named constant for the host to consume rather
/// than a `Navigator.push` call made from inside this screen.
const String backPanelRouteName = '/settings';

/// FR-100: "Settings rendered as the radio's back panel / battery-hatch
/// screen — even configuration stays in-world (P1)." Every control below
/// round-trips through [settingsProvider] / [SettingsRepository]
/// (TASK-008/030) — nothing here holds its own source of truth, and every
/// write re-renders live because `settingsProvider` is an [AsyncNotifier]
/// that re-emits after `save()` on the same repository instance.
class BackPanelScreen extends ConsumerWidget {
  const BackPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: KeryxTheme.shell900,
      appBar: AppBar(
        backgroundColor: KeryxTheme.shell700,
        foregroundColor: KeryxTheme.legend,
        title: Text(
          SettingsCopy.screenTitle,
          style: KeryxTheme.legendLabel.copyWith(color: KeryxTheme.legend),
        ),
      ),
      body: settingsAsync.when(
        data: (settings) => _BackPanelBody(
          settings: settings,
          onChanged: (next) => unawaited(_save(controller, next)),
        ),
        loading: () => Center(
          child: CircularProgressIndicator(color: KeryxTheme.lcd),
        ),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              SettingsCopy.loadFailed,
              style: KeryxTheme.panelBody.copyWith(color: KeryxTheme.legend),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fire-and-forget from a synchronous control callback, but never silent:
/// a rejected write (e.g. storage failure) is logged rather than lost,
/// same pattern `SettingsRepository.load()` uses for a corrupt read.
Future<void> _save(SettingsController controller, KeryxSettings next) async {
  try {
    await controller.save(next);
  } on Object catch (error, stackTrace) {
    developer.log(
      'Failed to save a back-panel setting change.',
      name: 'keryx.settings_panel',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _BackPanelBody extends StatelessWidget {
  const _BackPanelBody({required this.settings, required this.onChanged});

  final KeryxSettings settings;
  final ValueChanged<KeryxSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(KeryxTheme.grid * 2),
      children: [
        PanelSection(
          title: SettingsCopy.audioSectionTitle,
          children: [
            PanelStepperRow(
              key: const ValueKey<String>('settings-squelch'),
              label: SettingsCopy.squelchLabel,
              description: SettingsCopy.squelchDescription,
              value: settings.squelchLevel,
              min: KeryxSettings.squelchLevelMin,
              max: KeryxSettings.squelchLevelMax,
              step: 1,
              valueLabel: (v) => '$v',
              onChanged: (v) => onChanged(settings.copyWith(squelchLevel: v)),
            ),
            PanelPickerRow<RogerBeepVariant>(
              key: const ValueKey<String>('settings-roger'),
              label: SettingsCopy.rogerLabel,
              description: SettingsCopy.rogerDescription,
              value: settings.rogerBeep,
              options: RogerBeepVariant.values,
              optionLabel: SettingsCopy.rogerOptionLabel,
              onChanged: (v) => onChanged(settings.copyWith(rogerBeep: v)),
            ),
          ],
        ),
        PanelSection(
          title: SettingsCopy.txSectionTitle,
          children: [
            PanelStepperRow(
              key: const ValueKey<String>('settings-tot'),
              label: SettingsCopy.totLabel,
              description: SettingsCopy.totDescription,
              value: settings.totSeconds,
              min: KeryxSettings.totSecondsMin,
              max: KeryxSettings.totSecondsMax,
              step: 5,
              valueLabel: (v) => '${v}s',
              onChanged: (v) => onChanged(settings.copyWith(totSeconds: v)),
            ),
            PanelToggleRow(
              key: const ValueKey<String>('settings-latch'),
              label: SettingsCopy.latchLabel,
              description: SettingsCopy.latchDescription,
              value: settings.latchMode,
              onChanged: (v) => onChanged(settings.copyWith(latchMode: v)),
            ),
            PanelToggleRow(
              key: const ValueKey<String>('settings-lockout'),
              label: SettingsCopy.lockoutLabel,
              description: SettingsCopy.lockoutDescription,
              value: settings.busyLockout,
              onChanged: (v) => onChanged(settings.copyWith(busyLockout: v)),
            ),
          ],
        ),
        PanelSection(
          title: SettingsCopy.characterSectionTitle,
          children: [
            PanelPickerRow<CharacterDspIntensity>(
              key: const ValueKey<String>('settings-dsp'),
              label: SettingsCopy.dspLabel,
              description: SettingsCopy.dspDescription,
              value: settings.characterDspIntensity,
              options: CharacterDspIntensity.values,
              optionLabel: SettingsCopy.dspOptionLabel,
              onChanged: (v) =>
                  onChanged(settings.copyWith(characterDspIntensity: v)),
            ),
            PanelPickerRow<DimMode>(
              key: const ValueKey<String>('settings-dim'),
              label: SettingsCopy.dimLabel,
              description: SettingsCopy.dimDescription,
              value: settings.dimMode,
              options: DimMode.values,
              optionLabel: SettingsCopy.dimOptionLabel,
              onChanged: (v) => onChanged(settings.copyWith(dimMode: v)),
            ),
          ],
        ),
        PanelSection(
          title: SettingsCopy.networkSectionTitle,
          children: [
            PanelToggleRow(
              key: const ValueKey<String>('settings-force-local'),
              label: SettingsCopy.forceLocalLabel,
              description: SettingsCopy.forceLocalDescription,
              value: settings.forceLocalOnly,
              onChanged: (v) =>
                  onChanged(settings.copyWith(forceLocalOnly: v)),
            ),
            PanelTextRow(
              key: const ValueKey<String>('settings-region'),
              label: SettingsCopy.regionLabel,
              description: SettingsCopy.regionDescription,
              value: settings.region,
              onChanged: (v) => onChanged(settings.copyWith(region: v)),
            ),
          ],
        ),
      ],
    );
  }
}
