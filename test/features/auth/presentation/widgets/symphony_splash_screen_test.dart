import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../../support/auth_test_support.dart';

void main() {
  late InMemoryKeyValueStorage storage;
  late InMemoryAuthAdapter adapter;

  setUp(() {
    storage = InMemoryKeyValueStorage();
    adapter = InMemoryAuthAdapter(accounts: demoAccounts);
  });

  Future<void> pumpSplash(
    WidgetTester tester,
    ProviderContainer container,
    SymphonySplashScreen splash,
  ) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: splash),
      ),
    );
  }

  testWidgets(
      'restores the session after the first frame and waits for the '
      'minimum duration', (tester) async {
    final container = createAuthContainer(adapter: adapter, storage: storage);
    final statesDuringBuild = <AuthState>[];
    AuthState? completed;
    await pumpSplash(
      tester,
      container,
      SymphonySplashScreen(
        builder: (context, error, retry) => Consumer(
          builder: (context, ref, _) {
            statesDuringBuild.add(ref.watch(authControllerProvider));
            return const SizedBox.shrink();
          },
        ),
        onCompleted: (state) => completed = state,
      ),
    );

    // The first frame is built before the restoration starts.
    expect(statesDuringBuild.first, isA<AuthUnknown>());

    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    expect(completed, isNull);

    await tester.pump(const Duration(milliseconds: 600));
    expect(completed, isA<AuthUnauthenticated>());
  });

  testWidgets('reports a restored session', (tester) async {
    final session = await adapter.login(
      AuthCredentials.emailPassword(
        email: 'admin@example.com',
        password: 'secret123',
      ),
    );
    await persistSession(storage, session);
    final container = createAuthContainer(adapter: adapter, storage: storage);
    AuthState? completed;
    await pumpSplash(
      tester,
      container,
      SymphonySplashScreen(
        minDisplayDuration: Duration.zero,
        onCompleted: (state) => completed = state,
      ),
    );

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(completed, isA<AuthAuthenticated>());
    expect(completed?.user, adminUser);
  });

  testWidgets('shows the application name, logo and subtitle', (tester) async {
    final container = createAuthContainer(adapter: adapter);
    await pumpSplash(
      tester,
      container,
      const SymphonySplashScreen(
        logo: Icon(Icons.music_note),
        subtitle: 'Loading your workspace',
        loadingMessage: 'Please wait',
      ),
    );

    expect(find.text(testConfig.appName), findsOneWidget);
    expect(find.text('Loading your workspace'), findsOneWidget);
    expect(find.text('Please wait'), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('runs onInitialize before restoring the session', (tester) async {
    final container = createAuthContainer(adapter: adapter);
    final events = <String>[];
    await pumpSplash(
      tester,
      container,
      SymphonySplashScreen(
        minDisplayDuration: Duration.zero,
        onInitialize: (ref) async {
          events.add(
            'initialize:${ref.read(authControllerProvider).status.name}',
          );
        },
        onCompleted: (state) => events.add('completed:${state.status.name}'),
      ),
    );

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(events, <String>[
      'initialize:unknown',
      'completed:unauthenticated',
    ]);
  });

  testWidgets('shows an error with a retry button when start-up fails',
      (tester) async {
    final container = createAuthContainer(adapter: adapter);
    var attempts = 0;
    AuthState? completed;
    await pumpSplash(
      tester,
      container,
      SymphonySplashScreen(
        minDisplayDuration: Duration.zero,
        errorTitle: 'Startup failed',
        onInitialize: (ref) async {
          attempts++;
          if (attempts == 1) throw const NetworkFailure('Server unreachable');
        },
        onCompleted: (state) => completed = state,
      ),
    );

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Startup failed'), findsOneWidget);
    expect(find.text('Server unreachable'), findsOneWidget);
    expect(completed, isNull);
    expect(container.read(authControllerProvider), isA<AuthUnknown>());

    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(attempts, 2);
    expect(completed, isA<AuthUnauthenticated>());
  });

  testWidgets('renders a custom body', (tester) async {
    final container = createAuthContainer(adapter: adapter);
    await pumpSplash(
      tester,
      container,
      SymphonySplashScreen(
        builder: (context, error, retry) => const Text('Custom splash'),
      ),
    );

    expect(find.text('Custom splash'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('can skip the session restoration', (tester) async {
    final container = createAuthContainer(adapter: adapter);
    AuthState? completed;
    await pumpSplash(
      tester,
      container,
      SymphonySplashScreen(
        minDisplayDuration: Duration.zero,
        restoreAuthSession: false,
        onCompleted: (state) => completed = state,
      ),
    );

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(completed, isA<AuthUnknown>());
  });
}
