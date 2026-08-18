import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }) : assert(channel >= minimumChannel && channel <= maximumChannel),
       assert(
         privacyCode >= minimumPrivacyCode && privacyCode <= maximumPrivacyCode,
       );

  static const int minimumChannel = 1;
  static const int maximumChannel = 99;
  static const int minimumPrivacyCode = 0;
  static const int maximumPrivacyCode = 38;

  const RadioState.off()
    : phase = RadioPhase.off,
      mode = RadioMode.auto,
      channel = minimumChannel,
      privacyCode = minimumPrivacyCode;

  final RadioPhase phase;
  final RadioMode mode;
  final int channel;
  final int privacyCode;

  RadioState copyWith({
    RadioPhase? phase,
    RadioMode? mode,
    int? channel,
    int? privacyCode,
  }) => RadioState(
    phase: phase ?? this.phase,
    mode: mode ?? this.mode,
    channel: channel ?? this.channel,
    privacyCode: privacyCode ?? this.privacyCode,
  );

  @override
  bool operator ==(Object other) =>
      other is RadioState &&
      phase == other.phase &&
      mode == other.mode &&
      channel == other.channel &&
      privacyCode == other.privacyCode;

  @override
  int get hashCode => Object.hash(phase, mode, channel, privacyCode);

  @override
  String toString() =>
      'RadioState(phase: $phase, mode: $mode, channel: $channel, '
      'privacyCode: $privacyCode)';
}

/// Inputs accepted by the pure [RadioReducer].
sealed class RadioEvent {
  const RadioEvent();
}

class PowerOn extends RadioEvent {
  const PowerOn();
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

/// Enter the visible degradation state. It may be sent from every phase.
class LinkDegraded extends RadioEvent {
  const LinkDegraded();
}

/// Leave degradation at idle. A fallback forces LOCAL routing without a modal.
class LinkRecovered extends RadioEvent {
  const LinkRecovered({this.fallbackToLocal = false});

  final bool fallbackToLocal;
}

/// Authoritative, side-effect-free radio transition function.
class RadioReducer {
  const RadioReducer();

  RadioState reduce(RadioState state, RadioEvent event) {
    if (event is LinkDegraded) {
      return state.copyWith(phase: RadioPhase.linkDegraded);
    }
    if (event is PowerOn) {
      return state.phase == RadioPhase.off
          ? state.copyWith(phase: RadioPhase.boot)
          : state;
    }
    if (event is BootCompleted) {
      return state.phase == RadioPhase.boot
          ? state.copyWith(phase: RadioPhase.idle)
          : state;
    }
    if (event is BeginTuning) {
      return state.phase == RadioPhase.idle
          ? state.copyWith(phase: RadioPhase.tuning)
          : state;
    }
    if (event is FinishTuning) {
      return state.phase == RadioPhase.tuning
          ? state.copyWith(phase: RadioPhase.idle)
          : state;
    }
    if (event is TuneTo) {
      return _isValidTuning(event)
          ? state.copyWith(
              channel: event.channel,
              privacyCode: event.privacyCode,
            )
          : state;
    }
    if (event is SetMode) {
      return state.copyWith(mode: event.mode);
    }
    if (event is RequestTransmit) {
      return state.phase == RadioPhase.idle
          ? state.copyWith(phase: RadioPhase.txRequest)
          : state;
    }
    if (event is TransmitGranted) {
      return state.phase == RadioPhase.txRequest
          ? state.copyWith(phase: RadioPhase.tx)
          : state;
    }
    if (event is TransmitDenied) {
      return state.phase == RadioPhase.txRequest
          ? state.copyWith(phase: RadioPhase.idle)
          : state;
    }
    if (event is EndTransmit) {
      return state.phase == RadioPhase.tx
          ? state.copyWith(phase: RadioPhase.idle)
          : state;
    }
    if (event is RemoteFloorStarted) {
      return state.phase == RadioPhase.idle
          ? state.copyWith(phase: RadioPhase.rxActive)
          : state;
    }
    if (event is RemoteFloorEnded) {
      return state.phase == RadioPhase.rxActive
          ? state.copyWith(phase: RadioPhase.idle)
          : state;
    }
    if (event is LinkRecovered) {
      return state.phase == RadioPhase.linkDegraded
          ? state.copyWith(
              phase: RadioPhase.idle,
              mode: event.fallbackToLocal ? RadioMode.local : state.mode,
            )
          : state;
    }
    return state;
  }

  bool _isValidTuning(TuneTo event) =>
      event.channel >= RadioState.minimumChannel &&
      event.channel <= RadioState.maximumChannel &&
      event.privacyCode >= RadioState.minimumPrivacyCode &&
      event.privacyCode <= RadioState.maximumPrivacyCode;
}

/// Riverpod host for the reducer. It introduces no state transitions of its own.
class RadioStateController extends StateNotifier<RadioState> {
  RadioStateController(this._reducer) : super(const RadioState.off());

  final RadioReducer _reducer;

  void dispatch(RadioEvent event) => state = _reducer.reduce(state, event);
}

final radioReducerProvider = Provider<RadioReducer>(
  (ref) => const RadioReducer(),
);

final radioStateProvider =
    StateNotifierProvider<RadioStateController, RadioState>((ref) {
      return RadioStateController(ref.watch(radioReducerProvider));
    });
