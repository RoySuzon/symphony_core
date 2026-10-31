import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Masks sensitive values (tokens, passwords, cookies, API keys...) before
/// they are written to logs or shown in the API inspector.
///
/// A key is considered sensitive when its normalized form (lower case, without
/// `-`, `_`, `.` and spaces) *contains* one of the normalized
/// [sensitiveKeys]. Over-masking is preferred to leaking a secret.
@immutable
class LogRedactor {
  /// Creates a redactor.
  const LogRedactor({
    this.sensitiveKeys = defaultSensitiveKeys,
    this.mask = defaultMask,
  });

  /// Keys masked by default.
  static const Set<String> defaultSensitiveKeys = <String>{
    'authorization',
    'password',
    'passwd',
    'token',
    'secret',
    'cookie',
    'apikey',
    'credential',
    'session',
  };

  /// Replacement used for masked values.
  static const String defaultMask = '***';

  /// Keys whose values are masked.
  final Set<String> sensitiveKeys;

  /// Replacement text for masked values.
  final String mask;

  static String _normalize(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[\s_\-.]'), '');

  /// Whether values stored under [key] must be masked.
  bool isSensitive(String key) {
    final normalized = _normalize(key);
    if (normalized.isEmpty) return false;
    for (final candidate in sensitiveKeys) {
      final c = _normalize(candidate);
      if (c.isNotEmpty && normalized.contains(c)) return true;
    }
    return false;
  }

  /// Returns a copy of [headers] with sensitive values masked.
  Map<String, String> redactHeaders(Map<String, dynamic> headers) {
    return <String, String>{
      for (final entry in headers.entries)
        entry.key: isSensitive(entry.key) ? mask : _headerValue(entry.value),
    };
  }

  static String _headerValue(Object? value) {
    if (value is List) return value.join(', ');
    return '$value';
  }

  /// Returns [uri] with sensitive query parameter values masked.
  ///
  /// A sensitive parameter appears once, with [mask] as its value (written
  /// as is when it only contains characters allowed in a query, which is the
  /// case of the default mask: `?token=***`). [uri] itself is returned when
  /// it has no sensitive parameter. A query that cannot be decoded (invalid
  /// percent-encoding) cannot be checked and is replaced by [mask] entirely.
  /// Never throws.
  Uri redactUri(Uri uri) {
    if (!uri.hasQuery) return uri;
    final Map<String, List<String>> params;
    try {
      params = uri.queryParametersAll;
    } on Object {
      return uri.replace(query: mask);
    }
    if (!params.keys.any(isSensitive)) return uri;
    final query = <String>[
      for (final entry in params.entries)
        if (isSensitive(entry.key))
          '${Uri.encodeQueryComponent(entry.key)}=$mask'
        else
          for (final value in entry.value)
            '${Uri.encodeQueryComponent(entry.key)}='
                '${Uri.encodeQueryComponent(value)}',
    ].join('&');
    return uri.replace(query: query);
  }

  /// Deeply masks sensitive entries of maps and lists.
  ///
  /// Strings that contain a JSON object or array are decoded, redacted and
  /// re-encoded. Any other value is returned unchanged.
  Object? redact(Object? data) {
    if (data is Map) {
      return <String, Object?>{
        for (final entry in data.entries)
          '${entry.key}':
              isSensitive('${entry.key}') ? mask : redact(entry.value),
      };
    }
    if (data is List) {
      return data.map(redact).toList();
    }
    if (data is String) {
      final trimmed = data.trimLeft();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return jsonEncode(redact(jsonDecode(data)));
        } on FormatException {
          return data;
        }
      }
    }
    return data;
  }

  /// Returns a readable, redacted string representation of [data], truncated
  /// to [maxLength] characters when provided.
  String stringify(Object? data, {int? maxLength}) {
    final redacted = redact(data);
    String text;
    if (redacted == null) {
      text = '';
    } else if (redacted is Map || redacted is List) {
      try {
        text = const JsonEncoder.withIndent('  ').convert(redacted);
      } on Object {
        text = '$redacted';
      }
    } else {
      text = '$redacted';
    }
    if (maxLength != null && maxLength >= 0 && text.length > maxLength) {
      return '${text.substring(0, maxLength)}… '
          '[truncated ${text.length - maxLength} chars]';
    }
    return text;
  }
}
