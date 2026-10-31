import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_call_form_data.dart';
import 'api_call_record.dart';

/// Builds a [cURL](https://curl.se) command line reproducing a captured
/// call.
///
/// The command is built from the record only, so it contains **redacted**
/// data: masked headers, query parameters and body fields keep their mask
/// (e.g. `Authorization: ***`) and must be filled in by hand before
/// replaying the call. Truncated bodies stay truncated and binary/stream
/// bodies (which are never captured) are omitted.
///
/// Arguments are quoted for POSIX shells (bash, zsh, sh): every value is
/// wrapped in single quotes and embedded single quotes are written `'\''`.
///
/// ```dart
/// final command = const CurlCommandBuilder().build(record);
/// // curl -X POST -H 'content-type: application/json' --data-raw '{...}' 'https://api.example.com/login'
/// ```
@immutable
class CurlCommandBuilder {
  /// Creates a builder.
  const CurlCommandBuilder({
    this.multiline = false,
    this.excludedHeaders = defaultExcludedHeaders,
  });

  /// Headers skipped by default (lower case): `content-length` is computed
  /// by cURL itself and a stale value would corrupt the request.
  static const Set<String> defaultExcludedHeaders = <String>{'content-length'};

  /// Puts every argument on its own line, joined with ` \` continuations.
  final bool multiline;

  /// Lower-case names of request headers that are not emitted.
  final Set<String> excludedHeaders;

  static final RegExp _methodToken = RegExp(r'^[A-Z]+$');
  static final RegExp _safeFileName = RegExp(r'^[A-Za-z0-9._-]+$');

  /// Returns the cURL command for [record].
  String build(ApiCallRecord record) {
    final method = record.method.toUpperCase();
    final form = record.requestFormData;
    final arguments = <String>[
      'curl',
      if (method == 'HEAD')
        '--head'
      else
        '-X ${_methodToken.hasMatch(method) ? method : quote(method)}',
    ];

    var compressed = false;
    for (final header in record.requestHeaders.entries) {
      final name = header.key.toLowerCase();
      if (excludedHeaders.contains(name)) continue;
      if (name == 'accept-encoding') {
        // cURL negotiates and decodes compression itself.
        compressed = true;
        continue;
      }
      // cURL generates its own multipart boundary.
      if (form != null && name == 'content-type') continue;
      arguments.add('-H ${quote('${header.key}: ${header.value}')}');
    }
    if (compressed) arguments.add('--compressed');

    if (form != null) {
      arguments.addAll(_formArguments(form));
    } else {
      arguments.addAll(_bodyArguments(record));
    }

    arguments.add(quote(record.uri.toString()));
    return arguments.join(multiline ? ' \\\n  ' : ' ');
  }

  /// Quotes [value] as a single POSIX shell word.
  static String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  Iterable<String> _formArguments(ApiCallFormData form) sync* {
    for (final field in form.fields) {
      // --form-string never interprets a leading `@` or `<` as a file.
      yield '--form-string ${quote('${field.key}=${field.value}')}';
    }
    for (final file in form.files) {
      final name = file.filename ?? file.field;
      final reference = _safeFileName.hasMatch(name)
          ? name
          : '"${name.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
      final type = file.contentType;
      final suffix = type == null || type.isEmpty ? '' : ';type=$type';
      yield '-F ${quote('${file.field}=@$reference$suffix')}';
    }
  }

  Iterable<String> _bodyArguments(ApiCallRecord record) sync* {
    final body = record.requestBody;
    if (body == null || body.isEmpty || ApiCallRecord.isBodyPlaceholder(body)) {
      return;
    }
    final contentType = record.requestContentType?.toLowerCase() ?? '';
    if (contentType.startsWith('application/x-www-form-urlencoded')) {
      final fields = _decodeObject(body);
      if (fields != null) {
        for (final entry in fields.entries) {
          final values = entry.value is List<Object?>
              ? entry.value as List<Object?>
              : <Object?>[entry.value];
          for (final value in values) {
            yield '--data-urlencode '
                '${quote('${entry.key}=${_formValue(value)}')}';
          }
        }
        return;
      }
    }
    yield '--data-raw ${quote(body)}';
  }

  static Map<String, Object?>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Not JSON (for example truncated): sent verbatim.
    }
    return null;
  }

  static String _formValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return jsonEncode(value);
  }
}
