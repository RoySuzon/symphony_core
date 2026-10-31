/// Converts values of type [T] to and from JSON-compatible maps so that any
/// [LocalDatabase] adapter can persist them.
///
/// Encoded maps should only contain JSON-compatible values: `null`, `bool`,
/// `num`, `String`, and lists or `String`-keyed maps of those. Convert
/// `DateTime`s, enums and nested models explicitly (for example with
/// `toIso8601String()`, `name` and their own `toJson()`).
///
/// Most models already have the required pair of functions:
///
/// ```dart
/// final todoCodec = StorageCodec<Todo>.json(
///   fromJson: Todo.fromJson,
///   toJson: (todo) => todo.toJson(),
/// );
/// ```
///
/// Extend this class for more elaborate conversions (versioned payloads,
/// migrations...).
abstract class StorageCodec<T> {
  /// Allows subclasses to have const constructors.
  const StorageCodec();

  /// Creates a codec from a pair of functions, typically a model's
  /// `fromJson` factory and `toJson` method.
  const factory StorageCodec.json({
    required T Function(Map<String, Object?> json) fromJson,
    required Map<String, Object?> Function(T value) toJson,
  }) = _FunctionStorageCodec<T>;

  /// Converts [value] into a JSON-compatible map.
  Map<String, Object?> encode(T value);

  /// Restores a value from a map produced by [encode].
  ///
  /// May throw (typically a `FormatException` or a `TypeError`) when [json]
  /// is invalid; stores report such errors as a `StorageFailure` with code
  /// `StorageFailureCodes.decode`.
  T decode(Map<String, Object?> json);
}

/// [StorageCodec] delegating to a pair of functions.
class _FunctionStorageCodec<T> extends StorageCodec<T> {
  const _FunctionStorageCodec({
    required T Function(Map<String, Object?> json) fromJson,
    required Map<String, Object?> Function(T value) toJson,
  })  : _fromJson = fromJson,
        _toJson = toJson;

  final T Function(Map<String, Object?> json) _fromJson;
  final Map<String, Object?> Function(T value) _toJson;

  @override
  Map<String, Object?> encode(T value) => _toJson(value);

  @override
  T decode(Map<String, Object?> json) => _fromJson(json);
}

/// A named, typed collection of values identified by string ids, provided by
/// a [LocalDatabase].
///
/// Every operation is asynchronous and reports problems as a
/// `StorageFailure` (see `StorageFailureCodes` for the possible codes).
///
/// ```dart
/// final todos = ref.watch(localDatabaseProvider).store('todos', todoCodec);
///
/// await todos.put(todo.id, todo);
/// final all = await todos.getAll();
///
/// // In a provider: rebuilds the UI whenever the collection changes.
/// final todosProvider = StreamProvider<List<Todo>>(
///   (ref) => ref.watch(todosStoreProvider).watchAll(),
/// );
/// ```
abstract class LocalStore<T> {
  /// Allows subclasses to have const constructors.
  const LocalStore();

  /// Returns the value stored under [id], or `null` when there is none.
  Future<T?> get(String id);

  /// Returns every value of the store.
  ///
  /// The order is implementation-defined; the bundled implementations keep
  /// insertion order (updating a value keeps its position).
  Future<List<T>> getAll();

  /// Stores [value] under [id], replacing any previous value.
  Future<void> put(String id, T value);

  /// Stores every entry of [values] (id to value), replacing previous values
  /// with the same ids.
  ///
  /// Implementations should apply the whole batch or nothing.
  Future<void> putAll(Map<String, T> values);

  /// Removes the value stored under [id]. Does nothing when there is none.
  Future<void> delete(String id);

  /// Removes every value of the store.
  Future<void> clear();

  /// Watches every value of the store.
  ///
  /// The stream emits the current values (as [getAll] would return them) as
  /// soon as it is listened to, then the new values after every change made
  /// through this store. Problems are emitted as `StorageFailure` errors
  /// without ending the stream. It never completes on its own: the streams
  /// of a store obtained from a [LocalDatabase] complete when the database
  /// is closed; cancel the subscription otherwise.
  ///
  /// The bundled implementations return a stream that can be listened to
  /// several times, each listener receiving the current values first.
  Stream<List<T>> watchAll();

  /// Returns the number of values in the store.
  Future<int> count();
}

/// A pluggable local database made of named [LocalStore]s.
///
/// `symphony_core` never forces a particular database engine. It ships two
/// lightweight implementations:
///
/// * `InMemoryLocalDatabase`: volatile, for tests, previews and prototypes.
///   It is the default value of `localDatabaseProvider`.
/// * `KeyValueLocalDatabase`: persists each store as a single JSON document
///   in a `KeyValueStorage` (for example the secure storage). Suited to small
///   data sets such as settings, drafts or a few hundred cached records.
///
/// For anything bigger, adapt the engine of your choice (Hive, Isar, Drift,
/// sqflite, ObjectBox...) by implementing [LocalDatabase] and [LocalStore],
/// then override `localDatabaseProvider`:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     localDatabaseProvider.overrideWith((ref) {
///       final database = HiveLocalDatabase();
///       ref.onDispose(database.close);
///       return database;
///     }),
///   ],
///   child: const MyApp(),
/// );
/// ```
///
/// ## Lifecycle
///
/// A database is closed when created. [open] prepares it and [close]
/// releases its resources and completes every [LocalStore.watchAll] stream.
/// Stores can be obtained at any time: the bundled implementations open the
/// database automatically on first use (and again after [close]), so calling
/// [open] eagerly is only useful to surface initialization errors early, for
/// example during the splash screen. Adapters should behave the same way,
/// with an idempotent [open].
///
/// ## Writing an adapter
///
/// Store each value as the JSON produced by the store's [StorageCodec] and
/// keep one [LocalStore] per name. A Hive adapter (using `hive_flutter`)
/// looks like this:
///
/// ```dart
/// class HiveLocalDatabase extends LocalDatabase {
///   final _stores = <String, LocalStore<Object?>>{};
///   Future<void>? _opening;
///
///   @override
///   bool get isOpen => _opening != null;
///
///   @override
///   Future<void> open() => _opening ??= Hive.initFlutter();
///
///   @override
///   Future<void> close() async {
///     _opening = null;
///     await Hive.close(); // Closes every opened box.
///   }
///
///   @override
///   LocalStore<T> store<T>(String name, StorageCodec<T> codec) =>
///       _stores.putIfAbsent(name, () => HiveLocalStore<T>(this, name, codec))
///           as LocalStore<T>;
/// }
///
/// class HiveLocalStore<T> extends LocalStore<T> {
///   HiveLocalStore(this._database, this._name, this._codec);
///
///   final HiveLocalDatabase _database;
///   final String _name;
///   final StorageCodec<T> _codec;
///
///   Future<Box<String>> _box() async {
///     await _database.open();
///     return Hive.openBox<String>(_name); // Reuses the box once opened.
///   }
///
///   T _decode(String raw) =>
///       _codec.decode(jsonDecode(raw) as Map<String, Object?>);
///
///   String _encode(T value) => jsonEncode(_codec.encode(value));
///
///   @override
///   Future<T?> get(String id) async {
///     final raw = (await _box()).get(id);
///     return raw == null ? null : _decode(raw);
///   }
///
///   @override
///   Future<List<T>> getAll() async =>
///       (await _box()).values.map(_decode).toList();
///
///   @override
///   Future<void> put(String id, T value) async =>
///       (await _box()).put(id, _encode(value));
///
///   @override
///   Future<void> putAll(Map<String, T> values) async => (await _box())
///       .putAll(values.map((id, value) => MapEntry(id, _encode(value))));
///
///   @override
///   Future<void> delete(String id) async => (await _box()).delete(id);
///
///   @override
///   Future<void> clear() async => (await _box()).clear();
///
///   @override
///   Future<int> count() async => (await _box()).length;
///
///   @override
///   Stream<List<T>> watchAll() async* {
///     final box = await _box();
///     yield box.values.map(_decode).toList();
///     yield* box.watch().map((_) => box.values.map(_decode).toList());
///   }
/// }
/// ```
///
/// Remember to wrap engine errors into `StorageFailure`s so the rest of the
/// application only deals with `Failure`s.
///
/// * **Drift / sqflite**: use one table such as
///   `entries(store TEXT, id TEXT, data TEXT, PRIMARY KEY (store, id))`
///   where `data` holds `jsonEncode(codec.encode(value))`. With Drift,
///   implement [LocalStore.watchAll] with a `select(...).watch()` query;
///   with sqflite, emit from a `StreamController` after each write. Run
///   [LocalStore.putAll] in a transaction.
/// * **Isar / ObjectBox**: declare an entry collection with `store`, `id` and
///   `data` (JSON string) fields, or generate one collection per model and
///   map it in the codec. Use the engine's `watch(fireImmediately: true)`
///   queries for [LocalStore.watchAll].
abstract class LocalDatabase {
  /// Allows subclasses to have const constructors.
  const LocalDatabase();

  /// Whether the database is currently open.
  bool get isOpen;

  /// Opens the database. Calling it while the database is open does
  /// nothing.
  Future<void> open();

  /// Closes the database, releasing its resources and completing every
  /// [LocalStore.watchAll] stream. Calling it while the database is closed
  /// does nothing.
  Future<void> close();

  /// Returns the store named [name], whose values are converted with
  /// [codec].
  ///
  /// Calling it again with the same [name] returns the same store (the
  /// first [codec] is kept). Implementations throw an [ArgumentError] when
  /// [name] is empty and a [StateError] when [name] is already used with a
  /// different value type.
  LocalStore<T> store<T>(String name, StorageCodec<T> codec);
}
