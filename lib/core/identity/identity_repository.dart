import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'callsign.dart';
import 'identity_store.dart';
import 'install_uuid.dart';
import 'keys.dart';
import 'peer_id.dart';

/// Snapshot of the device identity.
///
/// [installUuid] is the v1 once-per-install UUID, kept only so external
/// call sites built against the pre-v2 shape keep compiling; it no longer
/// drives [peerId]. [keyPair] is the v2 Ed25519 identity (Technical §3.1);
/// it and [shortCode] are optional so a hand-built `DeviceIdentity` (as
/// several widget tests outside this task's `Owned_Paths` construct one)
/// still compiles without supplying real key material. [callsign] is
/// display-only and may be edited without touching either.
class DeviceIdentity {
  const DeviceIdentity({
    required this.installUuid,
    required this.peerId,
    required this.callsign,
    this.keyPair,
    this.shortCode,
  });

  final String installUuid;
  final String peerId;
  final Callsign callsign;
  final IdentityKeyPair? keyPair;
  final String? shortCode;

  /// The Ed25519 public key, when [keyPair] is a real v2 identity
  /// (Technical §3.1).
  Uint8List? get publicKey => keyPair?.publicKey;
}

/// Loads or creates the once-per-install identity: an Ed25519 key pair
/// (Technical §3.1), a legacy install UUID (kept for shape compatibility)
/// and a first-run NATO callsign.
class IdentityRepository {
  IdentityRepository(this._store, {Random? random})
    : _random = random ?? Random.secure();

  static const uuidKey = 'keryx.identity.install_uuid';
  static const callsignKey = 'keryx.identity.callsign';
  static const privateKeySeedKey = 'keryx.identity.ed25519_seed';

  final IdentityStore _store;
  final Random _random;

  /// Returns the persisted identity, creating an Ed25519 key pair and NATO
  /// callsign on first run. An existing v1 install (callsign present, no
  /// key) gets a fresh key pair and keeps its callsign (Technical §8); a
  /// corrupt stored seed, UUID or callsign is regenerated rather than
  /// crashing the first-run path.
  Future<DeviceIdentity> loadOrCreate() async {
    final uuid = await _loadOrCreateUuid();
    final keyPair = await _loadOrCreateKeyPair();
    final callsign = await _loadOrCreateCallsign();
    return DeviceIdentity(
      installUuid: uuid,
      peerId: derivePeerId(keyPair.publicKey),
      shortCode: deriveShortCode(keyPair.publicKey),
      callsign: callsign,
      keyPair: keyPair,
    );
  }

  /// Replaces the display callsign. The key pair (and so peerId) is
  /// unchanged.
  Future<DeviceIdentity> setCallsign(String raw) async {
    final next = Callsign.parse(raw);
    await _store.write(callsignKey, next.value);
    final current = await loadOrCreate();
    return DeviceIdentity(
      installUuid: current.installUuid,
      peerId: current.peerId,
      shortCode: current.shortCode,
      callsign: next,
      keyPair: current.keyPair,
    );
  }

  /// Restores an identity from a recovery-phrase-derived [keyPair],
  /// overwriting whatever key is currently stored (V2-FR-003). The
  /// callsign is left untouched here; the caller re-fetches the profile
  /// from the directory after restore (Technical §3.2).
  Future<void> restoreKeyPair(IdentityKeyPair keyPair) async {
    await _store.write(privateKeySeedKey, base64Encode(keyPair.seed));
  }

  Future<String> _loadOrCreateUuid() async {
    final existing = await _store.read(uuidKey);
    if (existing != null && isCanonicalUuid(existing)) {
      return existing;
    }
    final created = generateUuidV4(_random);
    await _store.write(uuidKey, created);
    return created;
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
