/// Lenient, type-safe helpers to read decoded JSON (`jsonDecode` output or
/// any nested `Map` / `List` structure).
///
/// None of these helpers throws on unexpected input: a missing path or a
/// value of the wrong type yields `null`, so mappers can apply their own
/// defaults.
///
/// ```dart
/// final json = jsonDecode(body);
/// final name = JsonReader.asString(JsonReader.readPath(json, 'data.user.name'));
/// final firstTag = JsonReader.asString(JsonReader.readPath(json, 'data.tags.0'));
/// final createdAt = JsonReader.asDateTime(JsonReader.readPath(json, 'meta.createdAt'));
/// final roles = JsonReader.asStringSet(JsonReader.readPath(json, 'data.user.roles')) ?? const {};
/// ```
abstract final class JsonReader {
  static final RegExp _basicIsoDate = RegExp(r'^\d{8}$');

  /// Returns the value found by following [dottedPath] in [json].
  ///
  /// Segments are separated by `.`: a segment selects a key of a map, or an
  /// index of a list when it is a non-negative integer (`'items.0.id'`).
  /// An empty path returns [json] itself. Returns `null` when a segment does
  /// not exist, an index is out of range or a value along the way is neither
  /// a map nor a list.
  ///
  /// Keys that contain a `.` cannot be addressed with a dotted path; use
  /// [readSegments] for them.
  static Object? readPath(Object? json, String dottedPath) {
    if (dottedPath.isEmpty) return json;
    return readSegments(json, dottedPath.split('.'));
  }

  /// Returns the value found by following [segments] in [json].
  ///
  /// Each segment is a map key (any object, usually a [String]) or a list
  /// index (an [int], or a [String] containing a non-negative integer).
  /// Returns `null` when the path cannot be followed.
  static Object? readSegments(Object? json, Iterable<Object> segments) {
    Object? current = json;
    for (final segment in segments) {
      final node = current;
      if (node is Map) {
        current = _readKey(node, segment);
      } else if (node is List) {
        final index = segment is int ? segment : int.tryParse('$segment');
        if (index == null || index < 0 || index >= node.length) return null;
        current = node[index];
      } else {
        return null;
      }
    }
    return current;
  }

  static Object? _readKey(Map<dynamic, dynamic> map, Object segment) {
    if (map.containsKey(segment)) return map[segment];
    if (segment is String) {
      final asInt = int.tryParse(segment);
      if (asInt != null && map.containsKey(asInt)) return map[asInt];
    } else {
      final asText = '$segment';
      if (map.containsKey(asText)) return map[asText];
    }
    return null;
  }

  /// Converts [value] to a [String].
  ///
  /// Strings are returned unchanged; numbers and booleans are converted with
  /// `toString()`. Anything else yields `null`.
  static String? asString(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return null;
  }

  /// Converts [value] to an [int] without losing information.
  ///
  /// Accepts integers, doubles without a fractional part (`3.0`) and strings
  /// containing such numbers (`' 42 '`, `'42.0'`). Anything else, including
  /// `3.5` and doubles too large to be exact (beyond 2^53), yields `null`.
  static int? asInt(Object? value) {
    if (value is int) return value;
    if (value is double) return _integralValue(value);
    if (value is String) {
      final text = value.trim();
      return int.tryParse(text) ?? _integralValue(double.tryParse(text));
    }
    return null;
  }

  static int? _integralValue(double? value) {
    if (value == null || !value.isFinite) return null;
    if (value != value.truncateToDouble()) return null;
    // Beyond 2^53 a double cannot represent every integer exactly.
    if (value.abs() > _maxSafeInteger) return null;
    return value.toInt();
  }

  static const double _maxSafeInteger = 9007199254740991;

  /// Converts [value] to a finite [double].
  ///
  /// Accepts numbers and numeric strings. Anything else, as well as `NaN` and
  /// infinite values, yields `null`.
  static double? asDouble(Object? value) {
    final double? result;
    if (value is num) {
      result = value.toDouble();
    } else if (value is String) {
      result = double.tryParse(value.trim());
    } else {
      result = null;
    }
    return result != null && result.isFinite ? result : null;
  }

  /// Converts [value] to a [bool].
  ///
  /// Accepts booleans, the numbers `1` and `0`, and the strings `true`,
  /// `false`, `1`, `0`, `yes`, `no`, `on` and `off` (case-insensitive,
  /// surrounding whitespace ignored). Anything else yields `null`.
  static bool? asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) {
      if (value == 1) return true;
      if (value == 0) return false;
      return null;
    }
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true' || '1' || 'yes' || 'on':
          return true;
        case 'false' || '0' || 'no' || 'off':
          return false;
      }
    }
    return null;
  }

  /// Converts [value] to a [DateTime].
  ///
  /// Accepts:
  /// * [DateTime] instances;
  /// * ISO-8601 strings (`'2024-05-01T10:30:00Z'`, `'2024-05-01'`,
  ///   `'20240501'`);
  /// * Unix epoch timestamps as numbers or numeric strings, in seconds,
  ///   milliseconds or microseconds. The unit is inferred from the magnitude:
  ///   values below 10^11 are seconds (up to the year 5138), values below
  ///   10^14 milliseconds, larger values microseconds. Fractional seconds are
  ///   supported.
  ///
  /// Epoch timestamps produce local times and ISO strings keep the time zone
  /// they carry, unless [isUtc] is `true`: the result is then converted to
  /// UTC. Anything else (including out-of-range timestamps) yields `null`.
  static DateTime? asDateTime(Object? value, {bool isUtc = false}) {
    final DateTime? result;
    if (value is DateTime) {
      result = value;
    } else if (value is num) {
      result = _fromEpoch(value, isUtc: isUtc);
    } else if (value is String) {
      result = _parseDateTime(value.trim(), isUtc: isUtc);
    } else {
      result = null;
    }
    if (result == null) return null;
    return isUtc ? result.toUtc() : result;
  }

  static DateTime? _parseDateTime(String text, {required bool isUtc}) {
    if (text.isEmpty) return null;
    // `YYYYMMDD` is a valid (basic) ISO-8601 date, not an epoch timestamp.
    if (_basicIsoDate.hasMatch(text)) return DateTime.tryParse(text);
    final numeric = num.tryParse(text);
    if (numeric != null) return _fromEpoch(numeric, isUtc: isUtc);
    return DateTime.tryParse(text);
  }

  static DateTime? _fromEpoch(num value, {required bool isUtc}) {
    if (!value.isFinite) return null;
    final magnitude = value.abs();
    final num micros;
    if (magnitude < 1e11) {
      micros = value * Duration.microsecondsPerSecond;
    } else if (magnitude < 1e14) {
      micros = value * Duration.microsecondsPerMillisecond;
    } else {
      micros = value;
    }
    try {
      return DateTime.fromMicrosecondsSinceEpoch(micros.round(), isUtc: isUtc);
    } on Object {
      // Outside the range supported by DateTime.
      return null;
    }
  }

  /// Converts [value] to a map with [String] keys.
  ///
  /// Maps whose keys are already strings are returned as they are (not
  /// copied); other maps are copied with their keys converted with
  /// `toString()`. Anything else yields `null`.
  static Map<String, Object?>? asMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      };
    }
    return null;
  }

  /// Converts [value] to a list.
  ///
  /// Lists are returned as they are (not copied); other iterables are copied
  /// into a new list. Anything else yields `null`.
  static List<Object?>? asList(Object? value) {
    if (value is List<Object?>) return value;
    if (value is Iterable<Object?>) return value.toList();
    return null;
  }

  /// Converts every element of the list [value] with [convert], dropping the
  /// elements for which it returns `null`.
  ///
  /// ```dart
  /// JsonReader.asListOf(json['ids'], JsonReader.asInt); // [1, 2, 3]
  /// ```
  ///
  /// Returns `null` when [value] is not a list (see [asList]).
  static List<T>? asListOf<T extends Object>(
    Object? value,
    T? Function(Object? element) convert,
  ) {
    final list = asList(value);
    if (list == null) return null;
    return list.map(convert).whereType<T>().toList();
  }

  /// Converts [value] to a set of strings, typically roles, permissions or
  /// scopes.
  ///
  /// Iterables are converted element by element with [asString] (elements
  /// that cannot be converted are dropped). A single string becomes a
  /// one-element set (an empty set when it is blank). Anything else yields
  /// `null`.
  static Set<String>? asStringSet(Object? value) {
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? <String>{} : <String>{text};
    }
    if (value is Iterable<Object?>) {
      return value.map(asString).whereType<String>().toSet();
    }
    return null;
  }
}
