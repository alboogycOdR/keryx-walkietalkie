import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Little-endian PCM WAV header + samples (48 kHz / 16-bit / mono expected).
final class WavFile {
  const WavFile({
    required this.sampleRate,
    required this.bitsPerSample,
    required this.channels,
    required this.samples,
  });

  final int sampleRate;
  final int bitsPerSample;
  final int channels;
  final Float64List samples;

  Duration get duration => Duration(
        microseconds: (samples.length * 1000000 / (sampleRate * channels))
            .round(),
      );

  static WavFile read(File file) {
    final bytes = file.readAsBytesSync();
    if (bytes.length < 44) {
      throw FormatException('WAV too short: ${file.path}');
    }
    if (_ascii(bytes, 0, 4) != 'RIFF' || _ascii(bytes, 8, 4) != 'WAVE') {
      throw FormatException('not a RIFF/WAVE: ${file.path}');
    }
    var offset = 12;
    var sampleRate = 0;
    var bits = 0;
    var channels = 0;
    Uint8List? data;
    while (offset + 8 <= bytes.length) {
      final id = _ascii(bytes, offset, 4);
      final size = _le32(bytes, offset + 4);
      final start = offset + 8;
      if (id == 'fmt ') {
        channels = _le16(bytes, start + 2);
        sampleRate = _le32(bytes, start + 4);
        bits = _le16(bytes, start + 14);
      } else if (id == 'data') {
        data = Uint8List.sublistView(bytes, start, start + size);
      }
      offset = start + size + (size.isOdd ? 1 : 0);
    }
    if (data == null || bits != 16) {
      throw FormatException('expected 16-bit PCM data in ${file.path}');
    }
    final samples = Float64List(data.length ~/ 2);
    final bd = ByteData.sublistView(data);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little) / 32767.0;
    }
    return WavFile(
      sampleRate: sampleRate,
      bitsPerSample: bits,
      channels: channels,
      samples: samples,
    );
  }
}

/// Ungated BS.1770-4 K-weighted integrated loudness (mono).
double integratedLufs(List<double> samples, {int sampleRate = 48000}) {
  if (samples.isEmpty) {
    return double.negativeInfinity;
  }
  if (sampleRate != 48000) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'LUFS helper is 48 kHz');
  }
  const preB = [1.53512485958697, -2.69169618940638, 1.19839281085285];
  const preA = [1.0, -1.69065929318241, 0.73248077421585];
  const rlbB = [1.0, -2.0, 1.0];
  const rlbA = [1.0, -1.99004745483398, 0.99007225036621];
  final k = _biquad(_biquad(samples, preB, preA), rlbB, rlbA);
  var ms = 0.0;
  for (final s in k) {
    ms += s * s;
  }
  ms /= k.length;
  if (ms <= 1e-20) {
    return double.negativeInfinity;
  }
  return -0.691 + 10.0 * (math.log(ms) / math.ln10);
}

List<double> _biquad(List<double> xs, List<double> b, List<double> a) {
  final y = List<double>.filled(xs.length, 0);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final xn = xs[i];
    final yn = b[0] * xn + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2;
    y[i] = yn;
    x2 = x1;
    x1 = xn;
    y2 = y1;
    y1 = yn;
  }
  return y;
}

String _ascii(Uint8List b, int o, int n) =>
    String.fromCharCodes(b.sublist(o, o + n));

int _le16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

int _le32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
