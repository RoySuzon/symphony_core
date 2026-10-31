/// Storage: centralized secure key/value storage, session persistence, JSON
/// helpers and pluggable local database interfaces.
///
/// * `KeyValueStorage` abstracts string key/value backends:
///   `SecureKeyValueStorage` (platform secure storage, the default),
///   `InMemoryKeyValueStorage` (tests) and the `PrefixedKeyValueStorage`
///   decorator. `JsonKeyValueStorageX` adds JSON helpers to all of them.
/// * `SessionStorage` / `SecureSessionStorage` persist the authentication
///   tokens and user.
/// * `LocalDatabase`, `LocalStore` and `StorageCodec` define an optional,
///   engine-agnostic local database with `InMemoryLocalDatabase` and
///   `KeyValueLocalDatabase` implementations; adapt any engine by
///   implementing them.
/// * `StorageFailureCodes` lists the codes of the `StorageFailure`s thrown
///   by this module.
/// * Riverpod entry points: `flutterSecureStorageProvider`,
///   `secureStorageProvider`, `sessionStorageProvider` and
///   `localDatabaseProvider`.
library;

export 'data/in_memory_key_value_storage.dart';
export 'data/in_memory_local_database.dart';
export 'data/key_value_local_database.dart';
export 'data/prefixed_key_value_storage.dart';
export 'data/secure_key_value_storage.dart';
export 'data/secure_session_storage.dart';
export 'domain/json_key_value_storage.dart';
export 'domain/key_value_storage.dart';
export 'domain/local_database.dart';
export 'domain/session_storage.dart';
export 'domain/storage_failure_codes.dart';
export 'presentation/storage_providers.dart';
