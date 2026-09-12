import 'dart:async';

import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/floor/effects.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/core/settings/settings_model.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_bridge.dart';
import 'package:keryx/services/discovery/discovery_config.dart';
import 'package:keryx/services/discovery/discovery_service.dart';
import 'package:keryx/services/discovery/room_prefix.dart';
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
/// TASK-097: thrown by [RadioSessionController._startLocal]/[_startLinked]
/// (surfaced through [RadioSessionController.start]/[switchTarget]) when
/// session establishment could not complete within
/// `RadioSessionController`'s own bound — either a [TimeoutException] from
/// that bound, or any real transport/signaling/token/LiveKit failure the
/// chain threw. Carries [transport] (always [Transport.direct] or
/// [Transport.relay] — a start attempt is always exactly one of the two) so
/// a caller (`KeryxRadioHost`) can name the actual problem instead of a
/// generic failure (Design §5), and [cause]/[stackTrace] for logging only —
/// never surfaced to the UI verbatim (Technical §3: "The UI must not parse
/// exception text to determine state").
class SessionEstablishmentFailure implements Exception {
  const SessionEstablishmentFailure(this.transport, this.cause, this.stackTrace);

  final Transport transport;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() =>
      'SessionEstablishmentFailure(transport: $transport, cause: $cause)';
}

class RadioSessionController {
  RadioSessionController({
    required this.localPeerId,
    required this.callsign,
    required KeryxSettings settings,
    required void Function(RadioEvent event) dispatch,
    FloorClock? clock,
    SignalingEndpoint Function()? endpointFactory,
    DiscoveryService Function()? discoveryFactory,
    RtcAdapter? rtcAdapter,
    LiveKitAdapter? liveKitAdapter,
    TokenClient Function(Uri baseUrl)? tokenClientFactory,
    Duration? sessionStartTimeout,
  }) : _settings = settings,
       _dispatch = dispatch,
       _clock = clock ?? const WallClock(),
       _endpointFactory = endpointFactory ?? IoSignalingEndpoint.new,
       _discoveryFactory = discoveryFactory ?? NsdDiscoveryService.production,
       _rtcAdapter = rtcAdapter ?? const FlutterWebrtcAdapter(),
       _liveKitAdapter = liveKitAdapter ?? const LiveKitClientAdapter(),
       _tokenClientFactory =
           tokenClientFactory ??
           ((Uri baseUrl) => TokenClient(baseUrl: baseUrl)),
       _sessionStartTimeout = sessionStartTimeout ?? _defaultSessionStartTimeout;

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

  /// TASK-097: bounds `_startLocal`/`_startLinked` — see this class's own
  /// `start()`/`switchTarget()` dartdoc-adjacent notes below. Injectable so
  /// a test can prove the bound fires without a real multi-second wait.
  final Duration _sessionStartTimeout;
  static const _defaultSessionStartTimeout = Duration(seconds: 20);

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
  StreamSubscription<PeerSession>? _joinedSub;
  StreamSubscription<PeerSession>? _departedSub;
  final Map<String, PeerSession> _peers = <String, PeerSession>{};
  final _stations = StreamController<List<StationInfo>>.broadcast();

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
  int _meterPollGeneration = 0;
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

  /// Resolves transport policy, builds the direct or relay chain, and
  /// dispatches `SetTransport` for whichever one actually got built.
  Future<void> start() async {
    _checkNotDisposed();
    final transport = _resolveTransport();
    if (transport == Transport.direct) {
      await _startLocal();
    } else {
      await _startLinked();
    }
    _dispatch(SetTransport(transport));
  }

  /// Switch the active chain to [target]'s room and close the solo
  /// join-guard (Technical §1.1) by calling `FloorEngine.updateRoster`
  /// with the full member list immediately after the chain is up.
  Future<void> switchTarget(
    TalkTarget target, {
    required List<String> memberPeerIds,
  }) async {
    _checkNotDisposed();
    await _teardownActive();
    final transport = _resolveTransport();
    if (transport == Transport.direct) {
      await _startLocal(roomIdOverride: target.roomId);
    } else {
      await _startLinked(roomIdOverride: target.roomId);
    }
    final roster = <String>{localPeerId, ...memberPeerIds};
    _floorEngine?.updateRoster(roster);
    _bridge?.updateRoster(roster.length);
    if (!_stations.isClosed) {
      _stations.add(
        memberPeerIds
            .map((id) => StationInfo(peerId: id, callsign: id))
            .toList(growable: false),
      );
    }
    _dispatch(SetRoom(target.roomId));
    _dispatch(SetTransport(transport));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _teardownActive();
    await _stations.close();
    await _meterLevelController.close();
  }

  // --- transport policy ---------------------------------------------------

  /// Idle placeholder used until [switchTarget] supplies a real room ID.
  /// 16 RFC 4648 chars so [RoomPrefix.compute] can slice it.
  static const _idleRoomId = 'AAAAAAAAAAAAAAAA';

  Transport _resolveTransport() {
    if (_settings.forceLocalOnly) return Transport.direct;
    if (_relayConfigured()) return Transport.relay;
    return Transport.direct;
  }

  bool _relayConfigured() {
    if (_settings.relayUrl.isEmpty) return false;
    final uri = Uri.tryParse(_settings.relayUrl);
    return uri != null && uri.host.isNotEmpty;
  }

  // --- LOCAL chain ---------------------------------------------------

  /// TASK-097: this whole method is bounded by [_sessionStartTimeout] — an
  /// unreachable LAN peer, a hung NSD/`MethodChannel` call inside
  /// `discovery.start()`/`onTuned()`, or any other suspension in this chain
  /// previously left `start()`/`switchTarget()` awaiting forever with no way
  /// for `RadioHost` to ever leave `RadioPhase.boot`. On timeout or any
  /// thrown failure, whatever was already constructed in this scope is
  /// best-effort disposed and a typed [SessionEstablishmentFailure] is
  /// thrown so callers get an honest, transport-labelled reason instead of
  /// a hang or a raw transport exception.
  ///
  /// **Disclosed limitation:** `.timeout()` stops *awaiting* the underlying
  /// call, it does not cancel it — a still-hung native platform call (e.g.
  /// NSD registration) may keep running in the background after this method
  /// has already thrown. Cancelling it would require a cancellation seam in
  /// `NsdDiscoveryService`/`SignalingService`, both outside this task's
  /// `Owned_Paths` (frozen since TASK-094). The bound here is a UI-facing
  /// guarantee ("never stuck showing boot forever"), not a resource-cleanup
  /// guarantee for an uncancellable platform call.
  Future<void> _startLocal({String? roomIdOverride}) async {
    final prefix = RoomPrefix.compute(roomIdOverride ?? _idleRoomId);
    final endpoint = _endpointFactory();
    final signaling = SignalingService(endpoint: endpoint, clock: _clock);
    DiscoveryService? discovery;
    try {
      await signaling
          .start(
            SignalingConfig(
              peerId: localPeerId,
              callsign: callsign,
              channelHashPrefix: prefix,
            ),
          )
          .timeout(_sessionStartTimeout);

      discovery = _discoveryFactory();
      await discovery
          .start(
            DiscoveryConfig(
              peerId: localPeerId,
              callsign: callsign,
              channelHashPrefix: prefix,
              signalingPort: signaling.boundPort,
            ),
          )
          .timeout(_sessionStartTimeout);
      await discovery.onTuned().timeout(_sessionStartTimeout);
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
    } catch (error, stack) {
      unawaited(discovery?.dispose());
      unawaited(signaling.dispose());
      throw SessionEstablishmentFailure(Transport.direct, error, stack);
    }
  }

  // --- LINKED chain ----------------------------------------------------

  /// TASK-097: same bound/disclosed-limitation notes as [_startLocal] —
  /// `linked.joinRoomId` (token fetch + LiveKit connect + publish) can
  /// suspend indefinitely on an unreachable relay; [LinkedController] itself
  /// carries no bound of its own (`token_client.dart`'s own 10 s HTTP
  /// timeout only covers the token fetch step, not the LiveKit `connect()`/
  /// publish steps after it).
  Future<void> _startLinked({String? roomIdOverride}) async {
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

    try {
      await linked
          .joinRoomId(
            roomId: roomIdOverride ?? _idleRoomId,
            forceLocalOnly: _settings.forceLocalOnly,
          )
          .timeout(_sessionStartTimeout);
      final transport = linked.floorTransport;
      if (transport != null) proxyTransport.attach(transport);

      _linked = linked;
      _linkedTransport = proxyTransport;
      _adoptEngine(engine, signaling: null);
    } catch (error, stack) {
      unawaited(linked.dispose());
      unawaited(proxyTransport.dispose());
      engine.dispose();
      throw SessionEstablishmentFailure(Transport.relay, error, stack);
    }
  }

  // --- shared wiring -------------------------------------------------

  void _adoptEngine(FloorEngine engine, {SignalingService? signaling}) {
    _floorEngine = engine;
    _bridge = RadioStateBridge(engine: engine, dispatch: _dispatch);
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
        .map(
          (session) =>
              StationInfo(peerId: session.peerId, callsign: session.callsign),
        )
        .toList(growable: false);
    if (!_stations.isClosed) _stations.add(stations);
  }

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
    _scheduleMeterPoll(++_meterPollGeneration);
  }

  void _stopMeterPolling() {
    _meterPollTimer?.cancel();
    _meterPollTimer = null;
    _polledSpeakerId = null;
    _meterPollGeneration++;
    _setMeterLevel(MeterLevel.decorative);
  }

  void _scheduleMeterPoll(int generation) {
    _meterPollTimer = _clock.schedule(
      _meterPollInterval,
      () => _pollMeterLevel(generation),
    );
  }

  Future<void> _pollMeterLevel(int generation) async {
    final speakerId = _polledSpeakerId;
    if (_disposed || speakerId == null || generation != _meterPollGeneration) {
      return;
    }
    // Only the LOCAL/mesh chain has a real reader today — see this
    // section's opening dartdoc for why LINKED is intentionally not
    // implemented here.
    final mesh = _mesh;
    RtcAudioLevel level = const RtcUnavailableAudioLevel();
    try {
      level = mesh != null
          ? await mesh.readAudioLevel(speakerId)
          : const RtcUnavailableAudioLevel();
    } catch (_) {
      // A closing peer connection can reject getStats mid-poll. Treat that
      // sample as unavailable; a transient read failure must not turn into
      // an uncaught async error or stop the active RX polling chain.
    }
    // Re-check after the `await` — a retune/dispose/floor-change may have
    // landed while the read was in flight, or a newer poll for a different
    // speaker may already be in progress.
    if (_disposed ||
        _polledSpeakerId != speakerId ||
        generation != _meterPollGeneration) {
      return;
    }
    _setMeterLevel(
      level is RtcMeasuredAudioLevel
          ? MeasuredMeterLevel(level.value * 100)
          : MeterLevel.decorative,
    );
    // Still polling this speaker — reschedule. `_polledSpeakerId` is
    // cleared by `_stopMeterPolling`/teardown, so a stale timer never
    // outlives the RX window it was started for.
    if (_polledSpeakerId == speakerId && generation == _meterPollGeneration) {
      _scheduleMeterPoll(generation);
    }
  }

  void _setMeterLevel(MeterLevel level) {
    if (_meterLevel == level) return;
    _meterLevel = level;
    if (!_meterLevelController.isClosed) _meterLevelController.add(level);
  }

  // --- teardown ---------------------------------------------------------

  Future<void> _teardownActive() async {
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
