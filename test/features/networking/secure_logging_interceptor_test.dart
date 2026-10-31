import 'dart:typed_data';

import 'package:dio/dio.dart' show BaseOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/core/logging/log_level.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

import 'support/networking_fakes.dart';

void main() {
  late FakeHttpClientAdapter adapter;
  late CapturingLogSink sink;

  setUp(() {
    adapter = FakeHttpClientAdapter();
    sink = CapturingLogSink();
  });

  ApiClient buildClient({
    AuthTokenDelegate? delegate,
    int maxLoggedBodyLength = 4000,
  }) {
    final client = ApiClient(
      config: testConfig(
        enableLogging: true,
        maxLoggedBodyLength: maxLoggedBodyLength,
      ),
      httpClientAdapter: adapter,
      logger: capturingLogger(sink),
      tokenDelegate: delegate == null ? null : () => delegate,
    );
    addTearDown(client.close);
    return client;
  }

  test('logs requests and responses with secrets redacted', () async {
    adapter.responder =
        (_, _) => jsonBody(
          <String, Object?>{
            'access_token': 'at-secret-1',
            'user': <String, Object?>{'name': 'Jane Doe'},
          },
          headers: <String, List<String>>{
            'Set-Cookie': <String>['session=cookie-secret'],
          },
        );
    final client = buildClient(
      delegate: FakeTokenDelegate(token: 'injected-token-secret'),
    );

    await client.post<void>(
      '/login',
      queryParameters: <String, dynamic>{'api_key': 'query-secret', 'page': 2},
      data: <String, Object?>{
        'email': 'jane@example.com',
        'password': 'hunter2-secret',
        'nested': <String, Object?>{'refresh_token': 'rt-secret'},
      },
      options: const ApiRequestOptions(
        headers: <String, String>{
          'Authorization': 'Basic header-secret',
          'X-Api-Key': 'key-secret',
          'X-Trace': 'trace-1',
        },
      ),
    );

    final text = sink.text;
    expect(sink.entries.every((entry) => entry.tag == 'HTTP'), isTrue);
    expect(text, contains('--> POST https://api.example.com/login?'));
    expect(text, contains('page=2'));
    expect(text, contains('<-- 200 POST https://api.example.com/login'));
    expect(text, contains(' ms)'));
    expect(text, contains('jane@example.com'));
    expect(text, contains('Jane Doe'));
    expect(text, contains('trace-1'));
    expect(text, contains('***'));
    for (final secret in <String>[
      'at-secret-1',
      'cookie-secret',
      'injected-token-secret',
      'query-secret',
      'hunter2-secret',
      'rt-secret',
      'header-secret',
      'key-secret',
    ]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });

  test('summarises multipart, binary and form encoded bodies', () async {
    final client = buildClient();

    await client.upload<void>(
      '/files',
      files: const <UploadFile>[
        UploadFile.fromBytes(
          <int>[1, 2, 3],
          filename: 'avatar.png',
          contentType: 'image/png',
        ),
      ],
      fields: const <String, Object?>{'password': 'multipart-secret'},
    );
    await client.post<void>(
      '/binary',
      data: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      options: const ApiRequestOptions(contentType: 'application/octet-stream'),
    );
    await client.post<void>(
      '/token',
      data: 'grant_type=password&username=jane&password=form-secret',
      options: const ApiRequestOptions(
        contentType: 'application/x-www-form-urlencoded',
      ),
    );

    final text = sink.text;
    expect(
      text,
      contains('FormData(fields: [password], files: [file: avatar.png'),
    );
    expect(text, contains('[binary 5 bytes]'));
    expect(text, contains('grant_type'));
    expect(text, isNot(contains('multipart-secret')));
    expect(text, isNot(contains('form-secret')));
  });

  test(
    'logs errors with their type and status, never their raw cause',
    () async {
      adapter.responder = (options, _) {
        if (options.path == '/offline') {
          throw const FakeSocketException('cause-secret');
        }
        return jsonBody(<String, Object?>{
          'message': 'Expired',
          'token': 'error-secret',
        }, statusCode: 401);
      };
      final client = buildClient();

      await expectLater(
        client.get<void>('/expired'),
        throwsA(isA<UnauthorizedFailure>()),
      );
      await expectLater(
        client.get<void>('/offline'),
        throwsA(isA<NetworkFailure>()),
      );

      final errors = sink.entries.where(
        (entry) => entry.level == LogLevel.warning,
      );
      final text = errors.map((entry) => entry.message).join('\n');
      expect(text, contains('<-- 401 GET https://api.example.com/expired'));
      expect(text, contains('[badResponse]'));
      expect(text, contains('Expired'));
      expect(text, contains('<-- ERROR GET https://api.example.com/offline'));
      expect(text, contains('[unknown]'));
      expect(text, contains('cause: FakeSocketException'));
      expect(sink.text, isNot(contains('error-secret')));
      expect(sink.text, isNot(contains('cause-secret')));
    },
  );

  test('masks credentials embedded in URLs', () async {
    final client = buildClient();

    client.updateBaseUrl('https://jane:url-secret@api.example.com');
    await client.get<void>(
      '/a',
      queryParameters: <String, dynamic>{'access_token': 'query-token-secret'},
    );

    expect(
      sink.text,
      contains('https://***@api.example.com/a?access_token=***'),
    );
    expect(sink.text, isNot(contains('url-secret')));
    expect(sink.text, isNot(contains('query-token-secret')));
  });

  test('truncates long bodies', () async {
    adapter.responder =
        (_, _) => jsonBody(<String, Object?>{
          'text': List<String>.filled(200, 'x').join(),
        });
    final client = buildClient(maxLoggedBodyLength: 50);

    await client.get<void>('/long');

    expect(sink.text, contains('[truncated'));
  });

  test('skips requests with log disabled', () async {
    final client = buildClient();

    await client.get<void>(
      '/quiet',
      options: const ApiRequestOptions(log: false),
    );

    expect(sink.entries, isEmpty);
  });

  test('marks retries in the request line', () async {
    final interceptor = SecureLoggingInterceptor(logger: capturingLogger(sink));
    final dio =
        Dio(BaseOptions(baseUrl: testBaseUrl))
          ..httpClientAdapter = adapter
          ..interceptors.add(interceptor);

    await dio.get<dynamic>(
      '/again',
      options: Options(
        extra: <String, dynamic>{SymphonyRequestExtras.retryAttempt: 2},
      ),
    );

    expect(
      sink.text,
      contains('--> GET https://api.example.com/again (retry #2)'),
    );
  });
}
