import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/symphony_core.dart';
import 'package:symphony_core_example/core/backend/demo_backend.dart';
import 'package:symphony_core_example/core/backend/demo_database.dart';
import 'package:symphony_core_example/features/orders/presentation/providers/orders_providers.dart';

import 'support/example_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late DemoBackend backend;
  late SymphonyCore core;

  setUp(() {
    now = DateTime.utc(2026, 10, 31, 9);
    backend = createTestBackend(clock: () => now);
    core = createTestCore(backend);
  });

  tearDown(() => core.dispose());

  Future<String> signIn(String email) async {
    final result = await core.auth.login(
      AuthCredentials.emailPassword(email: email, password: demoPassword),
    );
    expect(result.isSuccess, isTrue, reason: '${result.failureOrNull}');
    return core.read(authControllerProvider).session!.tokens.accessToken;
  }

  List<String> requests() => <String>[
    for (final record in backend.requestLog)
      '${record.method} ${record.path} ${record.statusCode}',
  ];

  test(
    'the custom AuthResponseMapping reads the non-default response shape',
    () async {
      await signIn('admin@example.com');

      final state = core.read(authControllerProvider);
      final user = state.user!;
      expect(user.id, 'usr_admin');
      expect(user.displayName, 'Alice Admin');
      expect(user.email, 'admin@example.com');
      expect(user.roles, <String>{'admin'});
      expect(user.permissions, containsAll(demoAllPermissions));
      expect(state.session!.tokens.tokenType, 'Bearer');
      expect(state.session!.tokens.canRefresh, isTrue);
      expect(core.read(accessContextProvider).hasRole('admin'), isTrue);
    },
  );

  test(
    'an expired access token is refreshed and the request replayed',
    () async {
      final firstToken = await signIn('staff@example.com');

      // The demo backend issues 30 s access tokens.
      now = now.add(const Duration(seconds: 31));
      final orders = await core.read(ordersRepositoryProvider).fetchOrders();

      expect(orders.isSuccess, isTrue, reason: '${orders.failureOrNull}');
      expect(orders.valueOrNull, hasLength(18));
      expect(
        requests(),
        containsAllInOrder(<String>[
          'POST /auth/login 200',
          'GET /orders 401',
          'POST /auth/token/refresh 200',
          'GET /orders 200',
        ]),
      );
      expect(backend.requestLog[1].errorCode, 'token_expired');

      // The refreshed session is published to the auth state.
      final state = core.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect(state.session!.tokens.accessToken, isNot(firstToken));

      // ...and the whole sequence is visible in the API inspector.
      final calls = core.read(apiInspectorProvider).calls.reversed.toList();
      expect(
        <String>[for (final call in calls) '${call.method} ${call.path}'],
        containsAllInOrder(<String>[
          'GET /orders',
          'POST /auth/token/refresh',
          'GET /orders',
        ]),
      );
      expect(calls.map((call) => call.statusCode), contains(401));
      final refresh = calls.firstWhere(
        (call) => call.path == '/auth/token/refresh',
      );
      // Tokens never reach the inspector in clear text.
      expect(refresh.requestBody, isNot(contains(firstToken)));
    },
  );

  test(
    'expiring every token from the developer tools triggers a refresh',
    () async {
      final firstToken = await signIn('admin@example.com');

      backend.expireAccessTokens();
      final result = await core
          .read(ordersRepositoryProvider)
          .fetchOrder('ord_1001');

      expect(result.valueOrNull?.summary.number, 'SO-1001');
      expect(
        core.read(authControllerProvider).session!.tokens.accessToken,
        isNot(firstToken),
      );
    },
  );

  test('concurrent requests share a single refresh', () async {
    await signIn('admin@example.com');
    now = now.add(const Duration(minutes: 5));

    final results = await Future.wait(<Future<Result<Object?>>>[
      core.read(ordersRepositoryProvider).fetchOrders(),
      core.read(ordersRepositoryProvider).fetchOrder('ord_1018'),
      core.read(ordersRepositoryProvider).fetchOrder('ord_1017'),
    ]);

    expect(results.every((result) => result.isSuccess), isTrue);
    expect(
      requests().where((r) => r.startsWith('POST /auth/token/refresh')),
      hasLength(1),
    );
  });

  test('a revoked session signs the user out', () async {
    await signIn('staff@example.com');

    backend.revokeSessions();
    backend.expireAccessTokens();
    final result = await core.read(ordersRepositoryProvider).fetchOrders();

    expect(result.failureOrNull, isA<UnauthorizedFailure>());
    expect(requests(), contains('POST /auth/token/refresh 401'));
    final state = core.read(authControllerProvider);
    expect(state, isA<AuthUnauthenticated>());
    expect((state as AuthUnauthenticated).failure, isNotNull);
  });

  test('a persisted session is restored after an app restart', () async {
    final storage = InMemoryKeyValueStorage();
    final firstRun = createTestCore(backend, storage: storage);
    final login = await firstRun.auth.login(
      AuthCredentials.emailPassword(
        email: 'admin@example.com',
        password: demoPassword,
      ),
    );
    expect(login.isSuccess, isTrue);
    await firstRun.dispose();

    // Restart: new core, new backend instance (tokens are self-describing),
    // ten minutes later.
    now = now.add(const Duration(minutes: 10));
    final restartedBackend = createTestBackend(clock: () => now);
    final secondRun = createTestCore(restartedBackend, storage: storage);
    addTearDown(secondRun.dispose);
    await secondRun.auth.restoreSession();

    expect(secondRun.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(secondRun.read(currentUserProvider)?.email, 'admin@example.com');
    expect(
      <String>[
        for (final record in restartedBackend.requestLog)
          '${record.method} ${record.path} ${record.statusCode}',
      ],
      containsAllInOrder(<String>[
        'POST /auth/token/refresh 200',
        'GET /auth/me 200',
      ]),
    );
  });
}
