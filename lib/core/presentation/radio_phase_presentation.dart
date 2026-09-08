import 'package:keryx/core/state/radio_state.dart' show RadioPhase;

import 'presentation_cue.dart';

/// Design §4's state-presentation catalogue rows that map 1:1 onto
/// [RadioPhase] — exactly the 8 phases the reducer defines (off, boot,
/// idle, tuning, txRequest, tx, rxActive, linkDegraded), each carrying the
/// catalogue's own "Main label" copy verbatim. The remaining 5 catalogue
/// rows (Denied/busy, Latched, Emergency, Permission denied, Service
/// fault) are overlays, not phases — see `radio_view_state.dart`'s own
/// cue constants for those.
///
/// This is presentation only: it never invents a phase [RadioReducer]
/// doesn't already have, and a widget must still read [RadioViewState
/// .phase] (== `RadioState.phase`, unchanged) for the authoritative value —
/// this extension only supplies the label/icon Design §4 requires
/// alongside colour. The FR-023 TOT-warning overlay is not a phase; it
/// lives on `RadioViewState.totWarning` / `OverlayCues.totWarning`.
extension RadioPhasePresentation on RadioPhase {
  PresentationCue get cue => switch (this) {
    RadioPhase.off => const PresentationCue(
      label: 'Radio off',
      iconId: 'power_off',
    ),
    RadioPhase.boot => const PresentationCue(
      label: 'Starting radio',
      iconId: 'hourglass',
    ),
    RadioPhase.idle => const PresentationCue(
      label: 'Hold to talk',
      iconId: 'mic_none',
    ),
    RadioPhase.tuning => const PresentationCue(
      label: 'Changing channel',
      iconId: 'tune',
    ),
    RadioPhase.txRequest => const PresentationCue(
      label: 'Requesting channel',
      iconId: 'pending',
    ),
    RadioPhase.tx => const PresentationCue(
      label: 'Transmitting',
      iconId: 'mic',
    ),
    RadioPhase.rxActive => const PresentationCue(
      label: 'Receiving',
      iconId: 'volume_up',
    ),
    RadioPhase.linkDegraded => const PresentationCue(
      label: 'Connection unavailable',
      iconId: 'wifi_off',
    ),
  };
}
