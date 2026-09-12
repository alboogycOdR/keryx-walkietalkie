import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/core/radio_host/radio_session_host_v2.dart';
import 'package:keryx/core/settings/settings_model.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart'
    show encodeUnpaddedBase64Url;
import 'package:keryx/services/linked/linked.dart';
import 'package:keryx/services/session/radio_session_controller.dart';

import '../../services/linked/fakes/fake_livekit_adapter.dart';

/// v2 (Technical §6.4, TASK-088 additive scope): standalone-seam coverage —
/// this class is not wired into `KeryxRadioHost` yet (Technical §6a), so it
/// is tested directly rather than through that class's much larger surface.
void main() {
  group('RadioSessionHostV2', () {
    late List<RadioEvent> dispatched;
    late RadioSessionController controller;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      dispatched = [];
      controller = RadioSessionController(
        localPeerId: 'ALFA-1',
        callsign: 'Alice',
        settings: const KeryxSettings(),
        dispatch: dispatched.add);
    });

    tearDown(() => controller.dispose());

    test(
      'runs identity -> presence -> target -> switchTarget in order, once',
      () async {
        final calls = <String>[];
        const target = TalkTarget(
          kind: TalkTargetKind.contact,
          id: 'p1',
          name: 'Bravo',
          roomId: 'v2-room-host',
          memberPeerIds: ['BRAVO-7']);

        await controller.start();
        final host = RadioSessionHostV2(
          loadIdentity: () async {
            calls.add('identity');
            return null;
          },
          openPresenceSession: () async {
            calls.add('presence');
          },
          resolveCurrentTarget: () async {
            calls.add('target');
            return target;
          },
          sessionController: controller);

        expect(host.isStarted, isFalse);
        await host.start();

        expect(calls, ['identity', 'presence', 'target']);
        expect(host.isStarted, isTrue);
        expect(dispatched.whereType<SetRoom>().last.roomId, 'v2-room-host');
      });

    test(
      'a null resolved target is a no-op (fresh install, no history)',
      () async {
        await controller.start();
        final host = RadioSessionHostV2(
          loadIdentity: () async => null,
          openPresenceSession: () async {},
          resolveCurrentTarget: () async => null,
          sessionController: controller);

        await host.start();

        expect(dispatched.whereType<SetRoom>(), isEmpty);
      });

    test(
      'a second start() re-resolves the target without repeating identity/'
      'presence bootstrap',
      () async {
        var identityCalls = 0;
        var presenceCalls = 0;
        var currentTarget = const TalkTarget(
          kind: TalkTargetKind.contact,
          id: 'p1',
          name: 'Bravo',
          roomId: 'v2-room-a');

        await controller.start();
        final host = RadioSessionHostV2(
          loadIdentity: () async {
            identityCalls++;
            return null;
          },
          openPresenceSession: () async {
            presenceCalls++;
          },
          resolveCurrentTarget: () async => currentTarget,
          sessionController: controller);

        await host.start();
        currentTarget = const TalkTarget(
          kind: TalkTargetKind.contact,
          id: 'p2',
          name: 'Charlie',
          roomId: 'v2-room-b');
        await host.start();

        expect(identityCalls, 1);
        expect(presenceCalls, 1);
        expect(dispatched.whereType<SetRoom>().last.roomId, 'v2-room-b');
      });

    test(
      'TASK-101: a contact target resolved by the host reaches requestToken '
      'as peerPublicKey (id is the encoded key; host does not strip it)',
      () async {
        final peerKey = List<int>.generate(32, (i) => 5);
        final peerPk = encodeUnpaddedBase64Url(peerKey);
        final contact = TalkTarget(
          kind: TalkTargetKind.contact,
          id: peerPk,
          name: 'Bravo',
          roomId: 'ABCDEFGHIJKLMNOP',
          memberPeerIds: [peerPk],
        );
        final recorder = _RecordingTokenClient();
        final linked = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: const KeryxSettings(
            squelchLevel: 5,
            totSeconds: 120,
            busyLockout: false,
            latchMode: false,
            forceLocalOnly: false,
            relayUrl: 'wss://relay.example',
            tokenServiceUrl: 'https://relay.example/token-svc',
            characterDspIntensity: CharacterDspIntensity.light,
            dimMode: DimMode.auto,
          ),
          dispatch: dispatched.add,
          liveKitAdapter: FakeLiveKitAdapter(),
          tokenClientFactory: (_, {signer}) => recorder,
        );
        addTearDown(linked.dispose);

        await linked.start();
        final host = RadioSessionHostV2(
          loadIdentity: () async => null,
          openPresenceSession: () async {},
          resolveCurrentTarget: () async => contact,
          sessionController: linked,
        );
        await host.start();

        expect(recorder.capturedPeerKeys, [peerKey]);
      });
  });
}

class _RecordingTokenClient extends TokenClient {
  _RecordingTokenClient() : super(baseUrl: Uri.parse('https://token.invalid'));

  final capturedPeerKeys = <List<int>?>[];

  @override
  Future<TokenResponse> requestToken({
    required String roomId,
    required String callsign,
    String? eventToken,
    List<int>? peerPublicKey,
  }) async {
    capturedPeerKeys.add(
      peerPublicKey == null ? null : List<int>.from(peerPublicKey),
    );
    return const TokenResponse(
      token: 'fake-jwt',
      identity: 'Alice#deadbeef',
      ttl: Duration(minutes: 5),
    );
  }
}
