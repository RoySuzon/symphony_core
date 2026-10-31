import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/error/failure.dart';
import '../domain/upload_file.dart';

/// Converts an [UploadFile] into a Dio [MultipartFile].
extension UploadFileMultipartConversion on UploadFile {
  /// Creates the [MultipartFile] sent for this file.
  ///
  /// Throws an [ArgumentError] when [UploadFile.contentType] is not a valid
  /// MIME type, and an [UnsupportedFailure] for a path based file on the web
  /// (use [UploadFile.fromBytes] there).
  Future<MultipartFile> toMultipartFile() async {
    final type = contentType;
    final parsed = type == null ? null : _parseContentType(type);
    // `Headers.jsonMimeType` is a media type instance available in every
    // supported Dio version; `change` derives the requested type from it
    // without depending on `package:http_parser` directly.
    final mediaType = parsed == null
        ? null
        : Headers.jsonMimeType.change(
            mimeType: parsed.$1,
            parameters: parsed.$2,
            clearParameters: true,
          );

    final content = bytes;
    if (content != null) {
      return MultipartFile.fromBytes(
        content,
        filename: filename,
        contentType: mediaType,
      );
    }
    final filePath = path;
    if (filePath == null) {
      throw ArgumentError('An UploadFile needs either bytes or a path.');
    }
    if (kIsWeb) {
      throw const UnsupportedFailure(
        'Uploading a file from a path is not supported on the web. '
        'Use UploadFile.fromBytes instead.',
      );
    }
    return MultipartFile.fromFile(
      filePath,
      filename: filename,
      contentType: mediaType,
    );
  }
}

/// Builds the `multipart/form-data` body sent by `ApiClient.upload`.
///
/// Every file in [files] is added under its [UploadFile.field] (several files
/// may share a field name). Form [fields] are converted as follows:
///
/// * `null` values are skipped;
/// * [UploadFile] and [MultipartFile] values are added as files;
/// * iterables add one entry per element under the same name;
/// * maps are JSON encoded;
/// * [DateTime]s use ISO-8601;
/// * anything else uses `toString()`.
Future<FormData> buildUploadFormData({
  List<UploadFile> files = const <UploadFile>[],
  Map<String, Object?> fields = const <String, Object?>{},
}) async {
  final formData = FormData();
  for (final entry in fields.entries) {
    await _addField(formData, entry.key, entry.value);
  }
  for (final file in files) {
    formData.files.add(MapEntry(file.field, await file.toMultipartFile()));
  }
  return formData;
}

Future<void> _addField(FormData formData, String name, Object? value) async {
  if (value == null) return;
  if (value is UploadFile) {
    formData.files.add(MapEntry(name, await value.toMultipartFile()));
  } else if (value is MultipartFile) {
    formData.files.add(MapEntry(name, value));
  } else if (value is Iterable<Object?>) {
    for (final item in value) {
      await _addField(formData, name, item);
    }
  } else if (value is Map) {
    formData.fields.add(MapEntry(name, jsonEncode(value)));
  } else if (value is DateTime) {
    formData.fields.add(MapEntry(name, value.toIso8601String()));
  } else {
    formData.fields.add(MapEntry(name, value.toString()));
  }
}

/// Splits `type/subtype; key=value` into the MIME type and its parameters.
(String, Map<String, String>) _parseContentType(String value) {
  final segments = value.split(';');
  final mimeType = segments.first.trim().toLowerCase();
  final parts = mimeType.split('/');
  final token = RegExp(r'^[a-z0-9!#$&^_.+\-]+$');
  if (parts.length != 2 ||
      !token.hasMatch(parts[0]) ||
      !token.hasMatch(parts[1])) {
    throw ArgumentError.value(
      value,
      'contentType',
      'Must be a MIME type such as "image/png"',
    );
  }
  final parameters = <String, String>{};
  for (final parameter in segments.skip(1)) {
    final separator = parameter.indexOf('=');
    if (separator <= 0) continue;
    final key = parameter.substring(0, separator).trim().toLowerCase();
    var paramValue = parameter.substring(separator + 1).trim();
    if (paramValue.length >= 2 &&
        paramValue.startsWith('"') &&
        paramValue.endsWith('"')) {
      paramValue = paramValue.substring(1, paramValue.length - 1);
    }
    if (key.isNotEmpty) parameters[key] = paramValue;
  }
  return (mimeType, parameters);
}
