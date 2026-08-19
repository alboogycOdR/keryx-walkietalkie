import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/state/radio_state.dart';

/// Riverpod host for the pure reducer. It introduces no transitions itself.
class RadioStateController extends Notifier<RadioState> {
  @override
  RadioState build() => const RadioState.off();

  void dispatch(RadioEvent event) {
    state = ref.read(radioReducerProvider).reduce(state, event);
  }
}

final radioReducerProvider = Provider<RadioReducer>(
  (ref) => const RadioReducer(),
);

final radioStateProvider = NotifierProvider<RadioStateController, RadioState>(
  RadioStateController.new,
);
