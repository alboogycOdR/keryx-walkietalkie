import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/session/session.dart' show RadioSessionController;

/// TASK-048 — the single, app-scoped [RadioHost], hoisted the rest of the
/// way per Technical §9 ("A separate integration task owns shared route
/// registration, app.dart, shared providers and final wiring").
///
/// Every default factory here is byte-identical in substance to the ones
/// TASK-045 left on `FaceScreen` (`lib/features/face/face_screen.dart`,
/// outside this task's `Owned_Paths`, so duplicated rather than imported —
/// they were file-private `static` members there). Nothing here constructs
/// a *different* session/audio/service stack than the pre-hoist code did
/// (ADR-001 §5/§6: this is a hoist, not a rewrite).
///
/// Constructed lazily on first read and never rebuilt: this is a plain
/// [Provider] (not `.autoDispose`), so Riverpod keeps exactly one instance
/// alive for the lifetime of `KeryxApp`'s single `ProviderScope` — the same
/// scope every destination in `lib/app_shell/**` and the dev-only legacy
/// route share (Technical §1/§2: "retain a single ProviderScope"). Every
/// destination only *reads* this provider; nothing beneath it ever
/// constructs a second [RadioHost] or duplicates `radioStateProvider`
/// (Technical §3).
final radioHostProvider = Provider<RadioHost>((ref) {
  final host = KeryxRadioHost(
    sessionFactory: _defaultSessionFactory,
    audioSinkFactory: _defaultAudioSinkFactory,
    audioSinkDisposer: _defaultAudioSinkDisposer,
    identityFactory: _defaultIdentityFactory,
    permissionGateFactory: _defaultPermissionGateFactory,
    radioServiceFactory: _defaultRadioServiceFactory,
    loadSettings: () => ref.read(settingsProvider.future),
    dispatch: (event) => ref.read(radioStateProvider.notifier).dispatch(event),
    readRadioState: () => ref.read(radioStateProvider),
    rememberChannel: (channel) =>
        ref.read(settingsProvider.notifier).rememberChannel(channel),
    listenRadioState: (onChange, {bool fireImmediately = false}) {
      // `Ref.listen` (not `WidgetRef.listenManual` — this provider body
      // receives a plain `Ref`, which has no `listenManual`; `listen` is
      // its provider-to-provider equivalent, same semantics).
      final subscription = ref.listen<RadioState>(
        radioStateProvider,
        (previous, next) => onChange(previous, next),
        fireImmediately: fireImmediately,
      );
      return subscription.close;
    },
    listenSettings: (onChange) {
      final subscription = ref.listen<AsyncValue<KeryxSettings>>(
        settingsProvider,
        (previous, next) {
          final settings = next.valueOrNull;
          // Still loading, or a load error — keep whatever session is
          // already running rather than tearing it down over a transient
          // read failure (mirrors the pre-hoist FaceScreen behaviour).
          if (settings != null) onChange(settings);
        },
      );
      return subscription.close;
    },
  );
  // Idempotent-safe: `dispose()` is documented as safe to call even if
  // `start()` never ran (VT-004 "repeated disposal is safe"). This scope is
  // only ever torn down at app exit, so in practice this fires at most once.
  ref.onDispose(() => unawaited(host.dispose()));
  return host;
});

SessionHost _defaultSessionFactory({
  required String localPeerId,
  required String callsign,
  required KeryxSettings settings,
  required void Function(RadioEvent event) dispatch,
  required int initialChannel,
  required int initialCode,
}) => RadioSessionHostAdapter(
  RadioSessionController(
    localPeerId: localPeerId,
    callsign: callsign,
    settings: settings,
    dispatch: dispatch,
    initialChannel: initialChannel,
    initialCode: initialCode,
  ),
);

Future<AudioSink> _defaultAudioSinkFactory() async {
  final sink = DeviceAudioSink();
  await sink.initialize();
  return sink;
}

Future<void> _defaultAudioSinkDisposer(AudioSink sink) async {
  if (sink is DeviceAudioSink) {
    await sink.dispose();
  }
}

Future<DeviceIdentity> _defaultIdentityFactory() =>
    IdentityRepository(SecureIdentityStore()).loadOrCreate();

FacePermissionGate _defaultPermissionGateFactory() =>
    const DeviceFacePermissionGate();

RadioServiceController _defaultRadioServiceFactory() =>
    ChannelRadioServiceController.production();
