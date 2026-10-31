/// Asynchronous string key/value storage abstraction.
///
/// The default implementation is backed by `flutter_secure_storage`
/// (`SecureKeyValueStorage`). Applications can plug any other backend
/// (shared preferences, Hive, an encrypted database...) by implementing this
/// interface; tests can use `InMemoryKeyValueStorage`.
///
/// Implementations should throw a `StorageFailure` when the backend fails.
abstract class KeyValueStorage {
  /// Allows subclasses to have const constructors.
  const KeyValueStorage();

  /// Returns the value stored under [key], or `null`.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any previous value.
  Future<void> write(String key, String value);

  /// Removes [key]. Does nothing when the key does not exist.
  Future<void> delete(String key);

  /// Whether a value is stored under [key].
  Future<bool> containsKey(String key);

  /// Returns every entry managed by this storage.
  Future<Map<String, String>> readAll();

  /// Removes every entry managed by this storage (and only those).
  Future<void> clear();
}
