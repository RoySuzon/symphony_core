import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/auth/domain/auth_state.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_tokens.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_user.dart';
import 'package:symphony_core/src/features/auth/presentation/controllers/auth_controller.dart';
import 'package:symphony_core/src/features/auth/presentation/providers/auth_providers.dart';
import 'package:symphony_core/src/features/networking/presentation/networking_providers.dart';
import 'package:symphony_core/src/features/storage/data/in_memory_key_value_storage.dart';
import 'package:symphony_core/src/features/storage/data/in_memory_local_database.dart';
import 'package:symphony_core/src/features/storage/presentation/storage_providers.dart';

import 'helpers/core_test_helpers.dart';

/// Matches an error whose description contains [text]. Riverpod 3 wraps
/// provider errors in a `ProviderException`, Riverpod 2 rethrows them as is.
Matcher _throwsMentioning(String text) =>
    throwsA(predicate((Object? error) => '$error'.contains(text)));

/// Simulates an authentication module whose restoration fails unexpectedly.
class _FailingRestoreController extends AuthController {
  @override
  Future<void> restoreSession({bool force = false}) async {
    throw StateError('restore exploded');
  }
}

final _appValueProvider = Provider<int>((ref) => 0, name: '_appValueProvider');

final _childValueProvider = Provider<String>(
  (ref) => 'default',
  name: '_childValueProvider',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(SymphonyCore.reset);

  group('SymphonyCore.initialize', () {
    test('registers the global instance', () async {
      expect(SymphonyCore.isInitialized, isFalse);

      final core = await SymphonyCore.initialize(config: testConfig);

      expect(SymphonyCore.isInitialized, isTrue);
      expect(SymphonyCore.instance, same(core));
      expect(core.config, same(testConfig));
      expect(core.read(symphonyConfigProvider), same(testConfig));
      expect(core.isDisposed, isFalse);
      expect(core.hasAuth, isFalse);
      expect(core.toString(), contains('Core Test App'));
    });

    test('instance throws a helpful error before initialization', () {
      expect(
        () => SymphonyCore.instance,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('SymphonyCore.initialize'),
          ),
        ),
      );
    });

    test('the documented call works and registers synchronously', () async {
      final onErrorBefore = FlutterError.onError;

      final future = SymphonyCore.initialize(
        // Written exactly like the documentation example.
        // ignore: prefer_const_constructors
        config: SymphonyConfig(
          baseUrl: 'https://api.example.com',
          enableInspector: true,
          enableLogging: true,
          // ignore: prefer_const_constructors
          connectTimeout: Duration(seconds: 30),
        ),
      );

      expect(SymphonyCore.isInitialized, isTrue, reason: 'before any await');
      final core = await future;
      expect(SymphonyCore.instance, same(core));
      expect(core.config.enableInspector, isTrue);
      expect(core.config.enableLogging, isTrue);
      expect(core.config.connectTimeout, const Duration(seconds: 30));
      expect(core.logger.enabled, isTrue);
      expect(identical(FlutterError.onError, onErrorBefore), isFalse);

      await SymphonyCore.reset();
      expect(identical(FlutterError.onError, onErrorBefore), isTrue);
    });

    test('re-initialization replaces and disposes the previous instance',
        () async {
      final first = await SymphonyCore.initialize(config: testConfig);
      final second = await SymphonyCore.initialize(
        config: testConfig.copyWith(appName: 'Second'),
      );

      expect(first.isDisposed, isTrue);
      expect(second.isDisposed, isFalse);
      expect(SymphonyCore.instance, same(second));
      expect(SymphonyCore.instance.config.appName, 'Second');
      expect(
        () => first.read(symphonyConfigProvider),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });

    test('a failing re-initialization keeps the previous instance', () async {
      final first = await SymphonyCore.initialize(config: testConfig);

      await expectLater(
        SymphonyCore.initialize(
          config: testConfig,
          authAdapter: FakeAuthAdapter(),
          authAdapterBuilder: (ref) => FakeAuthAdapter(),
        ),
        throwsArgumentError,
      );

      expect(first.isDisposed, isFalse);
      expect(SymphonyCore.instance, same(first));
    });

    test(
        'a re-initialization whose error reporter cannot be created keeps '
        'the previous instance and releases the new container', () async {
      final first = await SymphonyCore.initialize(config: testConfig);
      final onErrorBefore = FlutterError.onError;
      final platformOnErrorBefore = PlatformDispatcher.instance.onError;
      var probeDisposed = false;
      final probe = Provider<int>((ref) {
        ref.onDispose(() => probeDisposed = true);
        return 1;
      });

      await expectLater(
        SymphonyCore.initialize(
          config: testConfig.copyWith(handleGlobalErrors: true),
          overrides: [
            errorReporterProvider.overrideWith((ref) {
              ref.watch(probe);
              throw StateError('no crash reporter');
            }),
          ],
        ),
        _throwsMentioning('no crash reporter'),
      );

      expect(first.isDisposed, isFalse);
      expect(SymphonyCore.instance, same(first));
      expect(first.read(symphonyConfigProvider), same(testConfig));
      expect(probeDisposed, isTrue, reason: 'the new container is disposed');
      expect(identical(FlutterError.onError, onErrorBefore), isTrue);
      expect(
        identical(PlatformDispatcher.instance.onError, platformOnErrorBefore),
        isTrue,
      );
    });

    test('a failing session restoration is contained without a reporter',
        () async {
      final sink = RecordingLogSink();

      final core = await SymphonyCore.initialize(
        config: testConfig,
        authAdapter: FakeAuthAdapter(),
        secureStorage: InMemoryKeyValueStorage(),
        restoreSession: true,
        overrides: [
          authControllerProvider.overrideWith(_FailingRestoreController.new),
          errorReporterProvider.overrideWith(
            (ref) => throw StateError('no crash reporter'),
          ),
          symphonyLoggerProvider.overrideWithValue(
            SymphonyLogger(sinks: <LogSink>[sink]),
          ),
        ],
      );

      expect(SymphonyCore.instance, same(core));
      expect(
        sink.entries.where((e) => e.level == LogLevel.warning).first.message,
        'Session restoration failed',
      );
    });

    test('reset disposes and unregisters the instance', () async {
      final core = await SymphonyCore.initialize(config: testConfig);

      await SymphonyCore.reset();
      await SymphonyCore.reset();

      expect(core.isDisposed, isTrue);
      expect(SymphonyCore.isInitialized, isFalse);
    });

    test('disposing the global instance unregisters it', () async {
      final core = await SymphonyCore.initialize(config: testConfig);

      await core.dispose();
      await core.dispose();

      expect(core.isDisposed, isTrue);
      expect(SymphonyCore.isInitialized, isFalse);
    });

    test(
        'installs the global error handlers when configured and removes '
        'them on dispose', () async {
      final originalOnError = FlutterError.onError;
      final originalPresentError = FlutterError.presentError;
      final originalPlatformOnError = PlatformDispatcher.instance.onError;
      final previousCalls = <FlutterErrorDetails>[];
      final FlutterExceptionHandler previous = previousCalls.add;
      FlutterError.onError = previous;
      FlutterError.presentError = (_) {};
      try {
        final reporter = RecordingErrorReporter();
        final core = await SymphonyCore.initialize(
          config: testConfig.copyWith(handleGlobalErrors: true),
          errorReporter: reporter,
        );

        expect(identical(FlutterError.onError, previous), isFalse);
        FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('layout')),
        );
        PlatformDispatcher.instance.onError!(
          StateError('async'),
          StackTrace.current,
        );

        expect(reporter.reports.map((r) => r.fatal), <bool>[false, true]);
        expect(previousCalls, hasLength(1));

        await core.dispose();

        expect(identical(FlutterError.onError, previous), isTrue);
        expect(
          identical(
              PlatformDispatcher.instance.onError, originalPlatformOnError),
          isTrue,
        );
      } finally {
        FlutterError.onError = originalOnError;
        FlutterError.presentError = originalPresentError;
        PlatformDispatcher.instance.onError = originalPlatformOnError;
      }
    });

    test('does not install error handlers when handleGlobalErrors is false',
        () async {
      final before = FlutterError.onError;

      await SymphonyCore.initialize(config: testConfig);

      expect(identical(FlutterError.onError, before), isTrue);
    });

    test('logs one startup line without secrets', () async {
      final sink = RecordingLogSink();

      await SymphonyCore.initialize(
        config: testConfig.copyWith(
          baseUrl: 'https://user:pa55@api.example.com/v1?api_key=abc&lang=fr',
          enableLogging: true,
        ),
        overrides: [
          symphonyLoggerProvider.overrideWithValue(
            SymphonyLogger(sinks: <LogSink>[sink]),
          ),
        ],
      );

      final info = sink.entries.where((e) => e.level == LogLevel.info).single;
      expect(info.tag, 'SymphonyCore');
      expect(info.message, contains('Core Test App'));
      expect(info.message, contains('api.example.com/v1'));
      expect(info.message, contains('lang=fr'));
      expect(info.message, isNot(contains('pa55')));
      expect(info.message, isNot(contains('user:')));
      expect(info.message, isNot(contains('abc')));
    });

    test('does not create the ApiClient eagerly', () async {
      final core = await SymphonyCore.initialize(config: testConfig);

      expect(core.container.exists(apiClientProvider), isFalse);
    });

    test('an application override wins over the matching parameter', () async {
      final parameterReporter = RecordingErrorReporter();
      final appReporter = RecordingErrorReporter();
      const appConfig = SymphonyConfig(
        baseUrl: 'https://override.example.com',
        handleGlobalErrors: false,
      );

      final core = await SymphonyCore.initialize(
        config: testConfig,
        errorReporter: parameterReporter,
        overrides: [
          errorReporterProvider.overrideWithValue(appReporter),
          symphonyConfigProvider.overrideWithValue(appConfig),
        ],
      );

      expect(core.read(errorReporterProvider), same(appReporter));
      expect(core.config, same(appConfig));
    });
  });

  group('authentication', () {
    test('exposes the adapter and the controller', () async {
      final adapter = FakeAuthAdapter();
      final core = await SymphonyCore.initialize(
        config: testConfig,
        authAdapter: adapter,
        secureStorage: InMemoryKeyValueStorage(),
      );

      expect(core.hasAuth, isTrue);
      expect(core.read(authAdapterProvider), same(adapter));
      expect(core.auth, isA<AuthController>());
      expect(core.auth, same(core.read(authControllerProvider.notifier)));
    });

    test('auth throws a helpful error without an adapter', () async {
      final core = await SymphonyCore.initialize(config: testConfig);

      expect(
        () => core.auth,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('authAdapter'),
          ),
        ),
      );
    });

    test('authAdapterBuilder enables authentication', () async {
      final core = await SymphonyCore.initialize(
        config: testConfig,
        authAdapterBuilder: (ref) => FakeAuthAdapter(),
        secureStorage: InMemoryKeyValueStorage(),
      );

      expect(core.hasAuth, isTrue);
      expect(core.read(authAdapterProvider), isA<FakeAuthAdapter>());
    });

    test('restoreSession restores a persisted session', () async {
      final storage = InMemoryKeyValueStorage();
      final seed = SymphonyCore.create(
        config: testConfig,
        authAdapter: FakeAuthAdapter(),
        secureStorage: storage,
      );
      final sessionStorage = seed.read(sessionStorageProvider);
      await sessionStorage.writeTokens(
        const AuthTokens(accessToken: 'persisted', refreshToken: 'refresh'),
      );
      await sessionStorage.writeUser(
        const AuthUser(id: 'user-7', displayName: 'Ada').toJson(),
      );
      await seed.dispose();

      final core = await SymphonyCore.initialize(
        config: testConfig,
        authAdapter: FakeAuthAdapter(),
        secureStorage: storage,
        restoreSession: true,
      );

      final state = core.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect(state.user?.id, 'user-7');
    });

    test('restoreSession without a persisted session ends unauthenticated',
        () async {
      final core = await SymphonyCore.initialize(
        config: testConfig,
        authAdapter: FakeAuthAdapter(),
        secureStorage: InMemoryKeyValueStorage(),
        restoreSession: true,
      );

      expect(core.read(authControllerProvider), isA<AuthUnauthenticated>());
    });

    test('a failing session restoration is reported, not thrown', () async {
      final reporter = RecordingErrorReporter();
      final sink = RecordingLogSink();

      final core = await SymphonyCore.initialize(
        config: testConfig,
        authAdapter: FakeAuthAdapter(),
        secureStorage: InMemoryKeyValueStorage(),
        errorReporter: reporter,
        restoreSession: true,
        overrides: [
          authControllerProvider.overrideWith(_FailingRestoreController.new),
          symphonyLoggerProvider.overrideWithValue(
            SymphonyLogger(sinks: <LogSink>[sink]),
          ),
        ],
      );

      expect(SymphonyCore.instance, same(core));
      final report = reporter.reports.single;
      expect(report.error, isA<StateError>());
      expect(report.reason, contains('session restoration failed'));
      expect(report.fatal, isFalse);
      expect(
        sink.entries.where((e) => e.level == LogLevel.warning).single.message,
        'Session restoration failed',
      );
    });

    test('restoreSession without an adapter only logs a warning', () async {
      final sink = RecordingLogSink();

      await SymphonyCore.initialize(
        config: testConfig,
        restoreSession: true,
        overrides: [
          symphonyLoggerProvider.overrideWithValue(
            SymphonyLogger(sinks: <LogSink>[sink]),
          ),
        ],
      );

      expect(
        sink.entries.where((e) => e.level == LogLevel.warning).single.message,
        contains('no auth adapter'),
      );
    });
  });

  group('services', () {
    test('logger and read use the container', () async {
      final core = await SymphonyCore.initialize(config: testConfig);

      expect(core.logger, same(core.read(symphonyLoggerProvider)));
      expect(core.logger, same(core.container.read(symphonyLoggerProvider)));
    });

    test('apiClient is the shared client configured from the config', () async {
      final core = await SymphonyCore.initialize(config: testConfig);

      final client = core.apiClient;

      expect(client, same(core.read(apiClientProvider)));
      expect(client.baseUrl, testConfig.baseUrl);
    });

    test('a disposed instance rejects reads and wrap', () async {
      final core = SymphonyCore.create(config: testConfig);
      await core.dispose();

      expect(() => core.read(symphonyConfigProvider), throwsStateError);
      expect(() => core.logger, throwsStateError);
      expect(() => core.wrap(const SizedBox()), throwsStateError);
      expect(core.config, same(testConfig), reason: 'still describable');
    });
  });

  group('SymphonyCore.create', () {
    test('creates independent instances that are not registered', () async {
      final a = SymphonyCore.create(config: testConfig);
      final b = SymphonyCore.create(config: testConfig.copyWith(appName: 'B'));
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      expect(SymphonyCore.isInitialized, isFalse);
      expect(a.container, isNot(same(b.container)));
      expect(a.config.appName, 'Core Test App');
      expect(b.read(symphonyConfigProvider).appName, 'B');
    });

    test('does not touch the global instance', () async {
      final global = await SymphonyCore.initialize(config: testConfig);
      final local = SymphonyCore.create(config: testConfig);

      await local.dispose();

      expect(SymphonyCore.instance, same(global));
      expect(global.isDisposed, isFalse);
    });

    test('installs error handlers only when asked', () async {
      final before = FlutterError.onError;
      final platformBefore = PlatformDispatcher.instance.onError;

      final withoutHandlers = SymphonyCore.create(
        config: testConfig.copyWith(handleGlobalErrors: true),
      );
      expect(identical(FlutterError.onError, before), isTrue);
      await withoutHandlers.dispose();

      final withHandlers = SymphonyCore.create(
        config: testConfig,
        installErrorHandlers: true,
      );
      expect(identical(FlutterError.onError, before), isFalse);
      await withHandlers.dispose();

      expect(identical(FlutterError.onError, before), isTrue);
      expect(
        identical(PlatformDispatcher.instance.onError, platformBefore),
        isTrue,
      );
    });

    test('rejects both authAdapter and authAdapterBuilder', () {
      expect(
        () => SymphonyCore.create(
          config: testConfig,
          authAdapter: FakeAuthAdapter(),
          authAdapterBuilder: (ref) => FakeAuthAdapter(),
        ),
        throwsArgumentError,
      );
    });

    test('releases the container when the error handlers cannot be set up', () {
      final onErrorBefore = FlutterError.onError;
      var probeDisposed = false;
      final probe = Provider<int>((ref) {
        ref.onDispose(() => probeDisposed = true);
        return 1;
      });

      expect(
        () => SymphonyCore.create(
          config: testConfig,
          installErrorHandlers: true,
          overrides: [
            errorReporterProvider.overrideWith((ref) {
              ref.watch(probe);
              throw StateError('no crash reporter');
            }),
          ],
        ),
        _throwsMentioning('no crash reporter'),
      );

      expect(probeDisposed, isTrue, reason: 'the container is disposed');
      expect(identical(FlutterError.onError, onErrorBefore), isTrue);
    });
  });

  group('local database', () {
    test('initialize and create use the given database', () async {
      final database = InMemoryLocalDatabase();
      addTearDown(database.close);

      final global = await SymphonyCore.initialize(
        config: testConfig,
        localDatabase: database,
      );
      final local = SymphonyCore.create(
        config: testConfig,
        localDatabase: database,
      );
      addTearDown(local.dispose);

      expect(global.read(localDatabaseProvider), same(database));
      expect(local.read(localDatabaseProvider), same(database));
    });

    test('the application owns the lifecycle of the database', () async {
      final database = InMemoryLocalDatabase();
      addTearDown(database.close);
      final core = SymphonyCore.create(
        config: testConfig,
        localDatabase: database,
      );
      await core.read(localDatabaseProvider).open();

      await core.dispose();

      expect(database.isOpen, isTrue, reason: 'not closed by SymphonyCore');
    });

    test('defaults to the provider of the storage module', () async {
      final core = SymphonyCore.create(config: testConfig);
      addTearDown(core.dispose);

      expect(core.read(localDatabaseProvider), isA<InMemoryLocalDatabase>());
    });

    test('is rejected with a parent container', () {
      final root = ProviderContainer(
        overrides: symphonyOverrides(config: testConfig),
      );
      addTearDown(root.dispose);

      expect(
        () => SymphonyCore.create(
          config: testConfig,
          parent: root,
          localDatabase: InMemoryLocalDatabase(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('parent container', () {
    ProviderContainer configuredRoot({
      SymphonyConfig config = testConfig,
      ErrorReporter? errorReporter,
      bool withAuth = false,
    }) {
      final root = ProviderContainer(
        overrides: [
          ...symphonyOverrides(
            config: config,
            errorReporter: errorReporter,
            authAdapter: withAuth ? FakeAuthAdapter() : null,
            secureStorage: withAuth ? InMemoryKeyValueStorage() : null,
          ),
          _appValueProvider.overrideWithValue(42),
        ],
      );
      addTearDown(root.dispose);
      return root;
    }

    test('exposes the providers of a configured parent hierarchy', () async {
      final reporter = RecordingErrorReporter();
      final root = configuredRoot(errorReporter: reporter);

      final core = SymphonyCore.create(
        config: testConfig,
        parent: root,
        overrides: [_childValueProvider.overrideWithValue('child')],
      );

      expect(core.config, same(testConfig));
      expect(core.read(_appValueProvider), 42);
      expect(core.read(_childValueProvider), 'child');
      expect(core.read(errorReporterProvider), same(reporter));
      expect(core.logger, same(root.read(symphonyLoggerProvider)));
      expect(core.hasAuth, isFalse);
      expect(core.toString(), contains('auth: false'));

      await core.dispose();
      expect(root.read(_appValueProvider), 42, reason: 'parent stays alive');
      expect(root.read(_childValueProvider), 'default');
    });

    test('uses the authentication configured in the parent hierarchy',
        () async {
      final root = configuredRoot(withAuth: true);

      final core = SymphonyCore.create(config: testConfig, parent: root);
      addTearDown(core.dispose);

      expect(core.hasAuth, isTrue);
      expect(core.read(authAdapterProvider), isA<FakeAuthAdapter>());
      expect(core.auth, isA<AuthController>());
    });

    test('initialize accepts a configured parent', () async {
      final root = configuredRoot();

      final core = await SymphonyCore.initialize(
        config: testConfig,
        parent: root,
      );

      expect(SymphonyCore.instance, same(core));
      expect(core.read(_appValueProvider), 42);
    });

    test('rejects a parent that is not configured for symphony_core', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);

      expect(
        () => SymphonyCore.create(config: testConfig, parent: root),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('symphonyOverrides'),
          ),
        ),
      );
    });

    test('rejects a configuration that differs from the parent one', () {
      final root = configuredRoot();

      expect(
        () => SymphonyCore.create(
          config: testConfig.copyWith(appName: 'Other'),
          parent: root,
        ),
        throwsArgumentError,
      );
    });

    test('rejects services that belong to the parent hierarchy', () {
      final root = configuredRoot();

      for (final create in <SymphonyCore Function()>[
        () => SymphonyCore.create(
              config: testConfig,
              parent: root,
              authAdapter: FakeAuthAdapter(),
            ),
        () => SymphonyCore.create(
              config: testConfig,
              parent: root,
              authAdapterBuilder: (ref) => FakeAuthAdapter(),
            ),
        () => SymphonyCore.create(
              config: testConfig,
              parent: root,
              secureStorage: InMemoryKeyValueStorage(),
            ),
        () => SymphonyCore.create(
              config: testConfig,
              parent: root,
              errorReporter: const NoopErrorReporter(),
            ),
      ]) {
        expect(create, throwsArgumentError);
      }
    });

    test('initialize rejects the container of the instance it replaces',
        () async {
      final first = await SymphonyCore.initialize(config: testConfig);

      await expectLater(
        SymphonyCore.initialize(config: testConfig, parent: first.container),
        throwsArgumentError,
      );
      expect(first.isDisposed, isFalse);
    });
  });
}
