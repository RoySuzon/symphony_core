import 'package:symphony_core/symphony_core.dart';

/// A [KeyValueStorage] that uses [primary] and switches to [fallback] for
/// the rest of the run the first time [primary] fails.
///
/// The example passes `SecureKeyValueStorage` (flutter_secure_storage) as
/// primary storage. Some environments cannot use it out of the box — for
/// instance a macOS build without the Keychain Sharing entitlement — and the
/// demo should still work there (sessions are then kept in memory only).
/// It also shows how an application plugs its own storage into
/// `SymphonyCore.initialize(secureStorage: ...)`.
class ResilientKeyValueStorage extends KeyValueStorage {
  /// Creates the storage.
  ResilientKeyValueStorage({
    required this.primary,
    required this.fallback,
    this.onFallback,
  });

  /// Preferred storage.
  final KeyValueStorage primary;

  /// Storage used once [primary] failed.
  final KeyValueStorage fallback;

  /// Called once, with the failure, when switching to [fallback].
  final void Function(Failure failure)? onFallback;

  bool _usingFallback = false;

  /// Whether [fallback] is in use.
  bool get isUsingFallback => _usingFallback;

  Future<T> _run<T>(
      Future<T> Function(KeyValueStorage storage) operation) async {
    if (!_usingFallback) {
      try {
        return await operation(primary);
      } on StorageFailure catch (failure) {
        _usingFallback = true;
        onFallback?.call(failure);
      }
    }
    return operation(fallback);
  }

  @override
  Future<String?> read(String key) => _run((storage) => storage.read(key));

  @override
  Future<void> write(String key, String value) =>
      _run((storage) => storage.write(key, value));

  @override
  Future<void> delete(String key) => _run((storage) => storage.delete(key));

  @override
  Future<bool> containsKey(String key) =>
      _run((storage) => storage.containsKey(key));

  @override
  Future<Map<String, String>> readAll() => _run((storage) => storage.readAll());

  @override
  Future<void> clear() => _run((storage) => storage.clear());
}
