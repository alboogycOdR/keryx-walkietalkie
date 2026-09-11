import 'dart:async';

import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/floor/effects.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/core/settings/settings_model.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_bridge.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/services/discovery/channel_hash_prefix.dart';
import 'package:keryx/services/discovery/discovery_config.dart';
import 'package:keryx/services/discovery/discovery_service.dart';
import 'package:keryx/services/linked/linked.dart';
import 'package:keryx/services/mesh/mesh.dart';
import 'package:keryx/services/signaling/signaling.dart';

import 'linked_proxy_floor_transport.dart';
import 'station_info.dart';

/// Composes the LOCAL and LINKED transport lifecycles into the single radio
/// session `FaceScreen` (TASK-037) drives — the host-composition layer four
/// other territories (discovery, signaling, mesh, linked) each disclaim as
/// "host wiring, out of this task's scope".
///
/// Host-agnostic by design: no Riverpod import, no direct `RadioState`
/// reads. All external effects go through the injected [dispatch] callback,
/// matching `MeshController` / `LinkedController` / `RadioStateBridge`'s own
/// one-way-ingress convention. `FaceScreen` wiring is TASK-037's job, not
/// this one's.
///
/// **Disclosed decision — settings are a construction-time snapshot.**
/// [settings] is captured once, at construction (and used again on every
/// [retune]); it is not a live stream. A meaningfully different settings
/// value (mode, relay URL, `forceLocalOnly`, TOT, busy-lockout) needs a new
/// `RadioSessionController` from the host — matches the "your host,
/// your call" injection idiom the rest of this integration wave uses, and
/// keeps the mode-resolution logic in this file synchronous and testable
/// rather than needing to react mid-session to arbitrary setting flips.
///
/// **Disclosed decision — "reachable" in AUTO mode is evaluated as
/// "configured", not as a live network probe.** The PLAN text asks for
/// "LINKED when a relay URL is configured and reachable, LOCAL otherwise".
/// A live reachability probe before ever attempting the join would just
/// duplicate — at extra start-up latency cost — the fallback machinery that
/// already exists once a LINKED join is attempted: `LinkedController` /
/// `TokenClient` throw on an actually-unreachable relay, and `LinkMonitor`
/// (wired in by `LinkedController` itself) already dispatches
/// `LinkResolved(useLocalFallback: true)` on give-up. So AUTO's mode
/// resolution here is a pure, synchronous function of [KeryxSettings]:
/// `relayUrl` non-empty and parseable with a non-empty host counts as
/// "configured", which is treated as "reachable enough to attempt".
class RadioSessionController {
  RadioSessionController({
    required this.localPeerId,
    required this.callsign,
    required KeryxSettings settings,
    required void Function(RadioEvent event) dispatch,
    required int initialChannel,
    required int initialCode,
    FloorClock? clock,
    SignalingEndpoint Function()? endpointFactory,
    DiscoveryService Function()? discoveryFactory,
    RtcAdapter? rtcAdapter,
    LiveKitAdapter? liveKitAdapter,
    TokenClient Function(Uri baseUrl)? tokenClientFactory,
    bool Function()? isIdle,
  }) : _settings = settings,
       _dispatch = dispatch,
       _channel = initialChannel,
       _code = initialCode,
       _clock = clock ?? const WallClock(),
       _endpointFactory = endpointFactory ?? IoSignalingEndpoint.new,
       _discoveryFactory = discoveryFactory ?? NsdDiscoveryService.production,
       _rtcAdapter = rtcAdapter ?? const FlutterWebrtcAdapter(),
       _liveKitAdapter = liveKitAdapter ?? const LiveKitClientAdapter(),
       _tokenClientFactory =
           tokenClientFactory ?? ((Uri baseUrl) => TokenClient(baseUrl: baseUrl)),
       _isIdleOverride = isIdle;

  final String localPeerId;
  final String callsign;

  final KeryxSettings _settings;
  final void Function(RadioEvent event) _dispatch;
  final FloorClock _clock;
  final SignalingEndpoint Function() _endpointFactory;
  final DiscoveryService Function() _discoveryFactory;
  final RtcAdapter _rtcAdapter;
  final LiveKitAdapter _liveKitAdapter;
  final TokenClient Function(Uri baseUrl) _tokenClientFactory;

  /// Overrides the internal idle-phase mirror used to obey the `SetMode`
  /// reducer trap (see [_flushPendingSetMode]) with a live read of the real
  /// `RadioState`. TASK-037's host has that read access (via its own
  /// `ref.read(radioStateProvider)`); this controller, being host-agnostic,
  /// does not — so it defaults to mirroring the relevant `RadioPhase`
  /// transitions itself from the active [FloorEngine]'s effects, which is
  /// exactly what the reducer does for the same events (see the dartdoc on
  /// [_onEffectForIdleTracking]).
  final bool Function()? _isIdleOverride;

  int _channel;
  int _code;

  // --- LOCAL chain ---------------------------------------------------
  SignalingService? _signaling;
  DiscoveryService? _discovery;
  MeshController? _mesh;
  MeshFloorTransport? _meshTransport;

  // --- LINKED chain ----------------------------------------------------
  LinkedController? _linked;
  LinkedProxyFloorTransport? _linkedTransport;

  // --- shared -----------------------------------------------------------
  FloorEngine? _floorEngine;
  RadioStateBridge? _bridge;
  StreamSubscription<FloorEffect>? _idleTrackSub;
  StreamSubscription<PeerSession>? _joinedSub;
  StreamSubscription<PeerSession>? _departedSub;
  final Map<String, PeerSession> _peers = <String, PeerSession>{};
  final _stations = StreamController<List<StationInfo>>.broadcast();

  bool _idleGuess = true;
  RadioMode? _pendingSetMode;
  bool _disposed = false;

  // --- RX level telemetry (TASK-079/ADR-002 A6) -------------------------
  //
  // Polls the active speaker's remote-track `audioLevel` at ~10 Hz while
  // `RadioPhase.rxActive` is the effective floor state, using the SAME
  // `engine.effects` stream `_onEffectForIdleTracking` already mirrors
  // (`RemoteFloorStarted`/`RemoteFloorEnded`; `EndTransmit` also stops it —
  // a local grant taking the floor after an RX makes the previous speaker
  // no longer active regardless of whether a `RemoteFloorEnded` preceded
  // it). Only the LOCAL/mesh chain implements a real read today: LINKED's
  // `LiveKitAdapter`/`LiveKitRoom` (`lib/services/linked/livekit_adapter.dart`,
  // outside this task's `Owned_Paths`) exposes no per-participant
  // `audioLevel` to `LinkedController`, so LINKED stays
  // `MeterLevel.decorative` — documented in `dossiers/TASK-079.md` rather
  // than faked here.
  static const _meterPollInterval = Duration(milliseconds: 100);

  MeterLevel _meterLevel = MeterLevel.decorative;
  FloorTimer? _meterPollTimer;
  String? _polledSpeakerId;
  StreamSubscription<FloorEffect>? _meterTrackSub;
  final _meterLevelController = StreamController<MeterLevel>.broadcast();

  /// The latest projected RX level — [MeterLevel.decorative] whenever no
  /// real inbound-rtp sample is currently being polled (idle/TX/LINKED/
  /// unavailable-sample).
  MeterLevel get meterLevel => _meterLevel;

  /// Emits every time [meterLevel] changes. Never replays the current value
  /// to a new subscriber — matches every other broadcast stream this class
  /// exposes ([stations]).
  Stream<MeterLevel> get meterLevelChanges => _meterLevelController.stream;

  /// The engine driving the currently active chain (LOCAL or LINKED).
  /// Non-null once [start] has completed.
  FloorEngine get floorEngine {
    final engine = _floorEngine;
    if (engine == null) {
      throw StateError('RadioSessionController.start() has not completed yet');
    }
    return engine;
  }

  /// Remote stations currently visible on the tuned channel. Empty until a
  /// LOCAL chain's signaling reports at least one joined peer — see the
  /// class dartdoc's disclosed decisions for why LINKED mode never emits
  /// entries here (out of this task's scope; roster comes from
  /// `SignalingService`, which is LOCAL-only).
  Stream<List<StationInfo>> get stations => _stations.stream;

  /// Debug/test seams — never used for production control flow, only for
  /// asserting which chain got constructed (TASK-035 acceptance criterion
  /// on the mode matrix) and for reaching into the composed floor cycle.
  MeshController? get debugMeshController => _mesh;
  MeshFloorTransport? get debugMeshTransport => _meshTransport;
  SignalingService? get debugSignaling => _signaling;
  DiscoveryService? get debugDiscovery => _discovery;
  LinkedController? get debugLinkedController => _linked;
  LinkedProxyFloorTransport? get debugLinkedTransport => _linkedTransport;

  /// Resolves mode policy, builds the LOCAL or LINKED chain, and dispatches
  /// `SetMode` reflecting whichever one actually got built (queued if the
  /// reducer is not currently `RadioPhase.idle`).
  Future<void> start() async {
    _checkNotDisposed();
    final mode = _resolveEffectiveMode();
    if (mode == RadioMode.local) {
      await _startLocal();
    } else {
      await _startLinked();
    }
    _queueSetMode(mode);
  }

  /// Full teardown/rebuild of the channel-scoped parts (new
  /// `channelHashPrefix` / `roomId`), per TASK-035's own spec: retuning
  /// means the LOCAL discovery/signaling bind and the LINKED room are both
  /// channel-scoped, so nothing about them survives a channel change.
  Future<void> retune({required int channel, required int code}) async {
    _checkNotDisposed();
    await _teardownActive();
    _channel = channel;
    _code = code;
    await start();
  }

  /// Join a scanned/tapped Event QR payload (FR-043/FR-044). Requires an
  /// already-active LINKED chain — i.e. [start] must already have resolved
  /// to LINKED (`linked` mode, or `auto` with a configured relay and
  /// `forceLocalOnly` off). Disclosed simplification: this task does not
  /// force a mode switch on the caller's behalf; TASK-037's host is
  /// expected to check availability (or just call this only when the
  /// active mode is already LINKED) before invoking it.
  Future<void> joinEvent(EventLinkPayload payload) async {
    _checkNotDisposed();
    final linked = _linked;
    if (linked == null) {
      throw StateError(
        'joinEvent requires an active LINKED session; call start() with '
        'LINKED-capable settings first',
      );
    }
    await linked.joinRoomId(
      roomId: payload.roomId,
      forceLocalOnly: _settings.forceLocalOnly,
    );
    final transport = linked.floorTransport;
    if (transport != null) _linkedTransport?.attach(transport);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _teardownActive();
    await _stations.close();
    await _meterLevelController.close();
  }

  // --- mode policy --------------------------------------------------------

  RadioMode _resolveEffectiveMode() {
    if (_settings.forceLocalOnly) return RadioMode.local;
    switch (_settings.mode) {
      case RadioMode.local:
        return RadioMode.local;
      case RadioMode.linked:
        return RadioMode.linked;
      case RadioMode.auto:
        return _relayConfigured() ? RadioMode.linked : RadioMode.local;
    }
  }

  bool _relayConfigured() {
    if (_settings.relayUrl.isEmpty) return false;
    final uri = Uri.tryParse(_settings.relayUrl);
    return uri != null && uri.host.isNotEmpty;
  }

  // --- LOCAL chain ---------------------------------------------------

  String _channelHashPrefix() => ChannelHashPrefix.compute(
    region: _settings.region,
    channel: '$_channel',
    code: '$_code',
  );

  Future<void> _startLocal() async {
    final endpoint = _endpointFactory();
    final signaling = SignalingService(endpoint: endpoint, clock: _clock);
    await signaling.start(
      SignalingConfig(
        peerId: localPeerId,
        callsign: callsign,
        channelHashPrefix: _channelHashPrefix(),
      ),
    );

    final discovery = _discoveryFactory();
    await discovery.start(
      DiscoveryConfig(
        peerId: localPeerId,
        callsign: callsign,
        channelHashPrefix: _channelHashPrefix(),
        signalingPort: signaling.boundPort,
      ),
    );
    await discovery.onTuned();
    signaling.attachDiscovery(discovery);

    final meshTransport = MeshFloorTransport();
    final engine = FloorEngine(
      localPeerId: localPeerId,
      transport: meshTransport,
      clock: _clock,
      tot: Duration(seconds: _settings.totSeconds),
      busyLockout: _settings.busyLockout,
      callsign: callsign,
    );
    final mesh = MeshController(
      localPeerId: localPeerId,
      adapter: _rtcAdapter,
      signaling: signaling,
      floorEngine: engine,
      floorTransport: meshTransport,
    );

    _signaling = signaling;
    _discovery = discovery;
    _meshTransport = meshTransport;
    _mesh = mesh;
    _adoptEngine(engine, signaling: signaling);
  }

  // --- LINKED chain ----------------------------------------------------

  Future<void> _startLinked() async {
    final proxyTransport = LinkedProxyFloorTransport();
    final engine = FloorEngine(
      localPeerId: localPeerId,
      transport: proxyTransport,
      clock: _clock,
      tot: Duration(seconds: _settings.totSeconds),
      busyLockout: _settings.busyLockout,
      callsign: callsign,
    );
    final baseUrl = Uri.tryParse(_settings.resolvedTokenServiceUrl) ?? Uri();
    final tokenClient = _tokenClientFactory(baseUrl);
    final relayUrl = Uri.tryParse(_settings.relayUrl) ?? Uri();
    final linked = LinkedController(
      adapter: _liveKitAdapter,
      tokenClient: tokenClient,
      relayUrl: relayUrl,
      callsign: callsign,
      floorEngine: engine,
      dispatch: _dispatch,
    );

    await linked.joinNumbered(
      region: _settings.region,
      channel: _channel,
      code: _code,
      forceLocalOnly: _settings.forceLocalOnly,
    );
    final transport = linked.floorTransport;
    if (transport != null) proxyTransport.attach(transport);

    _linked = linked;
    _linkedTransport = proxyTransport;
    _adoptEngine(engine, signaling: null);
  }

  // --- shared wiring -------------------------------------------------

  void _adoptEngine(FloorEngine engine, {SignalingService? signaling}) {
    _floorEngine = engine;
    _bridge = RadioStateBridge(engine: engine, dispatch: _dispatch);
    _idleGuess = true;
    _idleTrackSub = engine.effects.listen(_onEffectForIdleTracking);
    _meterTrackSub = engine.effects.listen(_onEffectForMeterLevel);
    if (signaling != null) {
      _joinedSub = signaling.sessionsJoined.listen(_onPeerJoined);
      _departedSub = signaling.sessionsDeparted.listen(_onPeerDeparted);
    }
  }

  void _onPeerJoined(PeerSession session) {
    _peers[session.peerId] = session;
    _publishRoster();
  }

  void _onPeerDeparted(PeerSession session) {
    _peers.remove(session.peerId);
    _publishRoster();
  }

  void _publishRoster() {
    final ids = <String>{localPeerId, ..._peers.keys};
    _floorEngine?.updateRoster(ids);
    _bridge?.updateRoster(ids.length);
    final stations = _peers.values
        .map((session) => StationInfo(peerId: session.peerId, callsign: session.callsign))
        .toList(growable: false);
    if (!_stations.isClosed) _stations.add(stations);
  }

  // --- SetMode / reducer-idle handling ---------------------------------

  /// Mirrors just enough of `RadioReducer`'s `RadioPhase` transitions to
  /// know when `SetMode` (idle-only) is safe to dispatch, since this
  /// controller has no direct `RadioState` read access (host-agnostic — see
  /// class dartdoc). The mapping matches `RadioReducer.reduce` exactly for
  /// the events that move phase away from / back to `idle`:
  /// `RequestTransmit`/`RemoteFloorStarted` leave idle;
  /// `TransmitDenied`/`EndTransmit`/`RemoteFloorEnded` return to it.
  /// [_isIdleOverride], if supplied, replaces this mirror entirely with a
  /// live read from whoever does have `RadioState` access.
  void _onEffectForIdleTracking(FloorEffect effect) {
    if (effect is! DispatchRadio) return;
    final event = effect.event;
    if (event is RequestTransmit || event is RemoteFloorStarted) {
      _idleGuess = false;
    } else if (event is TransmitDenied ||
        event is EndTransmit ||
        event is RemoteFloorEnded) {
      _idleGuess = true;
      _flushPendingSetMode();
    }
  }

  bool _isIdleNow() => _isIdleOverride?.call() ?? _idleGuess;

  // --- RX level telemetry -----------------------------------------------

  /// Mirrors `RadioStateBridge._projectFloorEvent`'s own
  /// `RemoteFloorStarted`/`RemoteFloorEnded`/`TransmitGranted`(local TX
  /// pre-empting an RX)/`EndTransmit` handling for exactly the transitions
  /// that start or stop who currently holds the floor — same reasoning
  /// this file already documents on [_onEffectForIdleTracking].
  void _onEffectForMeterLevel(FloorEffect effect) {
    if (effect is! DispatchRadio) return;
    final event = effect.event;
    if (event is RemoteFloorStarted) {
      final speakerId = _floorEngine?.holder;
      if (speakerId != null) {
        _startMeterPolling(speakerId);
      } else {
        _stopMeterPolling();
      }
    } else if (event is RemoteFloorEnded ||
        event is EndTransmit ||
        event is TransmitGranted) {
      _stopMeterPolling();
    }
  }

  void _startMeterPolling(String speakerId) {
    _meterPollTimer?.cancel();
    _polledSpeakerId = speakerId;
    _scheduleMeterPoll();
  }

  void _stopMeterPolling() {
    _meterPollTimer?.cancel();
    _meterPollTimer = null;
    _polledSpeakerId = null;
    _setMeterLevel(MeterLevel.decorative);
  }

  void _scheduleMeterPoll() {
    _meterPollTimer = _clock.schedule(_meterPollInterval, _pollMeterLevel);
  }

  Future<void> _pollMeterLevel() async {
    final speakerId = _polledSpeakerId;
    if (_disposed || speakerId == null) return;
    // Only the LOCAL/mesh chain has a real reader today — see this
    // section's opening dartdoc for why LINKED is intentionally not
    // implemented here.
    final mesh = _mesh;
    final level = mesh != null
        ? await mesh.readAudioLevel(speakerId)
        : const RtcUnavailableAudioLevel();
    // Re-check after the `await` — a retune/dispose/floor-change may have
    // landed while the read was in flight, or a newer poll for a different
    // speaker may already be in progress.
    if (_disposed || _polledSpeakerId != speakerId) return;
    _setMeterLevel(
      level is RtcMeasuredAudioLevel
          ? MeasuredMeterLevel(level.value * 100)
          : MeterLevel.decorative,
    );
    // Still polling this speaker — reschedule. `_polledSpeakerId` is
    // cleared by `_stopMeterPolling`/teardown, so a stale timer never
    // outlives the RX window it was started for.
    if (_polledSpeakerId == speakerId) _scheduleMeterPoll();
  }

  void _setMeterLevel(MeterLevel level) {
    if (_meterLevel == level) return;
    _meterLevel = level;
    if (!_meterLevelController.isClosed) _meterLevelController.add(level);
  }

  void _queueSetMode(RadioMode mode) {
    _pendingSetMode = mode;
    _flushPendingSetMode();
  }

  void _flushPendingSetMode() {
    final pending = _pendingSetMode;
    if (pending == null) return;
    if (!_isIdleNow()) return;
    _pendingSetMode = null;
    _dispatch(SetMode(pending));
  }

  // --- teardown ---------------------------------------------------------

  Future<void> _teardownActive() async {
    await _idleTrackSub?.cancel();
    _idleTrackSub = null;
    await _meterTrackSub?.cancel();
    _meterTrackSub = null;
    _stopMeterPolling();
    await _joinedSub?.cancel();
    _joinedSub = null;
    await _departedSub?.cancel();
    _departedSub = null;
    await _bridge?.dispose();
    _bridge = null;
    _peers.clear();
    if (!_stations.isClosed) _stations.add(const []);
    _pendingSetMode = null;

    final mesh = _mesh;
    _mesh = null;
    if (mesh != null) await mesh.dispose();
    final signaling = _signaling;
    _signaling = null;
    if (signaling != null) await signaling.dispose();
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) await discovery.dispose();
    // Caller-owned (TASK-032 convention): the controller built this and
    // handed it to both `FloorEngine` and `MeshController`, so it — not
    // `MeshController.dispose()` — is responsible for disposing it.
    final meshTransport = _meshTransport;
    _meshTransport = null;
    if (meshTransport != null) await meshTransport.dispose();

    final linked = _linked;
    _linked = null;
    if (linked != null) await linked.dispose();
    final linkedTransport = _linkedTransport;
    _linkedTransport = null;
    if (linkedTransport != null) await linkedTransport.dispose();

    _floorEngine?.dispose();
    _floorEngine = null;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('RadioSessionController is disposed');
    }
  }
}
