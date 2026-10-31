import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/di/core_providers.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/networking/data/default_api_error_mapper.dart';
import 'package:symphony_core/src/features/networking/presentation/networking_providers.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../support/auth_test_support.dart';

/// A scripted HTTP backend plugged into the real `ApiClient`.
class FakeBackend implements HttpClientAdapter {
  FakeBackend(this.handle);

  final ResponseBody Function(RequestOptions request) handle;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(int status, Object? body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

String? authorizationOf(RequestOptions request) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == 'authorization') return '${entry.value}';
  }
  return null;
}

void main() {
  late InMemoryKeyValueStorage storage;
  late Set<String> validAccessTokens;
  late bool refreshAllowed;
  late int refreshCalls;
  late Object? loginRejection;
  late FakeBackend backend;

  ResponseBody route(RequestOptions request) {
    final authorization = authorizationOf(request);
    final authorized =
        authorization != null &&
        validAccessTokens.contains(authorization.replaceFirst('Bearer ', ''));
    switch ('${request.method} ${request.uri.path}') {
      case 'POST /auth/login':
        final body = request.data as Map;
        if (body['email'] != 'admin@example.com' ||
            body['password'] != 'secret123') {
          return jsonResponse(401, loginRejection);
        }
        validAccessTokens.add('a1');
        return jsonResponse(200, <String, Object?>{
          'access_token': 'a1',
          'refresh_token': 'r1',
          'expires_in': 3600,
          'user': <String, Object?>{
            'id': 1,
            'name': 'Ada',
            'roles': <String>['admin'],
          },
        });
      case 'POST /auth/refresh':
        refreshCalls++;
        final body = request.data as Map;
        if (!refreshAllowed || body['refresh_token'] != 'r1') {
          return jsonResponse(401, <String, Object?>{'message': 'Expired'});
        }
        validAccessTokens.add('a2');
        return jsonResponse(200, <String, Object?>{'access_token': 'a2'});
      case 'GET /orders':
        return authorized
            ? jsonResponse(200, <Object?>['order-1'])
            : jsonResponse(401, <String, Object?>{'message': 'Expired'});
      case 'POST /auth/logout':
        return authorized
            ? jsonResponse(200, <String, Object?>{})
            : jsonResponse(401, <String, Object?>{'message': 'Expired'});
    }
    return jsonResponse(404, <String, Object?>{'message': 'Not found'});
  }

  ProviderContainer createContainer({List<Object> overrides = const []}) {
    final container = ProviderContainer(
      overrides: [
        symphonyConfigProvider.overrideWithValue(testConfig),
        secureStorageProvider.overrideWithValue(storage),
        httpClientAdapterProvider.overrideWithValue(backend),
        authAdapterProvider.overrideWith(
          (ref) => RestAuthAdapter(
            apiClient: ref.watch(apiClientProvider),
            endpoints: const RestAuthEndpoints(
              login: '/auth/login',
              refresh: '/auth/refresh',
              logout: '/auth/logout',
            ),
          ),
        ),
        authTokenDelegateProvider.overrideWith(
          (ref) => ref.watch(sessionTokenDelegateProvider),
        ),
        ...overrides.cast(),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> signIn(ProviderContainer container) async {
    final result = await container
        .read(authControllerProvider.notifier)
        .login(
          AuthCredentials.emailPassword(
            email: 'admin@example.com',
            password: 'secret123',
          ),
        );
    expect(result.isSuccess, isTrue);
  }

  setUp(() {
    storage = InMemoryKeyValueStorage();
    validAccessTokens = <String>{};
    refreshAllowed = true;
    refreshCalls = 0;
    loginRejection = <String, Object?>{'message': 'Bad login'};
    backend = FakeBackend(route);
  });

  test(
    'signs in through a public call and authorizes later requests',
    () async {
      final container = createContainer();

      await signIn(container);
      final orders = await container
          .read(apiClientProvider)
          .get<Object?>('/orders');

      expect(orders.data, <Object?>['order-1']);
      expect(authorizationOf(backend.requests.first), isNull);
      expect(authorizationOf(backend.requests.last), 'Bearer a1');
      expect(container.read(accessContextProvider).hasRole('admin'), isTrue);
    },
  );

  test('wrong credentials surface as an AuthFailure', () async {
    final container = createContainer();

    final result = await container
        .read(authControllerProvider.notifier)
        .login(
          AuthCredentials.emailPassword(
            email: 'admin@example.com',
            password: 'nope',
          ),
        );

    expect(result.failureOrNull, isA<AuthFailure>());
    expect(refreshCalls, 0);
  });

  test('a bare 401 on sign-in reports invalid credentials even with a '
      'localized error mapper', () async {
    loginRejection = <String, Object?>{};
    final container = createContainer(
      overrides: <Object>[
        apiErrorMapperProvider.overrideWithValue(
          const DefaultApiErrorMapper(
            unauthorizedMessage: 'Sitzung abgelaufen.',
          ),
        ),
      ],
    );

    final result = await container
        .read(authControllerProvider.notifier)
        .login(
          AuthCredentials.emailPassword(
            email: 'admin@example.com',
            password: 'nope',
          ),
        );

    expect(
      result.failureOrNull,
      isA<AuthFailure>().having(
        (failure) => failure.message,
        'message',
        'Invalid credentials. Please try again.',
      ),
    );
  });

  test('refreshes an expired token, retries and updates the session', () async {
    final container = createContainer();
    await signIn(container);
    validAccessTokens.remove('a1');

    final orders = await container
        .read(apiClientProvider)
        .get<Object?>('/orders');

    expect(orders.data, <Object?>['order-1']);
    expect(refreshCalls, 1);
    expect(authorizationOf(backend.requests.last), 'Bearer a2');
    final session = container.read(authControllerProvider).session;
    expect(session?.tokens.accessToken, 'a2');
    expect(session?.tokens.refreshToken, 'r1');
    expect((await readPersistedSession(storage))?.tokens.accessToken, 'a2');
  });

  test('signs the user out when the refresh is rejected', () async {
    final container = createContainer();
    await signIn(container);
    validAccessTokens.clear();
    refreshAllowed = false;

    await expectLater(
      container.read(apiClientProvider).get<Object?>('/orders'),
      throwsA(isA<UnauthorizedFailure>()),
    );

    final state = container.read(authControllerProvider);
    expect(state, isA<AuthUnauthenticated>());
    expect((state as AuthUnauthenticated).failure, isA<UnauthorizedFailure>());
    expect(await readPersistedSession(storage), isNull);
  });

  test('logout sends the token and never refreshes', () async {
    final container = createContainer();
    await signIn(container);
    validAccessTokens.clear();

    await container.read(authControllerProvider.notifier).logout();

    final logout = backend.requests.last;
    expect(logout.uri.path, '/auth/logout');
    expect(authorizationOf(logout), 'Bearer a1');
    expect(refreshCalls, 0);
    expect(
      container.read(authControllerProvider),
      const AuthState.unauthenticated(),
    );
    expect(await readPersistedSession(storage), isNull);
  });

  test('a restarted app restores the persisted session', () async {
    await signIn(createContainer());

    final restarted = createContainer();
    await restarted.read(authControllerProvider.notifier).restoreSession();

    expect(restarted.read(currentUserProvider)?.displayName, 'Ada');
    final orders = await restarted
        .read(apiClientProvider)
        .get<Object?>('/orders');
    expect(orders.data, <Object?>['order-1']);
  });
}
