/// Install identity: peerId derivation, NATO callsigns, collision display.
///
/// TS §8.6 / FR-068 / KRX-075. Callsigns are display-only. peerId is
/// the sole arbiter-election input.
library;

export 'callsign.dart';
export 'collision.dart';
export 'identity_repository.dart';
export 'identity_store.dart';
export 'install_uuid.dart';
export 'peer_id.dart';
export 'rfc4648_base32.dart';
