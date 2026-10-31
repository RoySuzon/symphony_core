import 'dart:convert';

import '../../../core/error/failure.dart';
import 'key_value_storage.dart';
import 'storage_failure_codes.dart';

/// JSON helpers available on every [KeyValueStorage].
///
/// Values are stored as JSON strings, so they work with any backend:
///
/// ```dart
/// final storage = ref.read(secureStorageProvider);
/// await storage.writeJson('profile', {'name': 'Ada', 'theme': 'dark'});
/// final profile = await storage.readJson('profile'); // {name: Ada, ...}
///
/// await storage.writeJsonList('recent_searches', ['flutter', 'dart']);
/// final recent = await storage.readJsonList('recent_searches');
/// ```
///
/// Reading never throws because of bad data: a value that is not valid JSON,
/// or not of the expected JSON type, is reported as `null` (and left
/// untouched). Backend errors are still thrown as [StorageFailure]s.
extension JsonKeyValueStorageX on KeyValueStorage {
  /// Reads the JSON object stored under [key].
  ///
  /// Returns `null` when [key] does not exist or when its value is not a
  /// valid JSON object (corrupted, or written in another format).
  ///
  /// Throws a [StorageFailure] when the storage cannot be read.
  Future<Map<String, Object?>?> readJson(String key) async {
    final decoded = _tryDecodeJson(await read(key));
    return decoded is Map<String, Object?> ? decoded : null;
  }

  /// Stores [value] under [key] as a JSON object, replacing any previous
  /// value.
  ///
  /// [value] must only contain JSON-encodable values (`null`, `bool`, `num`,
  /// `String`, lists, maps with `String` keys, or objects with a `toJson()`
  /// method). Throws a [StorageFailure] with code
  /// [StorageFailureCodes.encode] when it cannot be encoded, or when the
  /// storage cannot be written.
  Future<void> writeJson(String key, Map<String, Object?> value) async {
    await write(key, _encodeJson(value));
  }

  /// Reads the JSON array stored under [key].
  ///
  /// Returns `null` when [key] does not exist or when its value is not a
  /// valid JSON array (corrupted, or written in another format).
  ///
  /// Throws a [StorageFailure] when the storage cannot be read.
  Future<List<Object?>?> readJsonList(String key) async {
    final decoded = _tryDecodeJson(await read(key));
    return decoded is List<Object?> ? decoded : null;
  }

  /// Stores [value] under [key] as a JSON array, replacing any previous
  /// value.
  ///
  /// Throws a [StorageFailure] with code [StorageFailureCodes.encode] when
  /// [value] cannot be encoded, or when the storage cannot be written.
  Future<void> writeJsonList(String key, List<Object?> value) async {
    await write(key, _encodeJson(value));
  }
}

Object? _tryDecodeJson(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

String _encodeJson(Object value) {
  try {
    return jsonEncode(value);
  } on Object catch (error, stackTrace) {
    // JsonUnsupportedObjectError / JsonCyclicError, or an error thrown by a
    // nested toJson() method.
    throw StorageFailure(
      'Unable to save the data.',
      code: StorageFailureCodes.encode,
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
