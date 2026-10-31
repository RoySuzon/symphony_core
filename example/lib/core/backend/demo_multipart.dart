import 'dart:convert';
import 'dart:typed_data';

/// One part of a `multipart/form-data` body.
class DemoMultipartPart {
  /// Creates a part.
  const DemoMultipartPart({
    required this.name,
    required this.headers,
    required this.bytes,
    this.filename,
    this.contentType,
  });

  /// Form field name.
  final String name;

  /// File name, for file parts.
  final String? filename;

  /// `Content-Type` of the part, if sent.
  final String? contentType;

  /// Part headers with lower-case names.
  final Map<String, String> headers;

  /// Part content.
  final Uint8List bytes;

  /// Whether this part is a file.
  bool get isFile => filename != null;

  /// The content decoded as UTF-8 text.
  String get text => utf8.decode(bytes, allowMalformed: true);
}

/// Extracts the boundary of a `multipart/*` [contentType], or `null`.
String? multipartBoundary(String? contentType) {
  if (contentType == null ||
      !contentType.trim().toLowerCase().startsWith('multipart/')) {
    return null;
  }
  final boundary = _parameters(contentType)['boundary'];
  return boundary == null || boundary.isEmpty ? null : boundary;
}

/// Splits a `multipart/form-data` [body] delimited by [boundary] into its
/// parts (RFC 7578). Malformed trailing data is ignored.
List<DemoMultipartPart> parseMultipart(Uint8List body, String boundary) {
  final delimiter = ascii.encode('--$boundary');
  final separator = <int>[13, 10, ...delimiter];
  final parts = <DemoMultipartPart>[];

  var position = _indexOf(body, delimiter, 0);
  while (position >= 0) {
    var start = position + delimiter.length;
    // `--boundary--` closes the body.
    if (_startsWith(body, start, const <int>[45, 45])) break;
    if (_startsWith(body, start, const <int>[13, 10])) start += 2;

    final end = _indexOf(body, separator, start);
    if (end < 0) break;
    final part = _parsePart(Uint8List.sublistView(body, start, end));
    if (part != null) parts.add(part);
    position = end + 2;
  }
  return parts;
}

DemoMultipartPart? _parsePart(Uint8List bytes) {
  final headerEnd = _indexOf(bytes, const <int>[13, 10, 13, 10], 0);
  if (headerEnd < 0) return null;
  final headers = <String, String>{};
  final headerText = utf8.decode(
    Uint8List.sublistView(bytes, 0, headerEnd),
    allowMalformed: true,
  );
  for (final line in headerText.split('\r\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    headers[line.substring(0, colon).trim().toLowerCase()] =
        line.substring(colon + 1).trim();
  }
  final disposition = headers['content-disposition'];
  if (disposition == null) return null;
  final parameters = _parameters(disposition);
  final name = parameters['name'];
  if (name == null) return null;
  return DemoMultipartPart(
    name: name,
    filename: parameters['filename'],
    contentType: headers['content-type'],
    headers: headers,
    bytes: Uint8List.fromList(
      Uint8List.sublistView(bytes, headerEnd + 4),
    ),
  );
}

/// Parses `value; key=value; key="quoted value"` header parameters.
Map<String, String> _parameters(String header) {
  final result = <String, String>{};
  final buffer = StringBuffer();
  final segments = <String>[];
  var quoted = false;
  for (final char in header.split('')) {
    if (char == '"') quoted = !quoted;
    if (char == ';' && !quoted) {
      segments.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  segments.add(buffer.toString());

  for (final segment in segments.skip(1)) {
    final equals = segment.indexOf('=');
    if (equals <= 0) continue;
    final key = segment.substring(0, equals).trim().toLowerCase();
    var value = segment.substring(equals + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value.replaceAll('%22', '"');
  }
  return result;
}

bool _startsWith(Uint8List bytes, int offset, List<int> pattern) {
  if (offset + pattern.length > bytes.length) return false;
  for (var i = 0; i < pattern.length; i++) {
    if (bytes[offset + i] != pattern[i]) return false;
  }
  return true;
}

int _indexOf(Uint8List bytes, List<int> pattern, int from) {
  final last = bytes.length - pattern.length;
  final first = pattern.first;
  for (var i = from; i <= last; i++) {
    if (bytes[i] == first && _startsWith(bytes, i, pattern)) return i;
  }
  return -1;
}
