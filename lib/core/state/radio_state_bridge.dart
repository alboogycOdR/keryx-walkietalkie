import 'dart:async';

import 'package:keryx/core/floor/effects.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/state/radio_state.dart';

/// One-way ingress from floor, presence, and telemetry systems into the
/// authoritative [RadioReducer]. The reducer never calls this bridge back.
///
/// Construct one bridge per [FloorEngine] and dispose it with the host. The
/// host must use this bridge, rather than separately dispatching
/// [DispatchRadio] effects, so every visible projection has one state source.
class RadioStateBridge {
  RadioStateBridge({
    required FloorEngine engine,
    required void Function(RadioEvent event) dispatch,
  }) : _engine = engine,
       _dispatch = dispatch {
    _subscription = engine.effects.listen(_onFloorEffect);
  }

  final FloorEngine _engine;
  final void Function(RadioEvent event) _dispatch;
  late final StreamSubscription<FloorEffect> _subscription;

  /// Presence feed ingress. The count includes the local station.
  void updateRoster(int stationCount) => _dispatch(RosterUpdated(stationCount));

  /// Telemetry feed ingress for the aggregate status-strip S-meter (S1–S9).
  void updateSignalQuality(int sMeter) =>
      _dispatch(SignalQualityUpdated(sMeter));

  void updatePrivateChannel(bool isPrivate) =>
      _dispatch(PrivateChannelChanged(isPrivate));
  void updateMonitor(bool isOpen) => _dispatch(MonitorChanged(isOpen));
  void updateScan(bool isActive) => _dispatch(ScanChanged(isActive));
  void updateVox(bool isArmed) => _dispatch(VoxChanged(isArmed));
  void updateReplay(bool isActive) => _dispatch(ReplayChanged(isActive));

  void _onFloorEffect(FloorEffect effect) {
    switch (effect) {
      case DispatchRadio():
        _dispatch(effect.event);
        _projectFloorEvent(effect.event);
      case EmgPinned():
        _dispatch(const EmergencyPinned());
      case EmgCleared():
        _dispatch(const EmergencyCleared());
      case ArbiterChanged():
        _dispatch(ArbiterIdentityChanged(effect.peerId));
      case DenyBuzz():
        _dispatch(const TransmitDeniedIndicated());
      case TotWarn():
        _dispatch(const TotWarningRaised());
      case TotCut():
        _dispatch(const TotWarningCleared());
      case GrantTone() || FloorIdleSettled():
        break;
    }
  }

  void _projectFloorEvent(RadioEvent event) {
    switch (event) {
      case RemoteFloorStarted():
        _dispatch(ActiveSpeakerChanged(_engine.holder));
      case RemoteFloorEnded() || EndTransmit():
        _dispatch(const ActiveSpeakerChanged(null));
      case TransmitGranted():
        _dispatch(ActiveSpeakerChanged(_engine.holder ?? _engine.localPeerId));
      case PowerOn() ||
          PowerOff() ||
          BootCompleted() ||
          BeginTuning() ||
          FinishTuning() ||
          TuneTo() ||
          SetMode() ||
          RequestTransmit() ||
          TransmitDenied() ||
          LinkDegraded() ||
          LinkResolved() ||
          EmergencyPinned() ||
          EmergencyCleared() ||
          ActiveSpeakerChanged() ||
          ArbiterIdentityChanged() ||
          RosterUpdated() ||
          SignalQualityUpdated() ||
          PrivateChannelChanged() ||
          ReplayChanged() ||
          MonitorChanged() ||
          ScanChanged() ||
          VoxChanged() ||
          TotWarningRaised() ||
          TotWarningCleared() ||
          TransmitDeniedIndicated():
        break;
    }
  }

  Future<void> dispose() => _subscription.cancel();
}
