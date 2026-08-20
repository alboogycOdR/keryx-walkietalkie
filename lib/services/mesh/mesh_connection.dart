import 'mesh_config.dart';
import 'floor_data_channel_transport.dart';
import 'rtc_adapter.dart';

/// One peer's WebRTC connection: the shared local audio track (muted /
/// enabled by [MeshController], never by this class), the offer/answer/ICE
/// dance, and the floor-control data channel — offerer creates it
/// explicitly, answerer receives it via [RtcPeerConnection.onDataChannel].
class MeshConnection {
  MeshConnection({
    required this.peerId,
    required RtcPeerConnection pc,
    required RtcLocalAudioTrack localTrack,
    required MeshFloorTransport floorTransport,
    required void Function(RtcIceCandidate candidate) onLocalIceCandidate,
  }) : _pc = pc,
       _localTrack = localTrack,
       _floorTransport = floorTransport {
    _pc.onIceCandidate = onLocalIceCandidate;
    _pc.onDataChannel = (RtcDataChannel channel) {
      _floorTransport.attach(peerId, channel);
    };
  }

  final String peerId;
  final RtcPeerConnection _pc;
  final RtcLocalAudioTrack _localTrack;
  final MeshFloorTransport _floorTransport;
  bool _closed = false;

  void Function(RtcPeerConnectionState state)? get onConnectionState =>
      _pc.onConnectionState;

  set onConnectionState(void Function(RtcPeerConnectionState state)? cb) {
    _pc.onConnectionState = cb;
  }

  /// Offerer side: publish the shared track (muted — [_localTrack.enabled]
  /// is [MeshController]'s to flip), open the floor data channel, and
  /// return the local offer to send over signaling.
  Future<RtcSessionDescription> createOffer() async {
    await _pc.addAudioTrack(_localTrack);
    final channel = await _pc.createDataChannel(
      MeshConfig.floorDataChannelLabel,
    );
    _floorTransport.attach(peerId, channel);
    final offer = await _pc.createOffer();
    await _pc.setLocalDescription(offer);
    return offer;
  }

  /// Answerer side: publish the shared track, apply the remote offer, and
  /// return the local answer to send back.
  Future<RtcSessionDescription> createAnswer(
    RtcSessionDescription remoteOffer,
  ) async {
    await _pc.addAudioTrack(_localTrack);
    await _pc.setRemoteDescription(remoteOffer);
    final answer = await _pc.createAnswer();
    await _pc.setLocalDescription(answer);
    return answer;
  }

  Future<void> acceptAnswer(RtcSessionDescription answer) {
    return _pc.setRemoteDescription(answer);
  }

  Future<void> addRemoteIceCandidate(RtcIceCandidate candidate) {
    return _pc.addIceCandidate(candidate);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _floorTransport.detach(peerId);
    await _pc.close();
  }
}
