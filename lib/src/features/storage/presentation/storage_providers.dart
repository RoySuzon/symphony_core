import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/in_memory_local_database.dart';
import '../data/secure_key_value_storage.dart';
import '../data/secure_session_storage.dart';
import '../domain/key_value_storage.dart';
import '../domain/local_database.dart';
import '../domain/session_storage.dart';

/// The platform secure storage plugin instance used by
/// [secureStorageProvider].
///
/// Override it to pass platform options (Android, iOS, web...):
///
/// ```dart
/// flutterSecureStorageProvider.overrideWithValue(
///   const FlutterSecureStorage(
///     iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
///   ),
/// );
/// ```
final flutterSecureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
  name: 'flutterSecureStorageProvider',
);

/// Prefix of every key that the default [secureStorageProvider] writes to the
/// platform secure storage (`'symphony.'`).
///
/// It scopes the package's entries, so that `clear()` and `readAll()` on the
/// default storage never touch the secure storage entries written by the
/// application itself or by other plugins.
const String symphonySecureStorageKeyPrefix = 'symphony.';

/// Secure key/value storage used for tokens and other secrets: a
/// `SecureKeyValueStorage` wrapping [flutterSecureStorageProvider].
///
/// Its keys are stored under [symphonySecureStorageKeyPrefix] (the key
/// `api_key` is stored as `symphony.api_key`), so `clear()` only removes the
/// entries written through this storage and `readAll()` only returns them.
///
/// Override it to plug another backend, or with `InMemoryKeyValueStorage()`
/// in tests:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     secureStorageProvider.overrideWithValue(InMemoryKeyValueStorage()),
///   ],
///   child: const MyApp(),
/// );
/// ```
final secureStorageProvider = Provider<KeyValueStorage>(
  (ref) => SecureKeyValueStorage(
    storage: ref.watch(flutterSecureStorageProvider),
    keyPrefix: symphonySecureStorageKeyPrefix,
  ),
  name: 'secureStorageProvider',
);

/// Persists the authentication session (tokens and user payload) in
/// [secureStorageProvider] through a `SecureSessionStorage`.
final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SecureSessionStorage(ref.watch(secureStorageProvider)),
  name: 'sessionStorageProvider',
);

/// The application's optional local database.
///
/// Defaults to a volatile `InMemoryLocalDatabase`, closed when the provider
/// is disposed. Applications that need persistence override it with
/// `KeyValueLocalDatabase` (small data sets) or with an adapter for their
/// database engine of choice (Hive, Isar, Drift, sqflite... see
/// [LocalDatabase]). An override created with `overrideWith` should close
/// its database in `ref.onDispose`:
///
/// ```dart
/// localDatabaseProvider.overrideWith((ref) {
///   final database = KeyValueLocalDatabase(ref.watch(secureStorageProvider));
///   ref.onDispose(database.close);
///   return database;
/// });
/// ```
///
/// Stores are then obtained from it, typically in their own providers:
///
/// ```dart
/// final todoStoreProvider = Provider<LocalStore<Todo>>(
///   (ref) => ref.watch(localDatabaseProvider).store('todos', todoCodec),
/// );
/// ```
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final database = InMemoryLocalDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
}, name: 'localDatabaseProvider');
