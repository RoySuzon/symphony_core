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

  /// Returns [uri] with its credentials masked:
  ///
  /// * `user:password@` user info (or a user name alone, often an API key)
  ///   is replaced by [mask]: `https://***@api.example.com`;
  /// * sensitive query parameter values are masked. A sensitive parameter
  ///   appears once, with [mask] as its value (written as is when it only
  ///   contains characters allowed in a query, which is the case of the
  ///   default mask: `?token=***`). A query that cannot be decoded (invalid
  ///   percent-encoding) cannot be checked and is replaced by [mask]
  ///   entirely;
  /// * a fragment made of `key=value` pairs (OAuth implicit-grant redirects
  ///   such as `#access_token=...`), or ending with such a query
  ///   (`#/reset?token=...`), has its sensitive values masked the same way.
  ///
  /// [uri] itself is returned when there is nothing to mask. Never throws.
  Uri redactUri(Uri uri) {
    var result = uri;
    final userInfo = result.userInfo;
    if (userInfo.isNotEmpty && userInfo != mask) {
      result = result.replace(userInfo: mask);
    }
    if (result.hasQuery) {
      final Map<String, List<String>> params;
      try {
        params = result.queryParametersAll;
      } on Object {
        return _redactFragment(result.replace(query: mask));
      }
      if (params.keys.any(isSensitive)) {
        result = result.replace(query: _maskedQuery(params));
      }
    }
    return _redactFragment(result);
  }

  /// Masks the sensitive `key=value` pairs of the fragment of [uri].
  Uri _redactFragment(Uri uri) {
    if (!uri.hasFragment) return uri;
    final fragment = uri.fragment;
    // `#/route?query` (hash based routing) or `#key=value&...`.
    final queryStart = fragment.indexOf('?');
    final prefix = queryStart < 0 ? '' : fragment.substring(0, queryStart + 1);
    final query =
        queryStart < 0 ? fragment : fragment.substring(queryStart + 1);
    if (!query.contains('=')) return uri;
    final Map<String, List<String>> params;
    try {
      params = Uri(query: query).queryParametersAll;
    } on Object {
      return uri.replace(fragment: '$prefix$mask');
    }
    if (!params.keys.any(isSensitive)) return uri;
    return uri.replace(fragment: '$prefix${_maskedQuery(params)}');
  }

  static Object? _toJsonOrNull(Object data) {
    try {
      // ignore: avoid_dynamic_calls
      final Object? json = (data as dynamic).toJson();
      return json is Map || json is List ? json : null;
    } on NoSuchMethodError {
      return null;
    } on Object {
      return null;
    }
  }

  String _maskedQuery(Map<String, List<String>> params) => <String>[
        for (final entry in params.entries)
          if (isSensitive(entry.key))
            '${Uri.encodeQueryComponent(entry.key)}=$mask'
          else
            for (final value in entry.value)
              '${Uri.encodeQueryComponent(entry.key)}='
                  '${Uri.encodeQueryComponent(value)}',
      ].join('&');

  /// Deeply masks sensitive entries of maps and lists.
  ///
  /// Strings that contain a JSON object or array are decoded, redacted and
  /// re-encoded. Objects exposing a `toJson()` method (request models) are
  /// converted first, so their sensitive fields are masked too. Any other
  /// value is returned unchanged.
  Object? redact(Object? data) {
    if (data != null &&
        data is! Map &&
        data is! List &&
        data is! String &&
        data is! num &&
        data is! bool) {
      final Object? json = _toJsonOrNull(data);
      if (json != null) return redact(json);
    }
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
