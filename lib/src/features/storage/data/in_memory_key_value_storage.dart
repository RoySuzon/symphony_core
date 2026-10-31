import '../domain/key_value_storage.dart';

/// Volatile [KeyValueStorage] for tests, previews and platforms without a
/// secure storage implementation.
class InMemoryKeyValueStorage extends KeyValueStorage {
  /// Creates a storage pre-filled with [initialValues].
  InMemoryKeyValueStorage([Map<String, String>? initialValues])
      : _values = <String, String>{...?initialValues};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.unmodifiable(_values);

  @override
  Future<void> clear() async => _values.clear();
}
