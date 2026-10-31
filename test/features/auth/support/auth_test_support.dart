import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/di/core_providers.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/networking/data/api_client.dart';
import 'package:symphony_core/src/features/networking/domain/api_request_options.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

class MockAuthAdapter extends Mock implements AuthAdapter {}

class MockApiClient extends Mock implements ApiClient {}

class MockAuthRepository extends Mock implements AuthRepository {}

/// Configuration used by every auth test.
const SymphonyConfig testConfig = SymphonyConfig(
  baseUrl: 'https://api.example.test',
);

/// A fixed point in time used as the test clock.
final DateTime testNow = DateTime.utc(2026, 1, 1, 12);

/// Default expiry of [testTokens]: valid for the fixed test clock and for
/// repositories using the real clock.
final DateTime farFuture = DateTime.utc(2100);

const AuthUser adminUser = AuthUser(
  id: '1',
  displayName: 'Ada Admin',
  email: 'admin@example.com',
  roles: <String>{'admin'},
  permissions: <String>{'orders.read', 'orders.write'},
);

const AuthUser plainUser = AuthUser(
  id: '2',
  displayName: 'Paul Plain',
  email: 'user@example.com',
  roles: <String>{'user'},
);

AuthTokens testTokens({
  String access = 'access-1',
  String? refresh = 'refresh-1',
  DateTime? expiresAt,
}) {
  return AuthTokens(
    accessToken: access,
    refreshToken: refresh,
    tokenType: 'Bearer',
    expiresAt: expiresAt ?? farFuture,
  );
}

AuthSession testSession({AuthTokens? tokens, AuthUser? user = adminUser}) =>
    AuthSession(tokens: tokens ?? testTokens(), user: user);

/// Demo accounts of the in-memory backend.
const List<InMemoryAccount> demoAccounts = <InMemoryAccount>[
  InMemoryAccount(
    identifier: 'admin@example.com',
    password: 'secret123',
    user: adminUser,
  ),
  InMemoryAccount(
    identifier: 'user@example.com',
    password: 'password1',
    user: plainUser,
  ),
];

void registerAuthFallbacks() {
  registerFallbackValue(const AuthCredentials(<String, Object?>{}));
  registerFallbackValue(const AuthTokens(accessToken: 'fallback'));
  registerFallbackValue(
    const AuthSession(tokens: AuthTokens(accessToken: 'fallback')),
  );
  registerFallbackValue(const ApiRequestOptions());
}

/// Stubs the members of [adapter] with the behaviour of [AuthAdapter]'s
/// default implementations.
void stubAdapterDefaults(MockAuthAdapter adapter) {
  when(() => adapter.validateSession(any())).thenAnswer((_) async {});
  when(() => adapter.fetchCurrentUser(any())).thenAnswer(
    (invocation) async =>
        (invocation.positionalArguments.first as AuthSession).user,
  );
  when(() => adapter.logout(any())).thenAnswer((_) async {});
  when(
    () => adapter.refresh(any()),
  ).thenAnswer((_) => Future<AuthTokens>.error(const UnauthorizedFailure()));
  when(() => adapter.supportsRegistration).thenReturn(false);
  when(() => adapter.supportsPasswordRecovery).thenReturn(false);
}

/// Writes [session] into [storage] the way the repository does.
Future<void> persistSession(
  KeyValueStorage storage,
  AuthSession session,
) async {
  final sessionStorage = SecureSessionStorage(storage);
  await sessionStorage.writeTokens(session.tokens);
  final user = session.user;
  if (user != null) await sessionStorage.writeUser(user.toJson());
}

/// Reads the session persisted in [storage].
Future<AuthSession?> readPersistedSession(KeyValueStorage storage) async {
  final sessionStorage = SecureSessionStorage(storage);
  final tokens = await sessionStorage.readTokens();
  if (tokens == null) return null;
  final user = await sessionStorage.readUser();
  return AuthSession(
    tokens: tokens,
    user: user == null ? null : AuthUser.fromJson(user),
  );
}

/// A container wired like an application using `symphony_core` auth.
///
/// [overrides] are Riverpod overrides (typed `Object` so that callers never
/// need to import `package:flutter_riverpod/misc.dart` for `Override`).
ProviderContainer createAuthContainer({
  required AuthAdapter adapter,
  KeyValueStorage? storage,
  List<Object> overrides = const <Object>[],
}) {
  final container = ProviderContainer(
    overrides: [
      symphonyConfigProvider.overrideWithValue(testConfig),
      authAdapterProvider.overrideWithValue(adapter),
      secureStorageProvider.overrideWithValue(
        storage ?? InMemoryKeyValueStorage(),
      ),
      ...overrides.cast(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Pumps [child] inside a Material app using [container].
Future<void> pumpAuthWidget(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// A [SessionStorage] whose operations fail.
class FailingSessionStorage extends SessionStorage {
  FailingSessionStorage({
    this.failReads = false,
    this.failWrites = false,
    this.failClear = false,
    SessionStorage? delegate,
  }) : delegate = delegate ?? SecureSessionStorage(InMemoryKeyValueStorage());

  final bool failReads;
  final bool failWrites;
  final bool failClear;
  final SessionStorage delegate;

  Never _fail() => throw StateError('storage unavailable');

  @override
  Future<AuthTokens?> readTokens() async =>
      failReads ? _fail() : delegate.readTokens();

  @override
  Future<Map<String, Object?>?> readUser() async =>
      failReads ? _fail() : delegate.readUser();

  @override
  Future<void> writeTokens(AuthTokens tokens) async =>
      failWrites ? _fail() : delegate.writeTokens(tokens);

  @override
  Future<void> writeUser(Map<String, Object?> user) async =>
      failWrites ? _fail() : delegate.writeUser(user);

  @override
  Future<void> clear() async => failClear ? _fail() : delegate.clear();
}

/// Completes once all pending microtasks and zero-delay timers ran.
Future<void> flushMicrotasks() => Future<void>.delayed(Duration.zero);
