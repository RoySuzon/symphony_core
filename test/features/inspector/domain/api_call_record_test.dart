import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/logging/log_redactor.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';

void main() {
  final started = DateTime(2024, 5, 17, 9, 5, 7);

  ApiCallRecord record({
    String url = 'https://api.example.com/v1/users?page=2',
    DateTime? endedAt,
    int? statusCode,
    String? error,
    Map<String, String> requestHeaders = const <String, String>{},
    Map<String, String> responseHeaders = const <String, String>{},
  }) {
    return ApiCallRecord(
      id: 1,
      method: 'GET',
      uri: Uri.parse(url),
      startedAt: started,
      endedAt: endedAt,
      statusCode: statusCode,
      error: error,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
    );
  }

  group('ApiCallRecord', () {
    test('exposes path, host and scheme helpers', () {
      final call = record();
      expect(call.path, '/v1/users');
      expect(call.host, 'api.example.com');
      expect(call.isSecure, isTrue);

      final local = record(url: 'http://localhost:8080');
      expect(local.path, '/');
      expect(local.host, 'localhost:8080');
      expect(local.isSecure, isFalse);
    });

    test('statusLabel describes pending, answered and failed calls', () {
      expect(record().statusLabel, '...');
      expect(record(endedAt: started, statusCode: 204).statusLabel, '204');
      expect(record(endedAt: started, error: 'boom').statusLabel, 'ERR');
    });

    test('isError and isSuccessful follow the outcome', () {
      final ok = record(endedAt: started, statusCode: 200);
      expect(ok.isSuccessful, isTrue);
      expect(ok.isError, isFalse);

      final notFound = record(endedAt: started, statusCode: 404);
      expect(notFound.isSuccessful, isFalse);
      expect(notFound.isError, isTrue);

      final offline = record(endedAt: started, error: 'offline');
      expect(offline.isError, isTrue);

      expect(record().isError, isFalse);
      expect(record().isPending, isTrue);
    });

    test('durationLabel formats milliseconds, seconds and minutes', () {
      expect(record().durationLabel, isNull);
      expect(
        record(
          endedAt: started.add(const Duration(milliseconds: 85)),
        ).durationLabel,
        '85 ms',
      );
      expect(
        record(
          endedAt: started.add(const Duration(milliseconds: 1240)),
        ).durationLabel,
        '1.24 s',
      );
      expect(
        record(
          endedAt: started.add(const Duration(seconds: 125)),
        ).durationLabel,
        '2 min 5 s',
      );
    });

    test('timeLabel is zero padded', () {
      expect(record().timeLabel, '09:05:07');
    });

    test('reads content types and length case-insensitively', () {
      final call = record(
        requestHeaders: const <String, String>{
          'Content-Type': 'application/json',
        },
        responseHeaders: const <String, String>{
          'content-type': 'text/plain',
          'Content-Length': '2048',
        },
      );
      expect(call.requestContentType, 'application/json');
      expect(call.responseContentType, 'text/plain');
      expect(call.responseContentLength, 2048);
      expect(record().responseContentLength, isNull);
    });

    test('formatBytes picks a readable unit', () {
      expect(ApiCallRecord.formatBytes(512), '512 B');
      expect(ApiCallRecord.formatBytes(1536), '1.5 KB');
      expect(ApiCallRecord.formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('copyWith replaces only the given fields', () {
      final call = record();
      final done = call.copyWith(
        endedAt: started.add(const Duration(seconds: 1)),
        statusCode: 201,
        statusMessage: 'Created',
        responseBody: '{}',
      );
      expect(done.id, call.id);
      expect(done.uri, call.uri);
      expect(done.startedAt, call.startedAt);
      expect(done.statusCode, 201);
      expect(done.statusMessage, 'Created');
      expect(done.responseBody, '{}');
      expect(done.isPending, isFalse);
      expect(call.isPending, isTrue);
    });

    test('recognizes body placeholders', () {
      expect(
        ApiCallRecord.isBodyPlaceholder(ApiCallRecord.binaryBodyPlaceholder(3)),
        isTrue,
      );
      expect(
        ApiCallRecord.isBodyPlaceholder(ApiCallRecord.streamBodyPlaceholder),
        isTrue,
      );
      expect(ApiCallRecord.isBodyPlaceholder('[1, 2]'), isFalse);
      expect(ApiCallRecord.isBodyPlaceholder(null), isFalse);
    });
  });

  group('ApiCallFormData', () {
    const form = ApiCallFormData(
      fields: <MapEntry<String, String>>[
        MapEntry<String, String>('name', 'Ada'),
        MapEntry<String, String>('password', 'p@ss-secret'),
        MapEntry<String, String>('tags[]', 'a'),
        MapEntry<String, String>('tags[]', 'b'),
        MapEntry<String, String>('payload', '{"token":"abc","n":1}'),
      ],
      files: <ApiCallFormFile>[
        ApiCallFormFile(
          field: 'avatar',
          filename: 'me.png',
          length: 3,
          contentType: 'image/png',
        ),
      ],
    );

    test('redact masks sensitive fields and nested JSON values', () {
      final redacted = form.redact(const LogRedactor());
      final values = <String, String>{
        for (final field in redacted.fields) field.key: field.value,
      };
      expect(values['name'], 'Ada');
      expect(values['password'], '***');
      expect(values['payload'], '{"token":"***","n":1}');
      expect(redacted.files, form.files);
    });

    test('toSummary groups repeated names and describes files', () {
      final summary = form.toSummary();
      final fields = summary['fields']! as Map<String, Object?>;
      expect(fields['tags[]'], <String>['a', 'b']);
      final files = summary['files']! as Map<String, Object?>;
      expect(files['avatar'], 'me.png (3 bytes, image/png)');
    });

    test('supports value equality', () {
      expect(
        const ApiCallFormData(
          fields: <MapEntry<String, String>>[
            MapEntry<String, String>('a', '1'),
          ],
        ),
        const ApiCallFormData(
          fields: <MapEntry<String, String>>[
            MapEntry<String, String>('a', '1'),
          ],
        ),
      );
      expect(const ApiCallFormData().isEmpty, isTrue);
    });
  });
}
