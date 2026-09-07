import 'package:flutter/material.dart';

/// Resolves TASK-046 [PresentationCue.iconId] values to the Material icon
/// family (Design §3.4). Colour stays on [KeryxUxTokens] — this map is
/// glyphs only, so a state is never colour-alone (UX-FR-022).
IconData iconForPresentation(String iconId) {
  return switch (iconId) {
    'power_off' => Icons.power_settings_new,
    'hourglass' => Icons.hourglass_empty,
    'mic_none' => Icons.mic_none,
    'tune' => Icons.tune,
    'pending' => Icons.hourglass_top,
    'mic' => Icons.mic,
    'volume_up' => Icons.volume_up,
    'wifi_off' => Icons.wifi_off_outlined,
    'block' => Icons.block,
    'lock' => Icons.lock_outline,
    'warning' => Icons.warning_amber_outlined,
    'mic_off' => Icons.mic_off_outlined,
    'error' => Icons.error_outline,
    _ => Icons.info_outline,
  };
}
