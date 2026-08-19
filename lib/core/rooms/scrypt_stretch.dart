import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// HMAC / scrypt context string from TS §8.7 (`"KERYX.v1"`).
const keryxContext = 'KERYX.v1';

/// Pinned scrypt parameters for keyed derivation.
///
/// Spec-silent (TS §8.7 says only "scrypt-stretched"). Chosen for a
/// ~32 MiB, ~100 ms stretch on a mid-range phone — enough that a
/// numbered-channel enumerator cannot brute keyed rooms, cheap enough
/// to run at join. Salt is the context string so the stretch is
/// deterministic across devices given the same passphrase.
///
/// Implemented in this file against RFC 7914 using `package:crypto`
/// HMAC-SHA256. `pointycastle` is only a transitive dep and
/// `pubspec.yaml` is frozen, so we do not import it.
abstract final class KeyedScrypt {
  /// CPU/memory cost. Must be a power of two.
  static const int n = 32768; // 2^15

  static const int r = 8;
  static const int p = 1;
  static const int dkLen = 32;

  /// Fixed salt. RoomIds must match on every device; a random salt
  /// would fork the namespace.
  static const String salt = keryxContext;
}

/// scrypt-stretches a keyed-channel passphrase (TS §8.7).
Uint8List stretchPassphrase(String passphrase) {
  return scrypt(
    utf8.encode(passphrase),
    utf8.encode(KeyedScrypt.salt),
    n: KeyedScrypt.n,
    r: KeyedScrypt.r,
    p: KeyedScrypt.p,
    dkLen: KeyedScrypt.dkLen,
  );
}

/// RFC 7914 scrypt. Exposed for the RFC test-vector suite.
Uint8List scrypt(
  List<int> password,
  List<int> salt, {
  required int n,
  required int r,
  required int p,
  required int dkLen,
}) {
  if (n < 2 || (n & (n - 1)) != 0) {
    throw ArgumentError.value(n, 'n', 'must be a power of two greater than 1');
  }
  if (r < 1 || p < 1 || dkLen < 1) {
    throw ArgumentError('r, p, and dkLen must be positive');
  }

  final blockSize = 128 * r;
  final b = pbkdf2HmacSha256(password, salt, 1, p * blockSize);
  final xy = Uint8List(blockSize);
  final v = Uint8List(blockSize * n);
  for (var i = 0; i < p; i++) {
    final offset = i * blockSize;
    _romix(b, offset, n, r, v, xy);
  }
  return pbkdf2HmacSha256(password, b, 1, dkLen);
}

/// PBKDF2-HMAC-SHA256 (RFC 2898 / RFC 7914).
Uint8List pbkdf2HmacSha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int dkLen,
) {
  final hmac = Hmac(sha256, password);
  final out = Uint8List(dkLen);
  var written = 0;
  var blockIndex = 1;
  while (written < dkLen) {
    final blockSalt = Uint8List(salt.length + 4);
    blockSalt.setAll(0, salt);
    blockSalt[salt.length] = (blockIndex >> 24) & 0xff;
    blockSalt[salt.length + 1] = (blockIndex >> 16) & 0xff;
    blockSalt[salt.length + 2] = (blockIndex >> 8) & 0xff;
    blockSalt[salt.length + 3] = blockIndex & 0xff;
    var u = Uint8List.fromList(hmac.convert(blockSalt).bytes);
    final t = Uint8List.fromList(u);
    for (var c = 1; c < iterations; c++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var k = 0; k < t.length; k++) {
        t[k] ^= u[k];
      }
    }
    final take = (dkLen - written).clamp(0, t.length);
    out.setRange(written, written + take, t);
    written += take;
    blockIndex++;
  }
  return out;
}

void _romix(Uint8List b, int offset, int n, int r, Uint8List v, Uint8List xy) {
  final blockSize = 128 * r;
  xy.setRange(0, blockSize, b, offset);
  for (var i = 0; i < n; i++) {
    v.setRange(i * blockSize, (i + 1) * blockSize, xy);
    _blockMix(xy, r);
  }
  for (var i = 0; i < n; i++) {
    final j = _integerify(xy, r) & (n - 1);
    _xorBlocks(xy, v, j * blockSize, blockSize);
    _blockMix(xy, r);
  }
  b.setRange(offset, offset + blockSize, xy);
}

void _blockMix(Uint8List b, int r) {
  final blockCount = 2 * r;
  final x = Uint8List(64);
  x.setRange(0, 64, b, (blockCount - 1) * 64);
  final y = Uint8List(blockCount * 64);
  for (var i = 0; i < blockCount; i++) {
    _xorBlocks(x, b, i * 64, 64);
    _salsa20_8(x);
    // Even blocks then odd blocks (RFC 7914 scryptBlockMix).
    final dest = (i ~/ 2 + (i.isOdd ? r : 0)) * 64;
    y.setRange(dest, dest + 64, x);
  }
  b.setRange(0, y.length, y);
}

int _integerify(Uint8List x, int r) {
  final offset = (2 * r - 1) * 64;
  return ByteData.sublistView(x, offset, offset + 4).getUint32(0, Endian.little);
}

void _xorBlocks(Uint8List dest, Uint8List src, int srcOffset, int length) {
  for (var i = 0; i < length; i++) {
    dest[i] ^= src[srcOffset + i];
  }
}

void _salsa20_8(Uint8List block) {
  final x = Uint32List(16);
  final orig = Uint32List(16);
  final view = ByteData.sublistView(block);
  for (var i = 0; i < 16; i++) {
    final w = view.getUint32(i * 4, Endian.little);
    x[i] = w;
    orig[i] = w;
  }
  for (var i = 0; i < 4; i++) {
    _quarter(x, 0, 4, 8, 12);
    _quarter(x, 5, 9, 13, 1);
    _quarter(x, 10, 14, 2, 6);
    _quarter(x, 15, 3, 7, 11);
    _quarter(x, 0, 1, 2, 3);
    _quarter(x, 5, 6, 7, 4);
    _quarter(x, 10, 11, 8, 9);
    _quarter(x, 15, 12, 13, 14);
  }
  for (var i = 0; i < 16; i++) {
    view.setUint32(i * 4, _add32(x[i], orig[i]), Endian.little);
  }
}

void _quarter(Uint32List x, int a, int b, int c, int d) {
  x[b] ^= _rotl32(_add32(x[a], x[d]), 7);
  x[c] ^= _rotl32(_add32(x[b], x[a]), 9);
  x[d] ^= _rotl32(_add32(x[c], x[b]), 13);
  x[a] ^= _rotl32(_add32(x[d], x[c]), 18);
}

int _add32(int a, int b) => (a + b) & 0xffffffff;

int _rotl32(int v, int n) {
  final u = v & 0xffffffff;
  return ((u << n) | (u >> (32 - n))) & 0xffffffff;
}
