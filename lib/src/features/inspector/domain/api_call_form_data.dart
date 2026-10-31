import 'package:flutter/foundation.dart';

import '../../../core/logging/log_redactor.dart';

/// A file part of a captured `multipart/form-data` request.
///
/// Only metadata is captured: file contents never reach the inspector.
@immutable
class ApiCallFormFile {
  /// Creates a file part summary.
  const ApiCallFormFile({
    required this.field,
    required this.length,
    this.filename,
    this.contentType,
  });

  /// Name of the form field carrying the file.
  final String field;

  /// Size of the file part in bytes.
  final int length;

  /// File name sent to the server, if any.
  final String? filename;

  /// MIME type of the file part (e.g. `image/png`), if any.
  final String? contentType;

  /// Readable one-line description, e.g. `avatar.png (2048 bytes, image/png)`.
  String get description {
    final details = <String>[
      '$length bytes',
      if (contentType != null && contentType!.isNotEmpty) contentType!,
    ];
    return '${filename ?? field} (${details.join(', ')})';
  }

  @override
  bool operator ==(Object other) =>
      other is ApiCallFormFile &&
      other.field == field &&
      other.length == length &&
      other.filename == filename &&
      other.contentType == contentType;

  @override
  int get hashCode => Object.hash(field, length, filename, contentType);

  @override
  String toString() => 'ApiCallFormFile($field: $description)';
}

/// Summary of a captured `multipart/form-data` request body.
///
/// Text fields are kept (and redacted by [redact]); files are reduced to
/// their metadata ([ApiCallFormFile]).
@immutable
class ApiCallFormData {
  /// Creates a multipart body summary.
  const ApiCallFormData({
    this.fields = const <MapEntry<String, String>>[],
    this.files = const <ApiCallFormFile>[],
  });

  /// Text fields in sending order. Names may repeat (e.g. `tags[]`).
  final List<MapEntry<String, String>> fields;

  /// File parts in sending order.
  final List<ApiCallFormFile> files;

  /// Whether the body has neither fields nor files.
  bool get isEmpty => fields.isEmpty && files.isEmpty;

  /// Returns a copy whose field values are redacted with [redactor].
  ///
  /// Values of sensitive field names are replaced by [LogRedactor.mask];
  /// other values that contain JSON are deeply redacted.
  ApiCallFormData redact(LogRedactor redactor) {
    return ApiCallFormData(
      fields: List<MapEntry<String, String>>.unmodifiable(
        <MapEntry<String, String>>[
          for (final field in fields)
            MapEntry<String, String>(
              field.key,
              redactor.isSensitive(field.key)
                  ? redactor.mask
                  : '${redactor.redact(field.value)}',
            ),
        ],
      ),
      files: List<ApiCallFormFile>.unmodifiable(files),
    );
  }

  /// A JSON-friendly summary used to display the body:
  /// `{"fields": {...}, "files": {...}}`.
  ///
  /// Repeated names are grouped into lists and files are rendered with
  /// [ApiCallFormFile.description].
  Map<String, Object?> toSummary() {
    final fieldMap = <String, Object?>{};
    for (final field in fields) {
      _put(fieldMap, field.key, field.value);
    }
    final fileMap = <String, Object?>{};
    for (final file in files) {
      _put(fileMap, file.field, file.description);
    }
    return <String, Object?>{
      if (fieldMap.isNotEmpty) 'fields': fieldMap,
      if (fileMap.isNotEmpty) 'files': fileMap,
    };
  }

  static void _put(Map<String, Object?> target, String key, String value) {
    final existing = target[key];
    if (existing == null) {
      target[key] = value;
    } else if (existing is List<Object?>) {
      existing.add(value);
    } else {
      target[key] = <Object?>[existing, value];
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! ApiCallFormData) return false;
    if (other.fields.length != fields.length ||
        other.files.length != files.length) {
      return false;
    }
    for (var i = 0; i < fields.length; i++) {
      if (other.fields[i].key != fields[i].key ||
          other.fields[i].value != fields[i].value) {
        return false;
      }
    }
    for (var i = 0; i < files.length; i++) {
      if (other.files[i] != files[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(<Object>[
      for (final field in fields) Object.hash(field.key, field.value),
    ]),
    Object.hashAll(files),
  );

  @override
  String toString() =>
      'ApiCallFormData(fields: ${fields.length}, files: ${files.length})';
}
