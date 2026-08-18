import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tiny key-value boundary for install identity.
///
/// Deliberately not TASK-008's [SettingsStore] — that territory is
/// frozen and this package must stay import-free of `lib/core/settings`.
abstract interface class IdentityStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// flutter_secure_storage adapter. Same plugin as settings, own keys.
class SecureIdentityStore implements IdentityStore {
  SecureIdentityStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}
