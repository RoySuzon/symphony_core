import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

import 'support/networking_fakes.dart';

/// A request model serialised by Dio through `toJson`, whose `toString`
/// (like generated data classes) prints every field.
class _LoginRequest {
  const _LoginRequest(this.email, this.password);

  final String email;
  final String password;

  Map<String, Object?> toJson() => <String, Object?>{
    'email': email,
    'password': password,
  };

  @override
  String toString() => 'LoginRequest(email: $email, password: $password)';
}

void main() {
  late FakeHttpClientAdapter adapter;
  late CapturingLogSink sink;

  setUp(() {
    adapter = FakeHttpClientAdapter();
    sink = CapturingLogSink();
  });

  test('logs model bodies through toJson, never through toString', () async {
    final client = ApiClient(
      config: testConfig(enableLogging: true),
      httpClientAdapter: adapter,
      logger: capturingLogger(sink),
    );
    addTearDown(client.close);
    const json = ApiRequestOptions(contentType: 'application/json');

    await client.post<void>(
      '/login',
      data: const _LoginRequest('jane@example.com', 'model-secret'),
      options: json,
    );
    await client.post<void>(
      '/nested',
      data: <String, Object?>{
        'login': const _LoginRequest('john@example.com', 'nested-secret'),
        'attempts': <Object?>[
          const _LoginRequest('ann@example.com', 'list-secret'),
        ],
      },
      options: json,
    );

    // Dio really sends the models as JSON...
    expect(utf8.decode(adapter.bodies[0]), contains('model-secret'));
    expect(utf8.decode(adapter.bodies[1]), contains('nested-secret'));
    // ...but the logs only contain their redacted JSON form.
    expect(sink.text, contains('jane@example.com'));
    expect(sink.text, contains('john@example.com'));
    expect(sink.text, contains('ann@example.com'));
    expect(sink.text, isNot(contains('model-secret')));
    expect(sink.text, isNot(contains('nested-secret')));
    expect(sink.text, isNot(contains('list-secret')));
  });

  test('masks a custom auth header in logs, the inspector and cURL', () async {
    final inspector = ApiInspector();
    addTearDown(inspector.dispose);
    var calls = 0;
    adapter.responder =
        (_, _) =>
            calls++ == 0
                ? jsonBody(<String, Object?>{}, statusCode: 503)
                : jsonBody(
                  <String, Object?>{'ok': true},
                  // Some APIs hand out tokens in the same header.
                  headers: <String, List<String>>{
                    'x-auth': <String>['response-header-secret'],
                  },
                );
    final client = ApiClient(
      config: testConfig(
        enableLogging: true,
        enableInspector: true,
        maxRetries: 1,
        authHeaderName: 'X-Auth',
        authTokenPrefix: '',
      ),
      httpClientAdapter: adapter,
      logger: capturingLogger(sink),
      inspector: inspector,
      tokenDelegate: () => FakeTokenDelegate(token: 'custom-header-secret'),
    );
    addTearDown(client.close);

    await client.get<void>('/a');
    // Per-request credentials sent in the auth header (e.g. a sign-out).
    await client.post<void>(
      '/logout',
      options: const ApiRequestOptions(
        refreshOnUnauthorized: false,
        headers: <String, String>{'X-Auth': 'explicit-header-secret'},
      ),
    );

    expect(adapter.headerOf(1, 'X-Auth'), 'custom-header-secret');
    expect(adapter.headerOf(2, 'X-Auth'), 'explicit-header-secret');
    expect(sink.text, isNot(contains('header-secret')));
    expect(inspector.calls, hasLength(3));
    for (final call in inspector.calls) {
      expect(call.requestHeaders['X-Auth'], '***');
      expect(
        const CurlCommandBuilder().build(call),
        isNot(contains('header-secret')),
      );
      expect(call.responseHeaders.values.join(), isNot(contains('secret')));
    }
    expect(inspector.calls.first.responseHeaders['x-auth'], '***');
  });

  test('ApiResponse.toString never prints URL credentials or query values', () {
    final response = ApiResponse<void>(
      data: null,
      statusCode: 200,
      requestUri: Uri.parse(
        'https://jane:userinfo-secret@api.example.com/reset'
        '?token=query-secret&page=2#fragment-secret',
      ),
    );

    final text = '$response';

    expect(text, contains('status: 200'));
    expect(text, contains('api.example.com/reset'));
    expect(text, isNot(contains('userinfo-secret')));
    expect(text, isNot(contains('query-secret')));
    expect(text, isNot(contains('fragment-secret')));
  });
}
