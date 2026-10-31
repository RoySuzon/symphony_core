import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/networking/domain/api_request_options.dart';
import 'package:symphony_core/src/features/networking/domain/api_response.dart';

import '../support/auth_test_support.dart';

/// One request captured by [MockApiClient].
class CapturedRequest {
  CapturedRequest(this.path, this.method, this.data, this.options);

  final String path;
  final String method;
  final Object? data;
  final ApiRequestOptions options;
}

void main() {
  setUpAll(registerAuthFallbacks);

  late MockApiClient client;
  final responses = <String, Object? Function()>{};
  final requests = <CapturedRequest>[];

  const endpoints = RestAuthEndpoints(
    login: '/auth/login',
    refresh: '/auth/refresh',
    logout: '/auth/logout',
    currentUser: '/me',
    register: '/auth/register',
    requestPasswordReset: '/auth/password/forgot',
    confirmPasswordReset: '/auth/password/reset',
  );

  RestAuthAdapter createAdapter({
    RestAuthEndpoints endpoints = endpoints,
    AuthResponseMapping mapping = const AuthResponseMapping(),
    Object? Function(AuthCredentials credentials)? loginBody,
    Object? Function(AuthTokens tokens)? refreshBody,
    Map<String, String> Function(AuthTokens tokens)? refreshHeaders,
    String refreshTokenField = 'refresh_token',
    AuthSession Function(Object? data)? parseSession,
    AuthTokens Function(Object? data, AuthTokens previous)? parseRefresh,
    AuthUser? Function(Object? data)? parseUser,
    AuthSession? Function(Object? data)? parseRegistration,
    Object? Function(AuthSession session)? logoutBody,
    Object? Function(AuthCredentials data)? registerBody,
    bool fetchUserAfterLogin = true,
    Future<void> Function(AuthSession session)? sessionValidator,
  }) {
    return RestAuthAdapter(
      apiClient: client,
      endpoints: endpoints,
      mapping: mapping,
      loginBody: loginBody,
      refreshBody: refreshBody,
      refreshHeaders: refreshHeaders,
      refreshTokenField: refreshTokenField,
      parseSession: parseSession,
      parseRefresh: parseRefresh,
      parseUser: parseUser,
      parseRegistration: parseRegistration,
      logoutBody: logoutBody,
      registerBody: registerBody,
      fetchUserAfterLogin: fetchUserAfterLogin,
      sessionValidator: sessionValidator,
      clock: () => testNow,
    );
  }

  /// The requests sent so far (recorded from the invocations, so the order
  /// of named arguments does not matter).
  List<CapturedRequest> captured() => List<CapturedRequest>.of(requests);

  setUp(() {
    client = MockApiClient();
    responses.clear();
    requests.clear();
    when(() => client.config).thenReturn(testConfig);
    when(
      () => client.request<Object?>(
        any(),
        method: any(named: 'method'),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((invocation) async {
      final path = invocation.positionalArguments.first as String;
      requests.add(
        CapturedRequest(
          path,
          invocation.namedArguments[#method] as String,
          invocation.namedArguments[#data],
          invocation.namedArguments[#options] as ApiRequestOptions,
        ),
      );
      final handler = responses[path];
      if (handler == null) {
        throw StateError('Unexpected request to $path');
      }
      return ApiResponse<Object?>(data: handler(), statusCode: 200);
    });
  });

  group('login', () {
    const credentials = AuthCredentials(<String, Object?>{
      'email': 'admin@example.com',
      'password': 'secret123',
    });

    test('posts the credentials as an unauthenticated request', () async {
      responses['/auth/login'] = () => <String, Object?>{
            'access_token': 'a1',
            'refresh_token': 'r1',
            'user': <String, Object?>{'id': 1},
          };

      await createAdapter().login(credentials);

      final request = captured().single;
      expect(request.path, '/auth/login');
      expect(request.method, 'POST');
      expect(request.data, credentials.fields);
      expect(request.options.requiresAuth, isFalse);
      expect(request.options.refreshOnUnauthorized, isFalse);
    });

    test('uses the loginBody hook', () async {
      responses['/auth/login'] = () => <String, Object?>{
            'token': 'a1',
            'user': <String, Object?>{'id': 1},
          };

      await createAdapter(
        loginBody: (c) => <String, Object?>{
          'username': c['email'],
          'pwd': c['password'],
          'device': 'mobile',
        },
      ).login(credentials);

      expect(captured().single.data, <String, Object?>{
        'username': 'admin@example.com',
        'pwd': 'secret123',
        'device': 'mobile',
      });
    });

    test('maps a flat OAuth-like response', () async {
      responses['/auth/login'] = () => <String, Object?>{
            'access_token': 'a1',
            'refresh_token': 'r1',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'user': <String, Object?>{
              'id': 42,
              'name': 'Ada',
              'email': 'ada@example.com',
              'roles': <Object?>['admin', 'editor'],
              'permissions': <Object?>['orders.read'],
            },
          };

      final session = await createAdapter().login(credentials);

      expect(session.tokens.accessToken, 'a1');
      expect(session.tokens.refreshToken, 'r1');
      expect(session.tokens.tokenType, 'Bearer');
      expect(
        session.tokens.expiresAt,
        testNow.add(const Duration(seconds: 3600)),
      );
      final user = session.user!;
      expect(user.id, '42');
      expect(user.displayName, 'Ada');
      expect(user.email, 'ada@example.com');
      expect(user.roles, <String>{'admin', 'editor'});
      expect(user.permissions, <String>{'orders.read'});
      expect(user.data['name'], 'Ada');
    });

    test('maps a nested data envelope with a single role string', () async {
      responses['/auth/login'] = () => <String, Object?>{
            'data': <String, Object?>{
              'accessToken': 'a1',
              'refreshToken': 'r1',
              'expiresAt': '2026-01-02T00:00:00.000Z',
              'user': <String, Object?>{
                'uuid': 'u-1',
                'first_name': 'Grace',
                'last_name': 'Hopper',
                'role': 'editor',
                'scopes': 'orders.read orders.write',
              },
            },
          };

      final session = await createAdapter().login(credentials);

      expect(session.tokens.accessToken, 'a1');
      expect(session.tokens.expiresAt, DateTime.utc(2026, 1, 2));
      expect(session.user?.id, 'u-1');
      expect(session.user?.displayName, 'Grace Hopper');
      expect(session.user?.roles, <String>{'editor'});
      expect(
        session.user?.permissions,
        <String>{'orders.read', 'orders.write'},
      );
    });

    test('reads the expiry of a JWT access token', () async {
      final exp = DateTime.utc(2026, 3, 1).millisecondsSinceEpoch ~/ 1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode(<String, Object?>{'exp': exp})))
          .replaceAll('=', '');
      responses['/auth/login'] = () => <String, Object?>{
            'token': 'header.$payload.signature',
            'user': <String, Object?>{'id': 1},
          };

      final session = await createAdapter().login(credentials);

      expect(session.tokens.expiresAt, DateTime.utc(2026, 3, 1));
    });

    test('supports custom mappings', () async {
      responses['/auth/login'] = () => <String, Object?>{
            'result': <String, Object?>{
              'jwt': 'a1',
              'account': <String, Object?>{
                'key': 'k-9',
                'groups': <Object?>[
                  <String, Object?>{'name': 'staff'},
                  <String, Object?>{'name': 'manager'},
                ],
              },
            },
          };

      final session = await createAdapter(
        mapping: const AuthResponseMapping(
          accessToken: <String>['result.jwt'],
          user: <String>['result.account'],
          userId: <String>['key'],
          userRoles: <String>['groups'],
        ),
      ).login(credentials);

      expect(session.tokens.accessToken, 'a1');
      expect(session.user?.id, 'k-9');
      expect(session.user?.roles, <String>{'staff', 'manager'});
    });

    test('uses the parseSession hook', () async {
      responses['/auth/login'] = () => <String, Object?>{'k': 'custom'};

      final session = await createAdapter(
        parseSession: (data) => AuthSession(
          tokens: AuthTokens(accessToken: '${(data! as Map)['k']}'),
          user: plainUser,
        ),
      ).login(credentials);

      expect(session.tokens.accessToken, 'custom');
      expect(session.user, plainUser);
    });

    test('throws an AuthFailure when the access token is missing', () async {
      responses['/auth/login'] = () => <String, Object?>{'status': 'ok'};

      await expectLater(
        createAdapter().login(credentials),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.message,
            'message',
            'Invalid authentication response',
          ),
        ),
      );
    });

    test('rejects custom parser results without an access token', () async {
      responses['/auth/login'] = () => <String, Object?>{};
      responses['/auth/refresh'] = () => <String, Object?>{};

      await expectLater(
        createAdapter(
          parseSession: (_) =>
              const AuthSession(tokens: AuthTokens(accessToken: ' ')),
        ).login(credentials),
        throwsA(isA<AuthFailure>()),
      );
      await expectLater(
        createAdapter(
          parseRefresh: (_, previous) => previous.copyWith(accessToken: ''),
        ).refresh(testTokens()),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('converts parser crashes into a ParsingFailure', () async {
      responses['/auth/login'] = () => 'not json';

      await expectLater(
        createAdapter(parseSession: (data) => throw TypeError()).login(
          credentials,
        ),
        throwsA(isA<ParsingFailure>()),
      );
    });

    test('turns a 401 into an invalid credentials AuthFailure', () async {
      when(
        () => client.request<Object?>(
          any(),
          method: any(named: 'method'),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) => Future<ApiResponse<Object?>>.error(const UnauthorizedFailure()),
      );

      await expectLater(
        createAdapter().login(credentials),
        throwsA(
          isA<AuthFailure>()
              .having((f) => f.message, 'message', contains('Invalid'))
              .having((f) => f.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('loads the user with the new token when the response has none',
        () async {
      responses['/auth/login'] = () => <String, Object?>{'token': 'a1'};
      responses['/me'] = () => <String, Object?>{
            'data': <String, Object?>{'id': 5, 'email': 'me@example.com'},
          };

      final session = await createAdapter().login(credentials);

      expect(session.user?.id, '5');
      final requests = captured();
      expect(requests, hasLength(2));
      final me = requests.last;
      expect(me.path, '/me');
      expect(me.method, 'GET');
      expect(me.options.requiresAuth, isFalse);
      expect(me.options.refreshOnUnauthorized, isFalse);
      expect(me.options.headers, <String, String>{
        'Authorization': 'Bearer a1',
      });
    });

    test('skips the user lookup when disabled', () async {
      responses['/auth/login'] = () => <String, Object?>{'token': 'a1'};

      final session =
          await createAdapter(fetchUserAfterLogin: false).login(credentials);

      expect(session.user, isNull);
      expect(captured(), hasLength(1));
    });

    test('decodes JSON string bodies', () async {
      responses['/auth/login'] =
          () => '{"access_token": "a1", "user": {"id": "7"}}';

      final session = await createAdapter().login(credentials);

      expect(session.tokens.accessToken, 'a1');
      expect(session.user?.id, '7');
    });
  });

  group('refresh', () {
    final current = testTokens();

    test('posts the refresh token as an unauthenticated request', () async {
      responses['/auth/refresh'] = () => <String, Object?>{
            'access_token': 'a2',
            'refresh_token': 'r2',
            'expires_in': '60',
          };

      final tokens = await createAdapter().refresh(current);

      expect(tokens.accessToken, 'a2');
      expect(tokens.refreshToken, 'r2');
      expect(tokens.expiresAt, testNow.add(const Duration(seconds: 60)));
      final request = captured().single;
      expect(request.path, '/auth/refresh');
      expect(request.data, <String, Object?>{'refresh_token': 'refresh-1'});
      expect(request.options.requiresAuth, isFalse);
      expect(request.options.refreshOnUnauthorized, isFalse);
    });

    test('keeps the previous refresh token when none is returned', () async {
      responses['/auth/refresh'] = () => <String, Object?>{'access': 'a2'};

      final tokens = await createAdapter().refresh(current);

      expect(tokens.accessToken, 'a2');
      expect(tokens.refreshToken, 'refresh-1');
    });

    test('honours refreshTokenField, refreshBody and refreshHeaders', () async {
      responses['/auth/refresh'] = () => <String, Object?>{'token': 'a2'};

      await createAdapter(refreshTokenField: 'refresh').refresh(current);
      await createAdapter(
        refreshBody: (t) => <String, Object?>{
          'grant_type': 'refresh_token',
          'token': t.refreshToken,
        },
        refreshHeaders: (t) => <String, String>{
          'X-Refresh-Token': t.refreshToken!,
        },
      ).refresh(current);

      final requests = captured();
      expect(requests[0].data, <String, Object?>{'refresh': 'refresh-1'});
      expect(requests[1].data, <String, Object?>{
        'grant_type': 'refresh_token',
        'token': 'refresh-1',
      });
      expect(
        requests[1].options.headers,
        <String, String>{'X-Refresh-Token': 'refresh-1'},
      );
      expect(requests[1].options.requiresAuth, isFalse);
    });

    test('uses the parseRefresh hook', () async {
      responses['/auth/refresh'] = () => <String, Object?>{'x': 'a2'};

      final tokens = await createAdapter(
        parseRefresh: (data, previous) => previous.copyWith(
          accessToken: '${(data! as Map)['x']}',
        ),
      ).refresh(current);

      expect(tokens.accessToken, 'a2');
      expect(tokens.refreshToken, 'refresh-1');
    });

    test('is unauthorized without endpoint or refresh token', () async {
      await expectLater(
        createAdapter(endpoints: const RestAuthEndpoints(login: '/login'))
            .refresh(current),
        throwsA(isA<UnauthorizedFailure>()),
      );
      await expectLater(
        createAdapter().refresh(testTokens(refresh: null)),
        throwsA(isA<UnauthorizedFailure>()),
      );
      verifyNever(
        () => client.request<Object?>(
          any(),
          method: any(named: 'method'),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
    });

    test('throws an AuthFailure when the response has no token', () async {
      responses['/auth/refresh'] = () => <String, Object?>{};

      await expectLater(
        createAdapter().refresh(current),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('logout', () {
    test('sends the session token without triggering a refresh', () async {
      responses['/auth/logout'] = () => null;

      await createAdapter(
        logoutBody: (s) => <String, Object?>{
          'refresh_token': s.tokens.refreshToken,
        },
      ).logout(testSession());

      final request = captured().single;
      expect(request.path, '/auth/logout');
      expect(request.method, 'POST');
      expect(request.data, <String, Object?>{'refresh_token': 'refresh-1'});
      expect(request.options.refreshOnUnauthorized, isFalse);
      expect(
        request.options.headers,
        <String, String>{'Authorization': 'Bearer access-1'},
      );
    });

    test('uses the configured header name and prefix', () async {
      responses['/auth/logout'] = () => null;
      when(() => client.config).thenReturn(
        testConfig.copyWith(authHeaderName: 'X-Auth', authTokenPrefix: ''),
      );

      await createAdapter().logout(testSession());

      expect(
        captured().single.options.headers,
        <String, String>{'X-Auth': 'access-1'},
      );
    });

    test('does nothing without a logout endpoint', () async {
      await createAdapter(endpoints: const RestAuthEndpoints(login: '/login'))
          .logout(testSession());

      verifyNever(
        () => client.request<Object?>(
          any(),
          method: any(named: 'method'),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
    });
  });

  group('fetchCurrentUser', () {
    test('uses a regular authenticated request', () async {
      responses['/me'] = () => <String, Object?>{
            'id': 9,
            'username': 'grace',
            'avatar_url': 'https://example.com/a.png',
            'roles': <String, Object?>{'admin': true, 'editor': false},
          };

      final user = await createAdapter().fetchCurrentUser(testSession());

      expect(user?.id, '9');
      expect(user?.username, 'grace');
      expect(user?.avatarUrl, 'https://example.com/a.png');
      expect(user?.roles, <String>{'admin'});
      final request = captured().single;
      expect(request.method, 'GET');
      expect(request.options.requiresAuth, isTrue);
      expect(request.options.refreshOnUnauthorized, isTrue);
      expect(request.options.headers, isEmpty);
    });

    test('uses the parseUser hook', () async {
      responses['/me'] = () => <String, Object?>{'whatever': true};

      final user = await createAdapter(parseUser: (_) => plainUser)
          .fetchCurrentUser(testSession());

      expect(user, plainUser);
    });

    test('returns the session user without an endpoint', () async {
      final user = await createAdapter(
        endpoints: const RestAuthEndpoints(login: '/login'),
      ).fetchCurrentUser(testSession(user: plainUser));

      expect(user, plainUser);
    });
  });

  group('registration', () {
    const data = AuthCredentials(<String, Object?>{
      'email': 'new@example.com',
      'password': 'secret123',
      'name': 'New',
    });

    test('returns a session when the response contains tokens', () async {
      responses['/auth/register'] = () => <String, Object?>{
            'access_token': 'a1',
            'user': <String, Object?>{'id': 3, 'email': 'new@example.com'},
          };

      final session = await createAdapter().register(data);

      expect(session?.tokens.accessToken, 'a1');
      expect(session?.user?.email, 'new@example.com');
      final request = captured().single;
      expect(request.data, data.fields);
      expect(request.options.requiresAuth, isFalse);
      expect(request.options.refreshOnUnauthorized, isFalse);
    });

    test('returns null when the user is not signed in', () async {
      responses['/auth/register'] = () => <String, Object?>{
            'message': 'Check your inbox',
          };

      expect(await createAdapter().register(data), isNull);
    });

    test('uses the registerBody and parseRegistration hooks', () async {
      responses['/auth/register'] = () => <String, Object?>{'ok': true};

      final session = await createAdapter(
        registerBody: (d) => <String, Object?>{'account': d.fields},
        parseRegistration: (_) => testSession(),
      ).register(data);

      expect(session, testSession());
      expect(captured().single.data, <String, Object?>{'account': data.fields});
    });

    test('is unsupported without an endpoint', () async {
      final adapter = createAdapter(
        endpoints: const RestAuthEndpoints(login: '/login'),
      );

      expect(adapter.supportsRegistration, isFalse);
      await expectLater(
        adapter.register(data),
        throwsA(isA<UnsupportedFailure>()),
      );
    });
  });

  group('password recovery', () {
    const request = AuthCredentials(<String, Object?>{'email': 'a@b.co'});
    const confirm = AuthCredentials(<String, Object?>{
      'email': 'a@b.co',
      'code': '123456',
      'password': 'newSecret1',
    });

    test('sends unauthenticated requests to the configured endpoints',
        () async {
      responses['/auth/password/forgot'] = () => null;
      responses['/auth/password/reset'] = () => null;
      final adapter = createAdapter();

      await adapter.requestPasswordReset(request);
      await adapter.confirmPasswordReset(confirm);

      final requests = captured();
      expect(requests[0].path, '/auth/password/forgot');
      expect(requests[0].data, request.fields);
      expect(requests[0].options.requiresAuth, isFalse);
      expect(requests[1].path, '/auth/password/reset');
      expect(requests[1].data, confirm.fields);
      expect(requests[1].options.requiresAuth, isFalse);
    });

    test('is unsupported without endpoints', () async {
      final adapter = createAdapter(
        endpoints: const RestAuthEndpoints(login: '/login'),
      );

      expect(adapter.supportsPasswordRecovery, isFalse);
      await expectLater(
        adapter.requestPasswordReset(request),
        throwsA(isA<UnsupportedFailure>()),
      );
      await expectLater(
        adapter.confirmPasswordReset(confirm),
        throwsA(isA<UnsupportedFailure>()),
      );
    });
  });

  test('derives the supported features from the endpoints', () {
    final full = createAdapter();
    final minimal =
        createAdapter(endpoints: const RestAuthEndpoints(login: '/login'));

    expect(full.supportsRegistration, isTrue);
    expect(full.supportsPasswordRecovery, isTrue);
    expect(minimal.supportsRegistration, isFalse);
    expect(minimal.supportsPasswordRecovery, isFalse);
  });

  test('sessionValidator implements the business rules', () async {
    final adapter = createAdapter(
      sessionValidator: (session) async {
        if (!(session.user?.roles.contains('admin') ?? false)) {
          throw const AuthFailure('Administrators only');
        }
      },
    );

    await expectLater(adapter.validateSession(testSession()), completes);
    await expectLater(
      adapter.validateSession(testSession(user: plainUser)),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('resolves the ApiClient lazily', () async {
    var resolutions = 0;
    responses['/auth/login'] = () => <String, Object?>{
          'token': 'a1',
          'user': <String, Object?>{'id': 1},
        };
    final adapter = RestAuthAdapter(
      apiClientResolver: () {
        resolutions++;
        return client;
      },
      endpoints: endpoints,
    );

    expect(resolutions, 0);
    await adapter.login(const AuthCredentials(<String, Object?>{}));
    expect(resolutions, greaterThan(0));
  });
}
