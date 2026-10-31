import 'dart:convert';

import '../../../core/error/failure.dart';
import '../domain/local_database.dart';
import '../domain/storage_failure_codes.dart';
import 'storage_support.dart';

const String _defaultFailureMessage = 'Unable to process the stored data.';

/// Volatile [LocalStore] keeping its values in memory.
///
/// Use it in tests (as a fake store), previews and prototypes. Data is lost
/// when the instance is garbage collected.
///
/// When a [codec] is given (always the case for stores created by
/// [InMemoryLocalDatabase]), each value is converted to JSON on write and
/// back on read, exactly like a persistent store would do: callers never
/// share instances with the store and codec mistakes (for example a
/// `DateTime` left in an encoded map) surface immediately. Without a codec,
/// values are kept as-is, so prefer immutable values.
///
/// ```dart
/// final store = InMemoryLocalStore<Todo>(
///   initialValues: {'1': const Todo(id: '1', title: 'Buy milk')},
/// );
/// final repository = TodoRepository(store);
/// ```
class InMemoryLocalStore<T> extends LocalStore<T> {
  /// Creates a standalone in-memory store pre-filled with [initialValues].
  ///
  /// [failureMessage] is the user-facing message of the thrown
  /// `StorageFailure`s (override it to localize). Throws a `StorageFailure`
  /// with code [StorageFailureCodes.encode] when [codec] cannot encode one of
  /// [initialValues].
  InMemoryLocalStore({
    StorageCodec<T>? codec,
    Map<String, T>? initialValues,
    String failureMessage = _defaultFailureMessage,
  }) : this._(null, codec, initialValues, failureMessage);

  InMemoryLocalStore._(
    this._database,
    this.codec,
    Map<String, T>? initialValues,
    this.failureMessage,
  ) {
    if (initialValues != null) {
      _entries.addAll(initialValues.map(_encodeEntry));
    }
  }

  final InMemoryLocalDatabase? _database;

  /// Codec used to copy values on write and read, or `null` to keep values
  /// as-is.
  final StorageCodec<T>? codec;

  /// Message of the `StorageFailure`s thrown by this store (codec errors).
  final String failureMessage;

  /// Values by id: JSON strings when [codec] is set, `T` instances otherwise.
  final Map<String, Object?> _entries = <String, Object?>{};

  final StoreWatchers<T> _watchers = StoreWatchers<T>();

  Type get _valueType => T;

  @override
  Future<T?> get(String id) async {
    _markUsed();
    if (!_entries.containsKey(id)) return null;
    return _decode(_entries[id]);
  }

  @override
  Future<List<T>> getAll() async {
    _markUsed();
    return _snapshot();
  }

  @override
  Future<void> put(String id, T value) async {
    _markUsed();
    _entries[id] = _encode(value);
    _notify();
  }

  @override
  Future<void> putAll(Map<String, T> values) async {
    _markUsed();
    if (values.isEmpty) return;
    // Encode everything first so that a failing value leaves the store
    // untouched.
    final encoded = values.map(_encodeEntry);
    _entries.addAll(encoded);
    _notify();
  }

  @override
  Future<void> delete(String id) async {
    _markUsed();
    if (!_entries.containsKey(id)) return;
    _entries.remove(id);
    _notify();
  }

  @override
  Future<void> clear() async {
    _markUsed();
    if (_entries.isEmpty) return;
    _entries.clear();
    _notify();
  }

  @override
  Future<int> count() async {
    _markUsed();
    return _entries.length;
  }

  @override
  Stream<List<T>> watchAll() => _watchers.watch((controller) {
        _markUsed();
        try {
          _watchers.start(controller, _snapshot());
        } on Object catch (error, stackTrace) {
          _watchers.startWithError(controller, error, stackTrace);
        }
      });

  /// Stores of a database open it on first use (see [LocalDatabase]).
  void _markUsed() {
    _database?._isOpen = true;
  }

  List<T> _snapshot() => List<T>.unmodifiable(_entries.values.map<T>(_decode));

  void _notify() {
    if (!_watchers.hasActiveWatchers) return;
    try {
      _watchers.emit(_snapshot());
    } on Object catch (error, stackTrace) {
      _watchers.emitError(error, stackTrace);
    }
  }

  MapEntry<String, Object?> _encodeEntry(String id, T value) =>
      MapEntry<String, Object?>(id, _encode(value));

  Object? _encode(T value) {
    final codec = this.codec;
    if (codec == null) return value;
    try {
      return jsonEncode(codec.encode(value));
    } on Object catch (error, stackTrace) {
      throw StorageFailure(
        failureMessage,
        code: StorageFailureCodes.encode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  T _decode(Object? entry) {
    final codec = this.codec;
    if (codec == null) return entry as T;
    try {
      return codec.decode(jsonDecode(entry as String) as Map<String, Object?>);
    } on Object catch (error, stackTrace) {
      throw StorageFailure(
        failureMessage,
        code: StorageFailureCodes.decode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Volatile [LocalDatabase] whose stores live in memory.
///
/// It is the default value of `localDatabaseProvider`, which makes the local
/// database usable in tests, previews and prototypes without any setup.
/// Production applications override `localDatabaseProvider` with a
/// persistent implementation (`KeyValueLocalDatabase` or an adapter for
/// their engine of choice, see [LocalDatabase]).
///
/// Values go through each store's codec and JSON, like they would in a
/// persistent database. Data survives [close] / [open] cycles of the same
/// instance but is lost when the instance is discarded.
class InMemoryLocalDatabase extends LocalDatabase {
  /// Creates an empty in-memory database.
  ///
  /// [failureMessage] is the user-facing message of the `StorageFailure`s
  /// thrown by the stores (override it to localize).
  InMemoryLocalDatabase({this.failureMessage = _defaultFailureMessage});

  /// Message of the `StorageFailure`s thrown by the stores.
  final String failureMessage;

  final Map<String, InMemoryLocalStore<Object?>> _stores =
      <String, InMemoryLocalStore<Object?>>{};

  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> open() async {
    _isOpen = true;
  }

  @override
  Future<void> close() async {
    _isOpen = false;
    for (final store in _stores.values) {
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
      if (existing is InMemoryLocalStore<T> && existing._valueType == T) {
        return existing;
      }
      throw StateError(
        'The store "$name" already holds ${existing._valueType} values; '
        'it cannot be opened for $T values.',
      );
    }
    final created = InMemoryLocalStore<T>._(this, codec, null, failureMessage);
    _stores[name] = created;
    return created;
  }
}
