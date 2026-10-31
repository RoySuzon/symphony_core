import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

import 'support/networking_fakes.dart';

void main() {
  late FakeHttpClientAdapter adapter;
  late List<Duration> delays;

  setUp(() {
    adapter = FakeHttpClientAdapter();
    delays = <Duration>[];
  });

  ApiClient buildClient({
    SymphonyConfig? config,
    AuthTokenDelegate? delegate,
    RetryDelayCallback? delay,
  }) {
    final client = ApiClient(
      config: config ?? testConfig(maxRetries: 2),
      httpClientAdapter: adapter,
      tokenDelegate: delegate == null ? null : () => delegate,
      retryDelayCallback: delay ?? (duration) async => delays.add(duration),
    );
    addTearDown(client.close);
    return client;
  }

  void failWithConnectionError() {
    adapter.responder = (options, _) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        );
  }

  test('retries GET on connection errors up to maxRetries', () async {
    failWithConnectionError();
    final client = buildClient();

    final failure = await _failureOf(client.get<void>('/a'));

    expect(failure, isA<NetworkFailure>());
    expect(adapter.requests, hasLength(3));
    expect(
      adapter.requests.map(
        (request) => request.extra[SymphonyRequestExtras.retryAttempt] ?? 0,
      ),
      <int>[0, 1, 2],
    );
  });

  test('never retries POST or PATCH', () async {
    failWithConnectionError();
    final client = buildClient();

    await _failureOf(client.post<void>('/a'));
    await _failureOf(client.patch<void>('/b'));

    expect(adapter.requests, hasLength(2));
  });

  test('retries idempotent methods on timeouts and socket errors', () async {
    var calls = 0;
    adapter.responder = (options, _) {
      calls++;
      if (calls == 1) {
        throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        );
      }
      if (calls == 2) throw const FakeSocketException();
      return jsonBody(<String, Object?>{'ok': true});
    };
    final client = buildClient();

    final response = await client.put<Map<String, dynamic>>('/a');

    expect(response.data, <String, dynamic>{'ok': true});
    expect(adapter.requests, hasLength(3));
  });

  test('retries the configured status codes only', () async {
    adapter.responder = (options, _) {
      if (options.path == '/flaky' &&
          options.extra[SymphonyRequestExtras.retryAttempt] == null) {
        return jsonBody(<String, Object?>{}, statusCode: 503);
      }
      if (options.path == '/broken') {
        return jsonBody(<String, Object?>{}, statusCode: 500);
      }
      return jsonBody(<String, Object?>{'ok': true});
    };
    final client = buildClient();

    final response = await client.get<Map<String, dynamic>>('/flaky');
    final failure = await _failureOf(client.get<void>('/broken'));

    expect(response.data, <String, dynamic>{'ok': true});
    expect(failure, isA<ServerFailure>());
    expect(
      adapter.requests.map((request) => request.path),
      <String>['/flaky', '/flaky', '/broken'],
    );
  });

  test('honours per-request retry policies', () async {
    failWithConnectionError();
    final client = buildClient(config: testConfig());

    await _failureOf(
      client.get<void>('/more',
          options: const ApiRequestOptions(maxRetries: 1)),
    );
    await _failureOf(
      client.get<void>(
        '/none',
        options: const ApiRequestOptions(retry: false, maxRetries: 3),
      ),
    );

    expect(
      adapter.requests.map((request) => request.path),
      <String>['/more', '/more', '/none'],
    );
  });

  test('waits retryDelay multiplied by the attempt number', () async {
    failWithConnectionError();
    final client = buildClient(
      config: const SymphonyConfig(
        baseUrl: testBaseUrl,
        maxRetries: 3,
        retryDelay: Duration(milliseconds: 100),
      ),
    );

    await _failureOf(client.get<void>('/a'));

    expect(delays, const <Duration>[
      Duration(milliseconds: 100),
      Duration(milliseconds: 200),
      Duration(milliseconds: 300),
    ]);
  });

  test('honours Retry-After and gives up when it is too long', () async {
    adapter.responder = (options, _) {
      if (options.extra[SymphonyRequestExtras.retryAttempt] != null) {
        return jsonBody(<String, Object?>{'ok': true});
      }
      return jsonBody(
        <String, Object?>{},
        statusCode: 429,
        headers: <String, List<String>>{
          'Retry-After': <String>[options.path == '/soon' ? '2' : '120'],
        },
      );
    };
    final client = buildClient();

    final response = await client.get<Map<String, dynamic>>('/soon');
    final failure = await _failureOf(client.get<void>('/later'));

    expect(response.statusCode, 200);
    expect(delays, const <Duration>[Duration(seconds: 2)]);
    expect(failure, isA<ServerFailure>());
    expect(failure.statusCode, 429);
  });

  test('stops when the request is cancelled during the delay', () async {
    failWithConnectionError();
    final cancelToken = CancelToken();
    final client = buildClient(
      delay: (duration) async => cancelToken.cancel('stop'),
    );

    final failure = await _failureOf(
      client.get<void>('/a', cancelToken: cancelToken),
    );

    expect(failure, isA<CancelledFailure>());
    expect(adapter.requests, hasLength(1));
  });

  test('a retried request picks up the current access token', () async {
    final delegate = FakeTokenDelegate(token: 'first');
    adapter.responder = (options, _) {
      if (options.extra[SymphonyRequestExtras.retryAttempt] == null) {
        delegate.token = 'second';
        return jsonBody(<String, Object?>{}, statusCode: 503);
      }
      return jsonBody(<String, Object?>{'ok': true});
    };
    final client = buildClient(delegate: delegate);

    await client.get<void>('/a');

    expect(adapter.headerOf(0, 'Authorization'), 'Bearer first');
    expect(adapter.headerOf(1, 'Authorization'), 'Bearer second');
  });

  test('a multipart PUT is retried with a fresh body', () async {
    var calls = 0;
    adapter.responder = (options, _) {
      calls++;
      if (calls == 1) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'reset',
        );
      }
      return jsonBody(<String, Object?>{'ok': true});
    };
    final client = buildClient();

    await client.upload<void>(
      '/avatar',
      method: 'PUT',
      files: const <UploadFile>[
        UploadFile.fromBytes(<int>[1, 2, 3, 4], filename: 'a.png'),
      ],
    );

    expect(adapter.requests, hasLength(2));
    expect(adapter.bodies[1].length, adapter.bodies[0].length);
  });

  test('shouldRetry ignores cancellations and non idempotent methods', () {
    final interceptor = RetryInterceptor(
      dio: Dio(),
      config: testConfig(maxRetries: 1),
    );
    DioException error(String method, DioExceptionType type) => DioException(
          requestOptions: RequestOptions(path: '/x', method: method),
          type: type,
        );

    expect(
      interceptor.shouldRetry(error('GET', DioExceptionType.connectionError)),
      isTrue,
    );
    expect(
      interceptor.shouldRetry(error('POST', DioExceptionType.connectionError)),
      isFalse,
    );
    expect(
      interceptor.shouldRetry(error('GET', DioExceptionType.cancel)),
      isFalse,
    );
    expect(
      interceptor.shouldRetry(error('GET', DioExceptionType.badCertificate)),
      isFalse,
    );
  });
}

/// Awaits [future] and returns the [Failure] it throws.
Future<Failure> _failureOf(Future<Object?> future) async {
  try {
    await future;
  } on Failure catch (failure) {
    return failure;
  }
  fail('Expected the call to throw a Failure.');
}
