import 'dart:convert';

import '../../../core/error/failure.dart';
import '../../auth/domain/entities/auth_tokens.dart';
import '../domain/key_value_storage.dart';
import '../domain/session_storage.dart';
import '../domain/storage_failure_codes.dart';
import 'storage_support.dart';

/// [SessionStorage] that serializes the session as JSON into a
/// [KeyValueStorage] (secure storage by default).
///
/// The tokens are stored under [tokensKey] and the user payload under
/// [userKey], both derived from [namespace]:
///
/// ```dart
/// final sessionStorage = SecureSessionStorage(
///   const SecureKeyValueStorage(),
///   namespace: 'my_app',
/// );
/// await sessionStorage.writeTokens(tokens); // `my_app.session.tokens`
/// ```
///
/// Corrupted entries (invalid JSON, missing access token, wrong field types)
/// are deleted and reported as "no session", so a broken payload can never
/// lock a user out. Backend errors are thrown as `StorageFailure`s (errors
/// that already are `Failure`s are propagated unchanged).
class SecureSessionStorage extends SessionStorage {
  /// Creates a session storage writing into [storage] under [namespace].
  ///
  /// [failureMessage] is the user-facing message of the `StorageFailure`s
  /// thrown when [storage] fails with an error that is not a `Failure`
  /// (override it to localize).
  const SecureSessionStorage(
    this.storage, {
    this.namespace = 'symphony',
    this.failureMessage = 'Unable to access the session storage.',
  });

  /// Backing storage.
  final KeyValueStorage storage;

  /// Prefix of the keys written by this storage.
  final String namespace;

  /// Message of the `StorageFailure`s created by this storage.
  final String failureMessage;

  /// Key holding the serialized tokens.
  String get tokensKey => '$namespace.session.tokens';

  /// Key holding the serialized user.
  String get userKey => '$namespace.session.user';

  @override
  Future<AuthTokens?> readTokens() async {
    final json = await _readJson(tokensKey);
    if (json == null) return null;
    try {
      return AuthTokens.fromJson(json);
    } on Object {
      // FormatException (missing access token) or TypeError (a field of the
      // wrong type): the payload is unusable.
      await _safeDelete(tokensKey);
      return null;
    }
  }

  @override
  Future<void> writeTokens(AuthTokens tokens) =>
      _writeJson(tokensKey, tokens.toJson());

  @override
  Future<Map<String, Object?>?> readUser() => _readJson(userKey);

  @override
  Future<void> writeUser(Map<String, Object?> user) =>
      _writeJson(userKey, user);

  /// Removes the tokens and the user payload.
  ///
  /// Both entries are always attempted, so a failure on one of them does not
  /// leave the other behind; the first error is rethrown afterwards.
  @override
  Future<void> clear() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final key in <String>[tokensKey, userKey]) {
      try {
        await _guard(StorageFailureCodes.delete, () => storage.delete(key));
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<Map<String, Object?>?> _readJson(String key) async {
    final raw = await _guard(StorageFailureCodes.read, () => storage.read(key));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Fall through: corrupted payload.
    }
    await _safeDelete(key);
    return null;
  }

  Future<void> _writeJson(String key, Map<String, Object?> json) async {
    final String raw;
    try {
      raw = jsonEncode(json);
    } on Object catch (error, stackTrace) {
      throw StorageFailure(
        failureMessage,
        code: StorageFailureCodes.encode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    await _guard(StorageFailureCodes.write, () => storage.write(key, raw));
  }

  Future<void> _safeDelete(String key) async {
    try {
      await storage.delete(key);
    } on Object {
      // Ignore: best effort cleanup.
    }
  }

  Future<T> _guard<T>(String code, Future<T> Function() body) =>
      guardStorage(body, message: failureMessage, code: code);
}
