/// Machine readable `StorageFailure.code` values produced by the storage
/// module.
///
/// Every `StorageFailure` thrown by the bundled storages, stores and helpers
/// carries one of these codes, so applications can react to specific problems
/// or show their own localized message:
///
/// ```dart
/// try {
///   await todos.getAll();
/// } on StorageFailure catch (failure) {
///   if (failure.code == StorageFailureCodes.decode) {
///     // The persisted data is corrupted or incompatible: reset it.
///     await todos.clear();
///   }
/// }
/// ```
abstract final class StorageFailureCodes {
  /// Reading from the storage backend failed (`read`, `readAll`,
  /// `containsKey`).
  static const String read = 'storage_read_failed';

  /// Writing to the storage backend failed.
  static const String write = 'storage_write_failed';

  /// Deleting an entry from the storage backend failed.
  static const String delete = 'storage_delete_failed';

  /// Clearing the storage backend failed.
  static const String clear = 'storage_clear_failed';

  /// A value could not be serialized, for example because it contains
  /// objects that are not JSON-encodable or because a codec threw.
  static const String encode = 'storage_encode_failed';

  /// Persisted data could not be deserialized: it is corrupted or was
  /// written in an incompatible format (for example by an older codec).
  static const String decode = 'storage_decode_failed';
}
