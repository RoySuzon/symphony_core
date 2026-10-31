import 'package:symphony_core/symphony_core.dart';

/// Decoding helpers for the backend's response envelope:
/// `{"status": "ok", "result": {...}}`.
///
/// Used by the response decoders of every feature (`ApiClient` decoders run
/// on the decoded JSON body). A [FormatException] thrown here becomes a
/// `ParsingFailure` in the repository's `Result`.
abstract final class ApiEnvelope {
  /// The `result` object of a successful response.
  static Map<String, Object?> result(Object? body) {
    final envelope = JsonReader.asMap(body);
    if (envelope == null || envelope['status'] != 'ok') {
      throw const FormatException('Unexpected response envelope.');
    }
    return JsonReader.asMap(envelope['result']) ??
        (throw const FormatException('The response has no result.'));
  }

  /// The list stored under [key] in the `result` object.
  static List<Object?> list(Object? body, String key) =>
      JsonReader.asList(result(body)[key]) ??
      (throw FormatException('The response has no "$key" list.'));

  /// A required string field of [json].
  static String requireString(Map<String, Object?> json, String key) =>
      JsonReader.asString(json[key]) ??
      (throw FormatException('Missing "$key".'));

  /// A required date field of [json].
  static DateTime requireDate(Map<String, Object?> json, String key) =>
      JsonReader.asDateTime(json[key], isUtc: true)?.toLocal() ??
      (throw FormatException('Missing or invalid date "$key".'));

  /// A required object field of [json].
  static Map<String, Object?> requireMap(
    Map<String, Object?> json,
    String key,
  ) =>
      JsonReader.asMap(json[key]) ??
      (throw FormatException('Missing object "$key".'));
}
