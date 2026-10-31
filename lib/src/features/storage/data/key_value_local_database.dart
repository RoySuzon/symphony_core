import 'dart:async';
import 'dart:convert';

import '../../../core/error/failure.dart';
import '../domain/key_value_storage.dart';
import '../domain/local_database.dart';
import '../domain/storage_failure_codes.dart';
import 'storage_support.dart';

const String _defaultFailureMessage = 'Unable to access the local data.';

/// [LocalStore] persisting its whole collection as one JSON document under a
/// single [KeyValueStorage] key.
///
/// Every operation reads (and, for writes, rewrites) the whole collection,
/// so this store is meant for small data sets: settings, drafts, favorites,
/// a few hundred cached records. Use an adapter for a real database engine
/// for anything bigger (see [LocalDatabase]).
///
/// ```dart
/// final favorites = KeyValueLocalStore<Product>(
///   ref.watch(secureStorageProvider),
///   key: 'favorites',
///   codec: productCodec,
/// );
/// await favorites.put(product.id, product);
/// ```
///
/// The data is as protected as [storage]: it is encrypted when [storage] is
/// the secure storage. The document is a JSON array of
/// `{"id": ..., "value": ...}` objects (`value` being the codec output), in
/// insertion order; the key is removed when the collection becomes empty.
///
/// Operations of one instance run one at a time, so concurrent writes never
/// lose updates, and [watchAll] streams observe every change made through
/// this instance. Use a single instance per key (`KeyValueLocalDatabase`
/// does this for you).
///
/// When the persisted document is corrupted or a value cannot be decoded by
/// [codec], the affected operations throw a `StorageFailure` with code
/// [StorageFailureCodes.decode]; the data is left untouched so that it can be
/// migrated, and [clear] always works to reset the collection.
class KeyValueLocalStore<T> extends LocalStore<T> {
  /// Creates a store persisting its values in [storage] under [key], using
  /// [codec] to convert them.
  ///
  /// [failureMessage] is the user-facing message of the thrown
  /// `StorageFailure`s (override it to localize). Throws an [ArgumentError]
  /// when [key] is empty.
  KeyValueLocalStore(
    KeyValueStorage storage, {
    required String key,
    required StorageCodec<T> codec,
    String failureMessage = _defaultFailureMessage,
  }) : this._(null, storage, key, codec, failureMessage);

  KeyValueLocalStore._(
    this._database,
    this.storage,
    this.key,
    this.codec,
    this.failureMessage,
  ) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
  }

  final KeyValueLocalDatabase? _database;

  /// Backing storage.
  final KeyValueStorage storage;

  /// Key of [storage] holding the serialized collection.
  final String key;

  /// Converts values to and from JSON-compatible maps.
  final StorageCodec<T> codec;

  /// Message of the `StorageFailure`s thrown by this store.
  final String failureMessage;

  final SerialTaskQueue _queue = SerialTaskQueue();
  final StoreWatchers<T> _watchers = StoreWatchers<T>();

  Type get _valueType => T;

  @override
  Future<T?> get(String id) => _run(() async {
    final entries = await _readEntries();
    if (!entries.containsKey(id)) return null;
    return _decodeValue(entries[id]);
  });

  @override
  Future<List<T>> getAll() =>
      _run(() async => _decodeValues(await _readEntries()));

  @override
  Future<void> put(String id, T value) => _run(() async {
    final encoded = _encodeValue(value);
    final entries = await _readEntries();
    entries[id] = encoded;
    _notify(await _writeEntries(entries));
  });

  @override
  Future<void> putAll(Map<String, T> values) => _run(() async {
    if (values.isEmpty) return;
    // Encode everything first so that a failing value writes nothing.
    final encoded = values.map(
      (id, value) => MapEntry<String, Object?>(id, _encodeValue(value)),
    );
    final entries = await _readEntries();
    entries.addAll(encoded);
    _notify(await _writeEntries(entries));
  });

  @override
  Future<void> delete(String id) => _run(() async {
    final entries = await _readEntries();
    if (!entries.containsKey(id)) return;
    entries.remove(id);
    _notify(await _writeEntries(entries));
  });

  @override
  Future<void> clear() => _run(() async {
    final exists = await guardStorage(
      () => storage.containsKey(key),
      message: failureMessage,
      code: StorageFailureCodes.read,
    );
    if (!exists) return;
    await guardStorage(
      () => storage.delete(key),
      message: failureMessage,
      code: StorageFailureCodes.clear,
    );
    _notify(null);
  });

  @override
  Future<int> count() => _run(() async => (await _readEntries()).length);

  @override
  Stream<List<T>> watchAll() => _watchers.watch((controller) {
    // The initial snapshot is queued like any other operation, so it is
    // consistent with the changes notified afterwards.
    unawaited(
      _queue.run(() async {
        try {
          await _openDatabase();
          _watchers.start(controller, _decodeValues(await _readEntries()));
        } on Object catch (error, stackTrace) {
          _watchers.startWithError(controller, error, stackTrace);
        }
      }),
    );
  });

  /// Completes after every operation scheduled so far.
  Future<void> _drain() => _queue.run(() async {});

  Future<R> _run<R>(Future<R> Function() task) => _queue.run(() async {
    await _openDatabase();
    return task();
  });

  /// Stores of a database open it on first use (see [LocalDatabase]).
  Future<void> _openDatabase() async {
    final database = _database;
    if (database != null && !database.isOpen) await database.open();
  }

  /// Reads the collection: encoded values by id, in insertion order.
  Future<Map<String, Object?>> _readEntries() async {
    final raw = await guardStorage(
      () => storage.read(key),
      message: failureMessage,
      code: StorageFailureCodes.read,
    );
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    return _parseEntries(raw);
  }

  Map<String, Object?> _parseEntries(String raw) {
    final Object? document;
    try {
      document = jsonDecode(raw);
    } on FormatException catch (error, stackTrace) {
      throw _failure(StorageFailureCodes.decode, error, stackTrace);
    }
    if (document is! List<Object?>) {
      throw _corrupted('is not a JSON array');
    }
    final entries = <String, Object?>{};
    for (final item in document) {
      if (item is! Map<String, Object?>) {
        throw _corrupted('contains an entry that is not a JSON object');
      }
      final id = item['id'];
      if (id is! String) {
        throw _corrupted('contains an entry without a string "id"');
      }
      entries[id] = item['value'];
    }
    return entries;
  }

  /// Persists [entries] and returns the written document, or `null` when the
  /// collection is empty (the key is then removed).
  Future<String?> _writeEntries(Map<String, Object?> entries) async {
    if (entries.isEmpty) {
      await guardStorage(
        () => storage.delete(key),
        message: failureMessage,
        code: StorageFailureCodes.delete,
      );
      return null;
    }
    final String raw;
    try {
      raw = jsonEncode(<Object?>[
        for (final entry in entries.entries)
          <String, Object?>{'id': entry.key, 'value': entry.value},
      ]);
    } on Object catch (error, stackTrace) {
      throw _failure(StorageFailureCodes.encode, error, stackTrace);
    }
    await guardStorage(
      () => storage.write(key, raw),
      message: failureMessage,
      code: StorageFailureCodes.write,
    );
    return raw;
  }

  /// Sends the collection described by the written document [raw] (`null`
  /// for an empty collection) to the started [watchAll] streams.
  ///
  /// Values are decoded from the JSON document, exactly as later reads will
  /// see them.
  void _notify(String? raw) {
    if (!_watchers.hasActiveWatchers) return;
    try {
      _watchers.emit(
        raw == null
            ? List<T>.unmodifiable(<T>[])
            : _decodeValues(_parseEntries(raw)),
      );
    } on Object catch (error, stackTrace) {
      _watchers.emitError(error, stackTrace);
    }
  }

  Map<String, Object?> _encodeValue(T value) {
    try {
      return codec.encode(value);
    } on Object catch (error, stackTrace) {
      throw _failure(StorageFailureCodes.encode, error, stackTrace);
    }
  }

  T _decodeValue(Object? value) {
    try {
      return codec.decode(value as Map<String, Object?>);
    } on Object catch (error, stackTrace) {
      throw _failure(StorageFailureCodes.decode, error, stackTrace);
    }
  }

  List<T> _decodeValues(Map<String, Object?> entries) =>
      List<T>.unmodifiable(entries.values.map<T>(_decodeValue));

  StorageFailure _corrupted(String problem) => _failure(
    StorageFailureCodes.decode,
    FormatException('The collection stored under "$key" $problem.'),
    StackTrace.current,
  );

  StorageFailure _failure(String code, Object error, StackTrace stackTrace) =>
      StorageFailure(
        failureMessage,
        code: code,
        cause: error,
        stackTrace: stackTrace,
      );
}

/// [LocalDatabase] persisting each store as one JSON document in a
/// [KeyValueStorage], under the key `'$keyPrefix$name'`.
///
/// It needs no native database and works on every platform. Every store
/// operation reads (and rewrites) the whole store, so keep stores small;
/// adapt a database engine for larger data sets (see [LocalDatabase]).
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     localDatabaseProvider.overrideWith((ref) {
///       final database =
///           KeyValueLocalDatabase(ref.watch(secureStorageProvider));
///       ref.onDispose(database.close);
///       return database;
///     }),
///   ],
///   child: const MyApp(),
/// );
/// ```
///
/// See [KeyValueLocalStore] for the storage format and error handling.
class KeyValueLocalDatabase extends LocalDatabase {
  /// Creates a database whose stores are persisted in [storage].
  ///
  /// [keyPrefix] namespaces the keys written by the stores. [failureMessage]
  /// is the user-facing message of the `StorageFailure`s thrown by the
  /// stores (override it to localize).
  KeyValueLocalDatabase(
    this.storage, {
    this.keyPrefix = 'symphony.db.',
    this.failureMessage = _defaultFailureMessage,
  });

  /// Backing storage shared by every store.
  final KeyValueStorage storage;

  /// Prefix of the keys written by the stores.
  final String keyPrefix;

  /// Message of the `StorageFailure`s thrown by the stores.
  final String failureMessage;

  final Map<String, KeyValueLocalStore<Object?>> _stores =
      <String, KeyValueLocalStore<Object?>>{};

  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  /// Returns the [storage] key holding the store named [name].
  String keyFor(String name) => '$keyPrefix$name';

  @override
  Future<void> open() async {
    _isOpen = true;
  }

  /// Waits for the pending store operations, then closes the database and
  /// completes every [LocalStore.watchAll] stream.
  @override
  Future<void> close() async {
    final stores = _stores.values.toList();
    await Future.wait(stores.map((store) => store._drain()));
    _isOpen = false;
    for (final store in stores) {
      store._watchers.closeAll();
    }
  }

  @override
  LocalStore<T> store<T>(String name, StorageCodec<T> codec) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final existing = _stores[name];
    if (existing != null) {
      if (existing is KeyValueLocalStore<T> && existing._valueType == T) {
        return existing;
      }
      throw StateError(
        'The store "$name" already holds ${existing._valueType} values; '
        'it cannot be opened for $T values.',
      );
    }
    final created = KeyValueLocalStore<T>._(
      this,
      storage,
      keyFor(name),
      codec,
      failureMessage,
    );
    _stores[name] = created;
    return created;
  }
}
