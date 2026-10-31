import 'package:flutter/foundation.dart';

/// A file sent in a multipart request by `ApiClient.upload`.
///
/// Use [UploadFile.fromBytes] on the web (file paths are not available
/// there).
@immutable
class UploadFile {
  /// A file read from [path] on the device.
  const UploadFile.fromPath(
    String this.path, {
    this.field = 'file',
    this.filename,
    this.contentType,
  }) : bytes = null;

  /// A file held in memory.
  const UploadFile.fromBytes(
    List<int> this.bytes, {
    required String this.filename,
    this.field = 'file',
    this.contentType,
  }) : path = null;

  /// Multipart field name.
  final String field;

  /// Device path of the file, when created with [UploadFile.fromPath].
  final String? path;

  /// File content, when created with [UploadFile.fromBytes].
  final List<int>? bytes;

  /// File name sent to the server. Defaults to the last segment of [path].
  final String? filename;

  /// MIME type, e.g. `image/png`. Detected by the server when omitted.
  final String? contentType;

  @override
  String toString() =>
      'UploadFile(field: $field, filename: ${filename ?? path})';
}
