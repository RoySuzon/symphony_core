import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';
import 'package:symphony_core_example/app/app_router.dart';
import 'package:symphony_core_example/app/example_app.dart';
import 'package:symphony_core_example/core/backend/demo_backend.dart';
import 'package:symphony_core_example/core/backend/demo_database.dart';
import 'package:symphony_core_example/features/auth/data/example_auth_adapter.dart';

/// Configuration used by the tests (logging off to keep the output short).
const SymphonyConfig testConfig = SymphonyConfig(
  baseUrl: 'https://api.example.com',
  appName: 'Symphony Example',
  enableInspector: true,
);

/// A fast demo backend: no bandwidth simulation, short latency.
DemoBackend createTestBackend({
  Duration latency = Duration.zero,
  DateTime Function()? clock,
}) {
  return DemoBackend(
    latency: latency,
    uploadBytesPerSecond: null,
    downloadBytesPerSecond: null,
    clock: clock,
  );
}

/// An isolated [SymphonyCore] wired exactly like `main.dart` (not the
/// global instance), with in-memory storage instead of the platform's
/// secure storage.
SymphonyCore createTestCore(DemoBackend backend, {KeyValueStorage? storage}) {
  return SymphonyCore.create(
    config: testConfig,
    authAdapterBuilder: createExampleAuthAdapter,
    secureStorage: storage ?? InMemoryKeyValueStorage(),
    overrides: [httpClientAdapterProvider.overrideWithValue(backend)],
  );
}

/// The example app mounted in a widget test.
class ExampleAppHarness {
  ExampleAppHarness._(this.tester, this.core, this.backend);

  /// The tester.
  final WidgetTester tester;

  /// The app's core instance.
  final SymphonyCore core;

  /// The demo backend answering the requests.
  final DemoBackend backend;

  /// The app router.
  GoRouter get router => core.read(routerProvider);

  /// `METHOD /path STATUS` of every request handled by the backend.
  List<String> get requests => <String>[
        for (final record in backend.requestLog)
          '${record.method} ${record.path} ${record.statusCode}',
      ];

  /// Pumps (fake time) until [finder] matches something.
  Future<void> pumpUntilFound(
    Finder finder, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await pumpUntil(() => finder.evaluate().isNotEmpty, timeout: timeout);
    expect(finder, findsWidgets, reason: 'Still not found after $timeout');
  }

  /// Pumps (fake time) until [condition] holds or [timeout] elapses.
  ///
  /// `pumpAndSettle` is not used: progress indicators animate forever.
  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    const step = Duration(milliseconds: 50);
    final attempts = timeout.inMilliseconds ~/ step.inMilliseconds;
    for (var i = 0; i < attempts && !condition(); i++) {
      await tester.pump(step);
    }
  }

  /// Lets pending requests, timers and animations finish.
  Future<void> settle([Duration duration = const Duration(seconds: 2)]) async {
    const step = Duration(milliseconds: 50);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
      await tester.pump(step);
    }
  }

  /// Taps the icon of the button whose tooltip is [message].
  ///
  /// The icon is tapped rather than the `Tooltip` itself: on recent Flutter
  /// versions the tooltip's own render box does not always report a
  /// hit-testable position.
  Future<void> tapTooltip(String message) async {
    // Let page transitions finish: the button may still be sliding in.
    await settle(const Duration(milliseconds: 600));
    await tester.tap(
      find.descendant(
        of: find.byTooltip(message),
        matching: find.byType(Icon),
      ),
    );
    await tester.pump();
  }

  /// Waits for the login screen and signs in with the login form.
  Future<void> signIn(String email, {String password = demoPassword}) async {
    await pumpUntilFound(find.byKey(SymphonyLoginForm.identifierInputKey));
    await tester.enterText(
      find.byKey(SymphonyLoginForm.identifierInputKey),
      email,
    );
    await tester.enterText(
      find.byKey(SymphonyLoginForm.passwordInputKey),
      password,
    );
    await tester.tap(find.byKey(SymphonyLoginForm.submitButtonKey));
    await tester.pump();
  }

  /// Signs in as [email] and waits for the dashboard.
  Future<void> signInAndOpenDashboard(String email) async {
    await signIn(email);
    await pumpUntilFound(find.byType(SymphonyDashboard));
    await settle(const Duration(milliseconds: 500));
  }

  /// Unmounts the app and disposes the core.
  Future<void> dispose() async {
    await settle();
    await tester.pumpWidget(const SizedBox.shrink());
    await core.dispose();
  }
}

/// Mounts the example app (as `main.dart` does, but with an isolated core)
/// on a surface of [size] logical pixels (large by default).
Future<ExampleAppHarness> pumpExampleApp(
  WidgetTester tester, {
  DemoBackend? backend,
  Size size = const Size(1280, 2000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final demo = backend ??
      createTestBackend(
        latency: const Duration(milliseconds: 20),
      );
  final core = createTestCore(demo);
  addTearDown(core.dispose);
  await tester.pumpWidget(SymphonyScope(core: core, child: const ExampleApp()));
  return ExampleAppHarness._(tester, core, demo);
}
