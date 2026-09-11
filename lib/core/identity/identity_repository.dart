import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'callsign.dart';
import 'identity_store.dart';
import 'keys.dart';
import 'peer_id.dart';

/// Snapshot of the v2 device identity: an Ed25519 [keyPair], the [peerId]
/// and [shortCode] derived from its public key, and the display-only
/// [callsign] (Technical §3.1).
class DeviceIdentity {
  const DeviceIdentity({
    required this.keyPair,
    required this.peerId,
    required this.shortCode,
    required this.callsign,
  });

  final IdentityKeyPair keyPair;
  final String peerId;
  final String shortCode;
  final Callsign callsign;

  /// The Ed25519 public key — this *is* the identity (Technical §3.1).
  Uint8List get publicKey => keyPair.publicKey;
}

/// Loads or creates the once-per-install Ed25519 key pair and first-run
/// callsign.
class IdentityRepository {
  IdentityRepository(this._store, {Random? random})
    : _random = random ?? Random.secure();

  /// v1 legacy key, kept only so a pre-v2 install's callsign is found and
  /// preserved during migration (Technical §8); the UUID itself is no
  /// longer read for identity derivation.
  static const legacyUuidKey = 'keryx.identity.install_uuid';
  static const callsignKey = 'keryx.identity.callsign';
  static const privateKeySeedKey = 'keryx.identity.ed25519_seed';

  final IdentityStore _store;
  final Random _random;

  /// Returns the persisted identity, creating an Ed25519 key pair and NATO
  /// callsign on first run. An existing v1 install (callsign present, no
  /// key) gets a fresh key pair and keeps its callsign (Technical §8); a
  /// corrupt stored seed or callsign is regenerated rather than crashing
  /// the first-run path.
  Future<DeviceIdentity> loadOrCreate() async {
    final keyPair = await _loadOrCreateKeyPair();
    final callsign = await _loadOrCreateCallsign();
    return DeviceIdentity(
      keyPair: keyPair,
      peerId: derivePeerId(keyPair.publicKey),
      shortCode: deriveShortCode(keyPair.publicKey),
      callsign: callsign,
    );
  }

  /// Replaces the display callsign. The key pair (and so peerId) is
  /// unchanged.
  Future<DeviceIdentity> setCallsign(String raw) async {
    final next = Callsign.parse(raw);
    await _store.write(callsignKey, next.value);
    final current = await loadOrCreate();
    return DeviceIdentity(
      keyPair: current.keyPair,
      peerId: current.peerId,
      shortCode: current.shortCode,
      callsign: next,
    );
  }

  /// Restores an identity from a recovery-phrase-derived [keyPair],
  /// overwriting whatever key is currently stored (V2-FR-003). The
  /// callsign is left untouched here; the caller re-fetches the profile
  /// from the directory after restore (Technical §3.2).
  Future<void> restoreKeyPair(IdentityKeyPair keyPair) async {
    await _store.write(privateKeySeedKey, base64Encode(keyPair.seed));
  }

  Future<IdentityKeyPair> _loadOrCreateKeyPair() async {
    final existing = await _store.read(privateKeySeedKey);
    if (existing != null) {
      try {
        final seed = base64Decode(existing);
        if (seed.length == identityKeyLength) {
          return IdentityKeyPair.fromSeed(seed);
        }
      } on FormatException {
        // fall through and mint a fresh key
      }
    }
    final created = await IdentityKeyPair.generate();
    await _store.write(privateKeySeedKey, base64Encode(created.seed));
    return created;
  }

  Future<Callsign> _loadOrCreateCallsign() async {
    final existing = await _store.read(callsignKey);
    if (existing != null) {
      try {
        return Callsign.parse(existing);
      } on FormatException {
        // fall through and mint a fresh NATO name
      }
    }
    final created = Callsign.nato(_random);
    await _store.write(callsignKey, created.value);
    return created;
  }
}
