import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';

void main() {
  ApiCallRecord record({
    String method = 'POST',
    String url = 'https://api.example.com/auth/login',
    Map<String, String> headers = const <String, String>{},
    String? body,
    ApiCallFormData? form,
  }) {
    return ApiCallRecord(
      id: 1,
      method: method,
      uri: Uri.parse(url),
      startedAt: DateTime(2024),
      requestHeaders: headers,
      requestBody: body,
      requestFormData: form,
    );
  }

  const builder = CurlCommandBuilder();

  group('CurlCommandBuilder.quote', () {
    test('wraps values in single quotes', () {
      expect(CurlCommandBuilder.quote('abc'), "'abc'");
      expect(CurlCommandBuilder.quote(''), "''");
      expect(
        CurlCommandBuilder.quote(r'$HOME `id` "x"'),
        r"""'$HOME `id` "x"'""",
      );
    });

    test('escapes embedded single quotes', () {
      expect(CurlCommandBuilder.quote("it's"), r"'it'\''s'");
    });
  });

  group('CurlCommandBuilder.build', () {
    test('builds a JSON request from redacted data', () {
      final command = builder.build(
        record(
          headers: const <String, String>{
            'content-type': 'application/json',
            'Authorization': '***',
            'content-length': '42',
          },
          body: '{\n  "email": "ada@example.com",\n  "password": "***"\n}',
        ),
      );
      expect(
        command,
        "curl -X POST -H 'content-type: application/json' "
        "-H 'Authorization: ***' "
        "--data-raw '{\n  \"email\": \"ada@example.com\",\n  \"password\": \"***\"\n}' "
        "'https://api.example.com/auth/login'",
      );
      expect(command, isNot(contains('content-length')));
    });

    test('quotes values containing single quotes and shell syntax', () {
      final command = builder.build(
        record(
          url: r"https://api.example.com/search?q=it's&x=$(id)",
          headers: const <String, String>{'X-Note': "Ada's `phone`"},
          body: "{\"name\": \"O'Hara\"}",
        ),
      );
      expect(command, contains(r"-H 'X-Note: Ada'\''s `phone`'"));
      expect(command, contains(r"""--data-raw '{"name": "O'\''Hara"}'"""));
      expect(
        command,
        endsWith(r"'https://api.example.com/search?q=it'\''s&x=$(id)'"),
      );
    });

    test('uses --head for HEAD and keeps the masked query', () {
      final command = builder.build(
        record(method: 'HEAD', url: 'https://api.example.com/files?token=***'),
      );
      expect(command, "curl --head 'https://api.example.com/files?token=***'");
    });

    test('omits bodies that were not captured as text', () {
      final binary = builder.build(
        record(body: ApiCallRecord.binaryBodyPlaceholder(12)),
      );
      expect(binary, isNot(contains('--data')));
      final stream = builder.build(
        record(body: ApiCallRecord.streamBodyPlaceholder),
      );
      expect(stream, isNot(contains('--data')));
    });

    test('replaces Accept-Encoding with --compressed', () {
      final command = builder.build(
        record(
          method: 'GET',
          headers: const <String, String>{'accept-encoding': 'gzip'},
        ),
      );
      expect(
        command,
        "curl -X GET --compressed 'https://api.example.com/auth/login'",
      );
    });

    test('emits multipart fields and files without the boundary header', () {
      final command = builder.build(
        record(
          url: 'https://api.example.com/upload',
          headers: const <String, String>{
            'content-type': 'multipart/form-data; boundary=--dio-boundary-1',
          },
          body: '{"fields": "..."}',
          form: const ApiCallFormData(
            fields: <MapEntry<String, String>>[
              MapEntry<String, String>('name', '@not-a-file'),
              MapEntry<String, String>('password', '***'),
            ],
            files: <ApiCallFormFile>[
              ApiCallFormFile(
                field: 'avatar',
                filename: 'me.png',
                length: 3,
                contentType: 'image/png',
              ),
              ApiCallFormFile(
                field: 'doc',
                filename: 'my "cv";v2.pdf',
                length: 9,
              ),
            ],
          ),
        ),
      );
      expect(command, isNot(contains('boundary')));
      expect(command, isNot(contains('--data')));
      expect(command, contains("--form-string 'name=@not-a-file'"));
      expect(command, contains("--form-string 'password=***'"));
      expect(command, contains("-F 'avatar=@me.png;type=image/png'"));
      expect(command, contains(r"""-F 'doc=@"my \"cv\";v2.pdf"'"""));
    });

    test('url-encodes form bodies field by field', () {
      final command = builder.build(
        record(
          headers: const <String, String>{
            'content-type': 'application/x-www-form-urlencoded',
          },
          body:
              '{"grant_type": "password", "scope": ["a", "b"], '
              '"password": "***"}',
        ),
      );
      expect(command, contains("--data-urlencode 'grant_type=password'"));
      expect(command, contains("--data-urlencode 'scope=a'"));
      expect(command, contains("--data-urlencode 'scope=b'"));
      expect(command, contains("--data-urlencode 'password=***'"));
    });

    test('falls back to --data-raw for non-JSON form bodies', () {
      final command = builder.build(
        record(
          headers: const <String, String>{
            'content-type': 'application/x-www-form-urlencoded',
          },
          body: 'a=1&b=2',
        ),
      );
      expect(command, contains("--data-raw 'a=1&b=2'"));
    });

    test('supports multi-line output and custom excluded headers', () {
      const multiline = CurlCommandBuilder(
        multiline: true,
        excludedHeaders: <String>{'x-trace'},
      );
      final command = multiline.build(
        record(
          method: 'DELETE',
          url: 'https://api.example.com/items/1',
          headers: const <String, String>{
            'X-Trace': 'abc',
            'Content-Length': '0',
          },
        ),
      );
      expect(
        command,
        "curl \\\n  -X DELETE \\\n  -H 'Content-Length: 0' \\\n"
        "  'https://api.example.com/items/1'",
      );
    });
  });
}
