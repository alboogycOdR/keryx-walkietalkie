import 'mesh_config.dart';

/// SDP munging for the TS §8.1 Opus profile: "Opus, mono, 16–24 kbps, 20 ms
/// frames, in-band FEC on, DTX off during TX".
///
/// flutter_webrtc / libwebrtc do not expose in-band-FEC or DTX as
/// [RTCRtpParameters] knobs (only bitrate does, via `setParameters`), so all
/// four values are pinned the same way here: rewriting the `a=fmtp` line for
/// the negotiated Opus payload type before the SDP is set as local/remote
/// description. Pure string transform — no WebRTC types — so it is testable
/// without a plugin.
abstract final class OpusSdp {
  static final RegExp _rtpmapOpus = RegExp(
    r'^a=rtpmap:(\d+) opus/48000(?:/\d+)?$',
    caseSensitive: false,
  );

  /// Rewrite [sdp]'s Opus `a=fmtp` (and add `a=ptime`) to the §8.1 profile.
  /// Returns [sdp] unchanged if no `m=audio` / Opus payload type is found —
  /// callers should treat that as "nothing to munge", not an error, since a
  /// data-channel-only offer has no audio section at all.
  static String applyProfile(
    String sdp, {
    int maxBitrateBps = MeshConfig.maxBitrateBps,
    int ptimeMs = MeshConfig.ptimeMs,
    bool inBandFec = MeshConfig.inBandFecOn,
    bool dtxOff = MeshConfig.dtxOffDuringTx,
  }) {
    final lines = sdp.split(RegExp(r'\r\n|\n'));
    final payloadType = _findOpusPayloadType(lines);
    if (payloadType == null) return sdp;

    final fmtpValue =
        'useinbandfec=${inBandFec ? 1 : 0};usedtx=${dtxOff ? 0 : 1};'
        'maxaveragebitrate=$maxBitrateBps;stereo=0;sprop-stereo=0';

    final out = <String>[];
    var audioSection = false;
    var fmtpWritten = false;
    var ptimeWritten = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('m=audio')) {
        audioSection = true;
        out.add(line);
        continue;
      }
      if (audioSection && line.startsWith('m=')) {
        // Entering the next media section: flush anything not yet written.
        _flushAudioExtras(
          out,
          payloadType,
          fmtpValue,
          ptimeMs,
          fmtpWritten: fmtpWritten,
          ptimeWritten: ptimeWritten,
        );
        audioSection = false;
        fmtpWritten = true;
        ptimeWritten = true;
        out.add(line);
        continue;
      }

      if (audioSection && line.startsWith('a=fmtp:$payloadType ')) {
        out.add('a=fmtp:$payloadType $fmtpValue');
        fmtpWritten = true;
        continue;
      }
      if (audioSection && line.startsWith('a=ptime:')) {
        out.add('a=ptime:$ptimeMs');
        ptimeWritten = true;
        continue;
      }

      out.add(line);
    }

    if (audioSection) {
      // m=audio ran to the end of the SDP (single-section offer/answer).
      _flushAudioExtras(
        out,
        payloadType,
        fmtpValue,
        ptimeMs,
        fmtpWritten: fmtpWritten,
        ptimeWritten: ptimeWritten,
      );
    }

    return out.join('\r\n');
  }

  static void _flushAudioExtras(
    List<String> out,
    int payloadType,
    String fmtpValue,
    int ptimeMs, {
    required bool fmtpWritten,
    required bool ptimeWritten,
  }) {
    if (!fmtpWritten) {
      out.add('a=fmtp:$payloadType $fmtpValue');
    }
    if (!ptimeWritten) {
      out.add('a=ptime:$ptimeMs');
    }
  }

  static int? _findOpusPayloadType(List<String> lines) {
    for (final line in lines) {
      final match = _rtpmapOpus.firstMatch(line);
      if (match != null) return int.parse(match.group(1)!);
    }
    return null;
  }
}
