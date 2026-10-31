import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/key_value_storage.dart';
import '../domain/storage_failure_codes.dart';
import 'storage_support.dart';

/// [KeyValueStorage] backed by the platform secure storage through
/// `flutter_secure_storage`: the Keychain on iOS and macOS, Keystore-backed
/// encryption on Android and the platform equivalents on Linux, Windows and
/// the web.
///
/// This is the default implementation behind `secureStorageProvider` (which
/// uses the key prefix `symphonySecureStorageKeyPrefix`); use it for tokens
/// and other secrets.
///
/// ```dart
/// const storage = SecureKeyValueStorage(keyPrefix: 'my_app.');
/// await storage.write('api_key', 'secret'); // Stored as `my_app.api_key`.
/// ```
///
/// When [keyPrefix] is set, every key is transparently prefixed, [readAll]
/// only returns the prefixed entries (with the prefix removed) and [clear]
/// only removes those entries. Without a prefix the storage manages every
/// secure storage entry of the application: [clear] then deletes the entries
/// of the whole application, including those written by other code.
///
/// Every platform error (`PlatformException`, `MissingPluginException`,
/// unsupported platform...) is rethrown as a `StorageFailure` whose
/// `cause`/`stackTrace` hold the original error and whose `code` is one of
/// [StorageFailureCodes].
class SecureKeyValueStorage extends KeyValueStorage {
  /// Creates a secure storage.
  ///
  /// [storage] is the plugin instance; pass one configured with platform
  /// options when needed (defaults to `const FlutterSecureStorage()`).
  /// [failureMessage] is the user-facing message of the thrown
  /// `StorageFailure`s (override it to localize).
  const SecureKeyValueStorage({
    FlutterSecureStorage? storage,
    this.keyPrefix = '',
    this.failureMessage = 'Unable to access the secure storage.',
  }) : storage = storage ?? const FlutterSecureStorage();

  /// The underlying plugin instance.
  final FlutterSecureStorage storage;

  /// Prefix transparently added to every key (empty for none).
  final String keyPrefix;

  /// Message of the `StorageFailure`s thrown when the platform storage
  /// fails.
  final String failureMessage;

  String _prefixed(String key) => '$keyPrefix$key';

  @override
  Future<String?> read(String key) =>
      _guard(StorageFailureCodes.read, () => storage.read(key: _prefixed(key)));

  @override
  Future<void> write(String key, String value) => _guard(
    StorageFailureCodes.write,
    () => storage.write(key: _prefixed(key), value: value),
  );

  @override
  Future<void> delete(String key) => _guard(
    StorageFailureCodes.delete,
    () => storage.delete(key: _prefixed(key)),
  );

  @override
  Future<bool> containsKey(String key) => _guard(
    StorageFailureCodes.read,
    () => storage.containsKey(key: _prefixed(key)),
  );

  @override
  Future<Map<String, String>> readAll() =>
      _guard(StorageFailureCodes.read, () async {
        final entries = await storage.readAll();
        return Map<String, String>.unmodifiable(<String, String>{
          for (final entry in entries.entries)
            if (entry.key.startsWith(keyPrefix))
              entry.key.substring(keyPrefix.length): entry.value,
        });
      });

  @override
  Future<void> clear() => _guard(StorageFailureCodes.clear, () async {
    if (keyPrefix.isEmpty) {
      await storage.deleteAll();
      return;
    }
    final entries = await storage.readAll();
    for (final key in entries.keys) {
      if (key.startsWith(keyPrefix)) await storage.delete(key: key);
    }
  });

  Future<T> _guard<T>(String code, Future<T> Function() body) =>
      guardStorage(body, message: failureMessage, code: code);
}
