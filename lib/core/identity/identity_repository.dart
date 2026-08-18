import 'dart:math';

import 'callsign.dart';
import 'identity_store.dart';
import 'install_uuid.dart';
import 'peer_id.dart';

/// Snapshot of the install-scoped device identity.
///
/// [peerId] is derived from [installUuid] only. [callsign] is
/// display-only and may be edited without touching either.
class DeviceIdentity {
  const DeviceIdentity({
    required this.installUuid,
    required this.peerId,
    required this.callsign,
  });

  final String installUuid;
  final String peerId;
  final Callsign callsign;
}

/// Loads or creates the once-per-install UUID and first-run callsign.
class IdentityRepository {
  IdentityRepository(this._store, {Random? random})
    : _random = random ?? Random.secure();

  static const uuidKey = 'keryx.identity.install_uuid';
  static const callsignKey = 'keryx.identity.callsign';

  final IdentityStore _store;
  final Random _random;

  /// Returns the persisted identity, creating UUID + NATO callsign on
  /// first run. A corrupt stored UUID or callsign is regenerated
  /// rather than crashing the first-run path.
  Future<DeviceIdentity> loadOrCreate() async {
    final uuid = await _loadOrCreateUuid();
    final callsign = await _loadOrCreateCallsign();
    return DeviceIdentity(
      installUuid: uuid,
      peerId: derivePeerId(uuid),
      callsign: callsign,
    );
  }

  /// Replaces the display callsign. peerId and install UUID are unchanged.
  Future<DeviceIdentity> setCallsign(String raw) async {
    final next = Callsign.parse(raw);
    await _store.write(callsignKey, next.value);
    final current = await loadOrCreate();
    return DeviceIdentity(
      installUuid: current.installUuid,
      peerId: current.peerId,
      callsign: next,
    );
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
