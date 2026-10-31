import '../domain/key_value_storage.dart';

/// [KeyValueStorage] decorator that scopes another storage to the keys
/// starting with [prefix].
///
/// Use it to give each feature (or each signed-in user) its own namespace in
/// a shared backend, so that it can be cleared without touching the rest:
///
/// ```dart
/// final secure = ref.read(secureStorageProvider);
/// final userStorage = PrefixedKeyValueStorage(secure, 'user.$userId.');
///
/// await userStorage.write('draft', '...'); // Stored as `user.42.draft`.
/// await userStorage.clear(); // Only removes the `user.42.` keys.
/// ```
///
/// [readAll] only returns the prefixed entries (with the prefix removed).
/// Errors of [inner] are propagated unchanged. Prefixes can be nested by
/// decorating a [PrefixedKeyValueStorage].
class PrefixedKeyValueStorage extends KeyValueStorage {
  /// Creates a storage that stores every key of [inner] under [prefix].
  const PrefixedKeyValueStorage(this.inner, this.prefix);

  /// The decorated storage.
  final KeyValueStorage inner;

  /// Prefix added to every key. An empty prefix makes this storage a
  /// transparent pass-through.
  final String prefix;

  String _prefixed(String key) => '$prefix$key';

  @override
  Future<String?> read(String key) => inner.read(_prefixed(key));

  @override
  Future<void> write(String key, String value) =>
      inner.write(_prefixed(key), value);

  @override
  Future<void> delete(String key) => inner.delete(_prefixed(key));

  @override
  Future<bool> containsKey(String key) => inner.containsKey(_prefixed(key));

  @override
  Future<Map<String, String>> readAll() async {
    final entries = await inner.readAll();
    return Map<String, String>.unmodifiable(<String, String>{
      for (final entry in entries.entries)
        if (entry.key.startsWith(prefix))
          entry.key.substring(prefix.length): entry.value,
    });
  }

  @override
  Future<void> clear() async {
    if (prefix.isEmpty) {
      await inner.clear();
      return;
    }
    final entries = await inner.readAll();
    for (final key in entries.keys) {
      if (key.startsWith(prefix)) await inner.delete(key);
    }
  }
}
