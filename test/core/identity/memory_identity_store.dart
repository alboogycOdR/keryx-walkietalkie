import 'package:keryx/core/identity/identity.dart';

/// In-process [IdentityStore] for tests. Not exported from the library.
class MemoryIdentityStore implements IdentityStore {
  MemoryIdentityStore([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  Map<String, String> get snapshot => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
