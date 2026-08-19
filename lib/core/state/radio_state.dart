/// The only lifecycle state for the radio. External systems project from this
/// value; they do not mutate it directly.
enum RadioPhase {
  off,
  boot,
  idle,
  tuning,
  txRequest,
  tx,
  rxActive,
  linkDegraded,
}

/// Routing preference selected by the user. AUTO is the product default.
enum RadioMode { local, auto, linked }

/// Immutable state owned by [RadioReducer].
class RadioState {
  const RadioState({
    required this.phase,
    this.mode = RadioMode.auto,
    this.channel = 1,
    this.privacyCode = 0,
    this.isNoLink = false,
    this.isEmergency = false,
    this.isPrivate = false,
    this.isReplay = false,
    this.isMonitorOpen = false,
    this.isScanning = false,
    this.isVoxArmed = false,
    this.stationCount = 0,
    this.activeSpeaker,
    this.arbiterId,
    this.signalQuality = minimumSignalQuality,
  }) : assert(channel >= minimumChannel && channel <= maximumChannel),
       assert(
         privacyCode >= minimumPrivacyCode && privacyCode <= maximumPrivacyCode,
       ),
       assert(stationCount >= 0),
       assert(
         signalQuality >= minimumSignalQuality &&
             signalQuality <= maximumSignalQuality,
       );

  static const int minimumChannel = 1;
  static const int maximumChannel = 99;
  static const int minimumPrivacyCode = 0;
  static const int maximumPrivacyCode = 38;
  static const int minimumSignalQuality = 1;
  static const int maximumSignalQuality = 9;

  const RadioState.off()
    : phase = RadioPhase.off,
      mode = RadioMode.auto,
      channel = minimumChannel,
      privacyCode = minimumPrivacyCode,
      isNoLink = false,
      isEmergency = false,
      isPrivate = false,
      isReplay = false,
      isMonitorOpen = false,
      isScanning = false,
      isVoxArmed = false,
      stationCount = 0,
      activeSpeaker = null,
      arbiterId = null,
      signalQuality = minimumSignalQuality;

  final RadioPhase phase;
  final RadioMode mode;
  final int channel;
  final int privacyCode;
  final bool isNoLink;
  final bool isEmergency;
  final bool isPrivate;
  final bool isReplay;
  final bool isMonitorOpen;
  final bool isScanning;
  final bool isVoxArmed;
  final int stationCount;
  final String? activeSpeaker;
  final String? arbiterId;
  final int signalQuality;

  RadioState copyWith({
    RadioPhase? phase,
    RadioMode? mode,
    int? channel,
    int? privacyCode,
    bool? isNoLink,
    bool? isEmergency,
    bool? isPrivate,
    bool? isReplay,
    bool? isMonitorOpen,
    bool? isScanning,
    bool? isVoxArmed,
    int? stationCount,
    String? activeSpeaker,
    bool clearActiveSpeaker = false,
    String? arbiterId,
    bool clearArbiterId = false,
    int? signalQuality,
  }) => RadioState(
    phase: phase ?? this.phase,
    mode: mode ?? this.mode,
    channel: channel ?? this.channel,
    privacyCode: privacyCode ?? this.privacyCode,
    isNoLink: isNoLink ?? this.isNoLink,
    isEmergency: isEmergency ?? this.isEmergency,
    isPrivate: isPrivate ?? this.isPrivate,
    isReplay: isReplay ?? this.isReplay,
    isMonitorOpen: isMonitorOpen ?? this.isMonitorOpen,
    isScanning: isScanning ?? this.isScanning,
    isVoxArmed: isVoxArmed ?? this.isVoxArmed,
    stationCount: stationCount ?? this.stationCount,
    activeSpeaker: clearActiveSpeaker
        ? null
        : activeSpeaker ?? this.activeSpeaker,
    arbiterId: clearArbiterId ? null : arbiterId ?? this.arbiterId,
    signalQuality: signalQuality ?? this.signalQuality,
  );

  @override
  bool operator ==(Object other) =>
      other is RadioState &&
      phase == other.phase &&
      mode == other.mode &&
      channel == other.channel &&
      privacyCode == other.privacyCode &&
      isNoLink == other.isNoLink &&
      isEmergency == other.isEmergency &&
      isPrivate == other.isPrivate &&
      isReplay == other.isReplay &&
      isMonitorOpen == other.isMonitorOpen &&
      isScanning == other.isScanning &&
      isVoxArmed == other.isVoxArmed &&
      stationCount == other.stationCount &&
      activeSpeaker == other.activeSpeaker &&
      arbiterId == other.arbiterId &&
      signalQuality == other.signalQuality;

  @override
  int get hashCode => Object.hashAll([
    phase,
    mode,
    channel,
    privacyCode,
    isNoLink,
    isEmergency,
    isPrivate,
    isReplay,
    isMonitorOpen,
    isScanning,
    isVoxArmed,
    stationCount,
    activeSpeaker,
    arbiterId,
    signalQuality,
  ]);

  @override
  String toString() =>
      'RadioState(phase: $phase, mode: $mode, channel: $channel, '
      'privacyCode: $privacyCode, stationCount: $stationCount, '
      'activeSpeaker: $activeSpeaker, signalQuality: $signalQuality)';
}

/// Inputs accepted by the pure [RadioReducer].
sealed class RadioEvent {
  const RadioEvent();
}

class PowerOn extends RadioEvent {
  const PowerOn();
}

class PowerOff extends RadioEvent {
  const PowerOff();
}

class BootCompleted extends RadioEvent {
  const BootCompleted();
}

class BeginTuning extends RadioEvent {
  const BeginTuning();
}

class FinishTuning extends RadioEvent {
  const FinishTuning();
}

class TuneTo extends RadioEvent {
  const TuneTo({required this.channel, required this.privacyCode});
  final int channel;
  final int privacyCode;
}

class SetMode extends RadioEvent {
  const SetMode(this.mode);
  final RadioMode mode;
}

class RequestTransmit extends RadioEvent {
  const RequestTransmit();
}

class TransmitGranted extends RadioEvent {
  const TransmitGranted();
}

class TransmitDenied extends RadioEvent {
  const TransmitDenied();
}

class EndTransmit extends RadioEvent {
  const EndTransmit();
}

class RemoteFloorStarted extends RadioEvent {
  const RemoteFloorStarted();
}

class RemoteFloorEnded extends RadioEvent {
  const RemoteFloorEnded();
}

/// Enter the visible degradation state while the radio is powered on.
class LinkDegraded extends RadioEvent {
  const LinkDegraded();
}

/// Leave degradation at idle. A local fallback gives up the LINKED route.
class LinkResolved extends RadioEvent {
  const LinkResolved({this.useLocalFallback = false});
  final bool useLocalFallback;
}

class EmergencyPinned extends RadioEvent {
  const EmergencyPinned();
}

class EmergencyCleared extends RadioEvent {
  const EmergencyCleared();
}

/// Identity of the station currently holding the floor, or `null` when no
/// station is transmitting/receiving.
///
/// This carries a **peerId**, not a display callsign — the bridge feeds it
/// `FloorEngine.holder`/`localPeerId` (raw peer identifiers). Mapping a
/// peerId to a human-readable callsign is TASK-009's `displayNames` roster,
/// applied downstream by the UI layer (TASK-017); this reducer does not
/// perform that mapping and must not, since it has no roster to consult.
class ActiveSpeakerChanged extends RadioEvent {
  const ActiveSpeakerChanged(this.speaker);
  final String? speaker;
}

class ArbiterIdentityChanged extends RadioEvent {
  const ArbiterIdentityChanged(this.peerId);
  final String? peerId;
}

class RosterUpdated extends RadioEvent {
  const RosterUpdated(this.stationCount);
  final int stationCount;
}

class SignalQualityUpdated extends RadioEvent {
  const SignalQualityUpdated(this.sMeter);
  final int sMeter;
}

class PrivateChannelChanged extends RadioEvent {
  const PrivateChannelChanged(this.isPrivate);
  final bool isPrivate;
}

class ReplayChanged extends RadioEvent {
  const ReplayChanged(this.isActive);
  final bool isActive;
}

class MonitorChanged extends RadioEvent {
  const MonitorChanged(this.isOpen);
  final bool isOpen;
}

class ScanChanged extends RadioEvent {
  const ScanChanged(this.isActive);
  final bool isActive;
}

class VoxChanged extends RadioEvent {
  const VoxChanged(this.isArmed);
  final bool isArmed;
}

/// Authoritative, side-effect-free radio transition function.
class RadioReducer {
  const RadioReducer();

  RadioState reduce(RadioState state, RadioEvent event) => switch (event) {
    PowerOff() => state.copyWith(
      phase: RadioPhase.off,
      isNoLink: false,
      isReplay: false,
      clearActiveSpeaker: true,
    ),
    PowerOn() =>
      state.phase == RadioPhase.off
          ? state.copyWith(phase: RadioPhase.boot)
          : state,
    BootCompleted() =>
      state.phase == RadioPhase.boot
          ? state.copyWith(phase: RadioPhase.idle)
          : state,
    BeginTuning() =>
      state.phase == RadioPhase.idle
          ? state.copyWith(phase: RadioPhase.tuning)
          : state,
    FinishTuning() =>
      state.phase == RadioPhase.tuning
          ? state.copyWith(phase: RadioPhase.idle)
          : state,
    TuneTo() =>
      _isValidTuning(event)
          ? state.copyWith(
              channel: event.channel,
              privacyCode: event.privacyCode,
              isReplay:
                  event.channel == state.channel &&
                      event.privacyCode == state.privacyCode
                  ? state.isReplay
                  : false,
            )
          : state,
    SetMode() =>
      state.phase == RadioPhase.idle ? state.copyWith(mode: event.mode) : state,
    RequestTransmit() =>
      state.phase == RadioPhase.idle
          ? state.copyWith(phase: RadioPhase.txRequest)
          : state,
    TransmitGranted() =>
      state.phase == RadioPhase.txRequest
          ? state.copyWith(phase: RadioPhase.tx)
          : state,
    TransmitDenied() =>
      state.phase == RadioPhase.txRequest
          ? state.copyWith(phase: RadioPhase.idle)
          : state,
    EndTransmit() =>
      state.phase == RadioPhase.tx
          ? state.copyWith(phase: RadioPhase.idle)
          : state,
    RemoteFloorStarted() =>
      state.phase == RadioPhase.idle
          ? state.copyWith(phase: RadioPhase.rxActive)
          : state,
    RemoteFloorEnded() =>
      state.phase == RadioPhase.rxActive
          ? state.copyWith(phase: RadioPhase.idle)
          : state,
    LinkDegraded() =>
      state.phase != RadioPhase.off
          ? state.copyWith(phase: RadioPhase.linkDegraded, isNoLink: true)
          : state,
    LinkResolved() =>
      state.phase == RadioPhase.linkDegraded
          ? state.copyWith(
              phase: RadioPhase.idle,
              mode: event.useLocalFallback ? RadioMode.local : state.mode,
              isNoLink: false,
            )
          : state,
    EmergencyPinned() => state.copyWith(isEmergency: true),
    EmergencyCleared() => state.copyWith(isEmergency: false),
    ActiveSpeakerChanged() => state.copyWith(
      activeSpeaker: event.speaker,
      clearActiveSpeaker: event.speaker == null,
    ),
    ArbiterIdentityChanged() => state.copyWith(
      arbiterId: event.peerId,
      clearArbiterId: event.peerId == null,
    ),
    RosterUpdated() =>
      event.stationCount >= 0
          ? state.copyWith(stationCount: event.stationCount)
          : state,
    SignalQualityUpdated() =>
      _isValidSignalQuality(event.sMeter)
          ? state.copyWith(signalQuality: event.sMeter)
          : state,
    PrivateChannelChanged() => state.copyWith(isPrivate: event.isPrivate),
    ReplayChanged() => state.copyWith(isReplay: event.isActive),
    MonitorChanged() => state.copyWith(isMonitorOpen: event.isOpen),
    ScanChanged() => state.copyWith(isScanning: event.isActive),
    VoxChanged() => state.copyWith(isVoxArmed: event.isArmed),
  };

  bool _isValidTuning(TuneTo event) =>
      event.channel >= RadioState.minimumChannel &&
      event.channel <= RadioState.maximumChannel &&
      event.privacyCode >= RadioState.minimumPrivacyCode &&
      event.privacyCode <= RadioState.maximumPrivacyCode;

  bool _isValidSignalQuality(int value) =>
      value >= RadioState.minimumSignalQuality &&
      value <= RadioState.maximumSignalQuality;
}
