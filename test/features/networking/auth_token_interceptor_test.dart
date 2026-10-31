import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

import 'support/networking_fakes.dart';

void main() {
  late FakeHttpClientAdapter adapter;

  setUp(() {
    adapter = FakeHttpClientAdapter();
  });

  ApiClient buildClient(AuthTokenDelegate? delegate, {SymphonyConfig? config}) {
    final client = ApiClient(
      config: config ?? testConfig(),
      httpClientAdapter: adapter,
      tokenDelegate: () => delegate,
    );
    addTearDown(client.close);
    return client;
  }

  /// Answers 200 for [validHeader] and 401 for anything else.
  void acceptOnly(String validHeader) {
    adapter.responder =
        (options, _) =>
            options.headers['Authorization'] == validHeader
                ? jsonBody(<String, Object?>{'path': options.path})
                : jsonBody(<String, Object?>{
                  'message': 'Token expired',
                }, statusCode: 401);
  }

  group('token injection', () {
    test('uses the configured prefix and header name', () async {
      final delegate = FakeTokenDelegate(token: 'abc');

      await buildClient(delegate).get<void>('/a');
      await buildClient(
        delegate,
        config: testConfig(authTokenPrefix: 'Token'),
      ).get<void>('/b');
      await buildClient(
        delegate,
        config: testConfig(authTokenPrefix: '', authHeaderName: 'X-Auth'),
      ).get<void>('/c');

      expect(adapter.headerOf(0, 'Authorization'), 'Bearer abc');
      expect(adapter.headerOf(1, 'Authorization'), 'Token abc');
      expect(adapter.headerOf(2, 'X-Auth'), 'abc');
      expect(adapter.headerOf(2, 'Authorization'), isNull);
    });

    test('keeps a header set by the caller and never refreshes it', () async {
      final delegate = FakeTokenDelegate(token: 'abc', refreshedToken: 'new');
      adapter.responder =
          (_, _) => jsonBody(<String, Object?>{}, statusCode: 401);
      final client = buildClient(delegate);

      final failure = await _failureOf(
        client.get<void>(
          '/a',
          options: const ApiRequestOptions(
            headers: <String, String>{'authorization': 'Basic dXNlcg=='},
          ),
        ),
      );

      expect(failure, isA<UnauthorizedFailure>());
      expect(adapter.headerOf(0, 'Authorization'), 'Basic dXNlcg==');
      expect(adapter.requests, hasLength(1));
      expect(delegate.refreshCalls, 0);
      expect(delegate.expiredCalls, 0);
    });

    test(
      'is skipped for unauthenticated requests, which never refresh',
      () async {
        final delegate = FakeTokenDelegate(token: 'abc', refreshedToken: 'new');
        adapter.responder =
            (_, _) => jsonBody(<String, Object?>{}, statusCode: 401);
        final client = buildClient(delegate);

        final failure = await _failureOf(
          client.post<void>(
            '/auth/login',
            options: ApiRequestOptions.unauthenticated,
          ),
        );

        expect(failure, isA<UnauthorizedFailure>());
        expect(adapter.headerOf(0, 'Authorization'), isNull);
        expect(delegate.refreshCalls, 0);
        expect(delegate.expiredCalls, 0);
      },
    );

    test('sends no header without a delegate or a token', () async {
      await buildClient(null).get<void>('/a');
      await buildClient(FakeTokenDelegate()).get<void>('/b');

      expect(adapter.headerOf(0, 'Authorization'), isNull);
      expect(adapter.headerOf(1, 'Authorization'), isNull);
    });

    test('a throwing delegate does not fail the request', () async {
      final client = ApiClient(
        config: testConfig(),
        httpClientAdapter: adapter,
        tokenDelegate: () => throw StateError('not ready'),
      );
      addTearDown(client.close);

      final response = await client.get<Map<String, dynamic>>('/a');

      expect(response.statusCode, 200);
      expect(adapter.headerOf(0, 'Authorization'), isNull);
    });
  });

  group('token refresh', () {
    test(
      'refreshes once for concurrent 401s and replays every request',
      () async {
        final delegate = FakeTokenDelegate(token: 'old', refreshedToken: 'new');
        acceptOnly('Bearer new');
        final client = buildClient(delegate);

        final responses = await Future.wait(<Future<ApiResponse<Object?>>>[
          client.get<Object?>('/a'),
          client.get<Object?>('/b'),
          client.get<Object?>('/c'),
        ]);

        expect(delegate.refreshCalls, 1);
        expect(delegate.expiredCalls, 0);
        expect(
          responses.map((response) => (response.data! as Map)['path']),
          <String>['/a', '/b', '/c'],
        );
        final sent =
            adapter.requests
                .map(
                  (request) =>
                      '${request.path} ${request.headers['Authorization']}',
                )
                .toList();
        expect(sent.where((line) => line.endsWith('Bearer old')), hasLength(3));
        expect(sent.where((line) => line.endsWith('Bearer new')), hasLength(3));
        expect(
          adapter.requests
              .where(
                (request) => request.headers['Authorization'] == 'Bearer new',
              )
              .every(
                (request) =>
                    request.extra[SymphonyRequestExtras.authRetried] == true,
              ),
          isTrue,
        );
      },
    );

    test('requests started during a refresh wait for the new token', () async {
      final delegate = FakeTokenDelegate(token: 'old', refreshedToken: 'new')
        ..refreshGate = Completer<void>();
      acceptOnly('Bearer new');
      final client = buildClient(delegate);

      final first = client.get<Object?>('/first');
      while (delegate.refreshCalls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final second = client.get<Object?>('/second');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      delegate.refreshGate!.complete();
      await Future.wait(<Future<Object?>>[first, second]);

      final secondRequests = adapter.requests.where(
        (request) => request.path == '/second',
      );
      expect(secondRequests, hasLength(1));
      expect(secondRequests.single.headers['Authorization'], 'Bearer new');
      expect(delegate.refreshCalls, 1);
    });

    test('replays with the current token when it changed meanwhile', () async {
      final delegate = FakeTokenDelegate(token: 'old', refreshedToken: 'never');
      adapter.responder = (options, _) {
        if (options.headers['Authorization'] == 'Bearer old') {
          // Another part of the app refreshed the session in the meantime.
          delegate.token = 'fresh';
          return jsonBody(<String, Object?>{}, statusCode: 401);
        }
        return jsonBody(<String, Object?>{'ok': true});
      };
      final client = buildClient(delegate);

      final response = await client.get<Map<String, dynamic>>('/a');

      expect(response.data, <String, dynamic>{'ok': true});
      expect(delegate.refreshCalls, 0);
      expect(adapter.headerOf(1, 'Authorization'), 'Bearer fresh');
    });

    test('a refresh without a new token expires the session', () async {
      final delegate = FakeTokenDelegate(token: 'old');
      acceptOnly('Bearer new');
      final client = buildClient(delegate);

      final failure = await _failureOf(client.get<void>('/a'));

      expect(failure, isA<UnauthorizedFailure>());
      expect(failure.message, 'Token expired');
      expect(delegate.refreshCalls, 1);
      expect(delegate.expiredCalls, 1);
      expect(adapter.requests, hasLength(1));
    });

    test('a throwing refresh expires the session', () async {
      final delegate = FakeTokenDelegate(token: 'old')
        ..onRefresh = () async => throw StateError('refresh endpoint down');
      acceptOnly('Bearer new');
      final client = buildClient(delegate);

      final failure = await _failureOf(client.get<void>('/a'));

      expect(failure, isA<UnauthorizedFailure>());
      expect(delegate.expiredCalls, 1);
    });

    test('concurrent failures expire the session only once', () async {
      final delegate = FakeTokenDelegate(token: 'old');
      acceptOnly('Bearer new');
      final client = buildClient(delegate);

      final failures = await Future.wait(<Future<Failure>>[
        _failureOf(client.get<void>('/a')),
        _failureOf(client.get<void>('/b')),
        _failureOf(client.get<void>('/c')),
      ]);

      expect(failures, everyElement(isA<UnauthorizedFailure>()));
      expect(delegate.refreshCalls, 1);
      expect(delegate.expiredCalls, 1);
    });

    test(
      'a replay rejected again expires the session once without looping',
      () async {
        final delegate = FakeTokenDelegate(token: 'old', refreshedToken: 'new');
        adapter.responder =
            (_, _) => jsonBody(<String, Object?>{}, statusCode: 401);
        final client = buildClient(delegate);

        final failure = await _failureOf(client.get<void>('/a'));

        expect(failure, isA<UnauthorizedFailure>());
        expect(delegate.refreshCalls, 1);
        expect(delegate.expiredCalls, 1);
        expect(adapter.requests, hasLength(2));
        expect(adapter.headerOf(1, 'Authorization'), 'Bearer new');
      },
    );

    test('honours refreshOnUnauthorized and custom status codes', () async {
      final delegate = FakeTokenDelegate(token: 'old', refreshedToken: 'new');
      adapter.responder =
          (options, _) =>
              options.headers['Authorization'] == 'Bearer new'
                  ? jsonBody(<String, Object?>{})
                  : jsonBody(<String, Object?>{}, statusCode: 419);
      final client = buildClient(
        delegate,
        config: testConfig(refreshTokenStatusCodes: const <int>{401, 419}),
      );

      final failure = await _failureOf(
        client.get<void>(
          '/no-refresh',
          options: const ApiRequestOptions(refreshOnUnauthorized: false),
        ),
      );
      expect(failure, isA<ServerFailure>());
      expect(delegate.refreshCalls, 0);
      expect(adapter.headerOf(0, 'Authorization'), 'Bearer old');

      final response = await client.get<Map<String, dynamic>>('/refresh');
      expect(response.statusCode, 200);
      expect(delegate.refreshCalls, 1);
    });

    test('a request sent without credentials is not refreshed', () async {
      final delegate = FakeTokenDelegate(refreshedToken: 'new');
      adapter.responder =
          (_, _) => jsonBody(<String, Object?>{}, statusCode: 401);
      final client = buildClient(delegate);

      final failure = await _failureOf(client.get<void>('/a'));

      expect(failure, isA<UnauthorizedFailure>());
      expect(delegate.refreshCalls, 0);
      expect(delegate.expiredCalls, 0);
    });

    test(
      'a request issued by the refresh itself cannot deadlock or loop',
      () async {
        late ApiClient client;
        final delegate = FakeTokenDelegate(token: 'old');
        // A misconfigured refresh call that is not marked unauthenticated.
        delegate.onRefresh = () async {
          final response = await client.post<Map<String, dynamic>>(
            '/auth/refresh',
          );
          return response.data['token'] as String?;
        };
        adapter.responder =
            (_, _) => jsonBody(<String, Object?>{}, statusCode: 401);
        client = buildClient(delegate);

        final failure = await _failureOf(
          client.get<void>('/a'),
        ).timeout(const Duration(seconds: 5));

        expect(failure, isA<UnauthorizedFailure>());
        expect(delegate.refreshCalls, 1);
        expect(delegate.expiredCalls, 1);
        expect(adapter.requests.map((request) => request.path), <String>[
          '/a',
          '/auth/refresh',
        ]);
      },
    );

    test(
      'requests issued by onSessionExpired never trigger a refresh',
      () async {
        late ApiClient client;
        final delegate = FakeTokenDelegate(token: 'old');
        delegate.onExpired = () async {
          delegate.token = 'old';
          await _failureOf(client.post<void>('/auth/logout'));
        };
        adapter.responder =
            (_, _) => jsonBody(<String, Object?>{}, statusCode: 401);
        client = buildClient(delegate);

        final failure = await _failureOf(
          client.get<void>('/a'),
        ).timeout(const Duration(seconds: 5));

        expect(failure, isA<UnauthorizedFailure>());
        expect(delegate.refreshCalls, 1);
        expect(delegate.expiredCalls, 1);
        expect(adapter.requests.map((request) => request.path), <String>[
          '/a',
          '/auth/logout',
        ]);
      },
    );

    test('a multipart upload is replayed with a fresh body', () async {
      final delegate = FakeTokenDelegate(token: 'old', refreshedToken: 'new');
      acceptOnly('Bearer new');
      final client = buildClient(delegate);

      final response = await client.upload<Map<String, dynamic>>(
        '/files',
        files: const <UploadFile>[
          UploadFile.fromBytes(<int>[1, 2, 3], filename: 'a.bin'),
        ],
      );

      expect(response.statusCode, 200);
      expect(adapter.requests, hasLength(2));
      expect(adapter.bodies[1], isNotEmpty);
      expect(adapter.bodies[1].length, adapter.bodies[0].length);
    });
  });

  test('authorizationValue formats the header value', () {
    final interceptor = AuthTokenInterceptor(
      dio: Dio(),
      config: const SymphonyConfig(baseUrl: testBaseUrl, authTokenPrefix: ' '),
    );

    expect(interceptor.authorizationValue('raw'), 'raw');
    expect(interceptor.isRefreshing, isFalse);
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
