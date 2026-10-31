import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_user.dart';
import 'package:symphony_core/src/features/auth/presentation/providers/auth_providers.dart';
import 'package:symphony_core/src/features/networking/presentation/networking_providers.dart';
import 'package:symphony_core/src/features/storage/data/in_memory_key_value_storage.dart';
import 'package:symphony_core/src/features/storage/presentation/storage_providers.dart';

import '../helpers/core_test_helpers.dart';

/// Matches the error thrown when reading an unconfigured provider. Riverpod 3
/// wraps it in a `ProviderException`, Riverpod 2 rethrows it as is.
Matcher throwsMentioning(String text) =>
    throwsA(predicate((Object? error) => '$error'.contains(text)));

void main() {
  ProviderContainer track(ProviderContainer container) {
    addTearDown(container.dispose);
    return container;
  }

  test('overrides the configuration', () {
    final overrides = symphonyOverrides(config: testConfig);
    final container = track(ProviderContainer(overrides: overrides));

    expect(overrides, hasLength(1));
    expect(container.read(symphonyConfigProvider), same(testConfig));
  });

  test('leaves authentication unconfigured without an adapter', () {
    final container = track(
      ProviderContainer(overrides: symphonyOverrides(config: testConfig)),
    );

    expect(container.read(authTokenDelegateProvider), isNull);
    expect(
      () => container.read(authAdapterProvider),
      throwsMentioning('authAdapterProvider is not configured'),
    );
  });

  test('wires the auth adapter and the session token delegate', () {
    final adapter = FakeAuthAdapter();
    const delegate = FakeTokenDelegate();
    final overrides = symphonyOverrides(
      config: testConfig,
      authAdapter: adapter,
      overrides: [sessionTokenDelegateProvider.overrideWithValue(delegate)],
    );
    final container = track(ProviderContainer(overrides: overrides));

    expect(overrides, hasLength(4));
    expect(container.read(authAdapterProvider), same(adapter));
    expect(container.read(authTokenDelegateProvider), same(delegate));
  });

  test('authAdapterBuilder creates the adapter from the container', () {
    const delegate = FakeTokenDelegate();
    final container = track(
      ProviderContainer(
        overrides: symphonyOverrides(
          config: testConfig,
          authAdapterBuilder: (ref) => FakeAuthAdapter(
            user: AuthUser(id: ref.watch(symphonyConfigProvider).appName),
          ),
          overrides: [sessionTokenDelegateProvider.overrideWithValue(delegate)],
        ),
      ),
    );

    final adapter = container.read(authAdapterProvider);
    expect(adapter, isA<FakeAuthAdapter>());
    expect((adapter as FakeAuthAdapter).user.id, testConfig.appName);
    expect(container.read(authTokenDelegateProvider), same(delegate));
  });

  test('rejects both authAdapter and authAdapterBuilder', () {
    expect(
      () => symphonyOverrides(
        config: testConfig,
        authAdapter: FakeAuthAdapter(),
        authAdapterBuilder: (ref) => FakeAuthAdapter(),
      ),
      throwsArgumentError,
    );
  });

  test('overrides the secure storage and the error reporter', () {
    final storage = InMemoryKeyValueStorage();
    final reporter = RecordingErrorReporter();
    final container = track(
      ProviderContainer(
        overrides: symphonyOverrides(
          config: testConfig,
          secureStorage: storage,
          errorReporter: reporter,
        ),
      ),
    );

    expect(container.read(secureStorageProvider), same(storage));
    expect(container.read(errorReporterProvider), same(reporter));
  });

  test('appends the application overrides last, in order', () {
    final first = sessionTokenDelegateProvider.overrideWithValue(
      const FakeTokenDelegate(),
    );
    final second = symphonyLoggerProvider.overrideWithValue(
      SymphonyLogger.disabled(),
    );

    final overrides = symphonyOverrides(
      config: testConfig,
      errorReporter: const NoopErrorReporter(),
      overrides: [first, second],
    );

    expect(overrides, hasLength(4));
    expect(identical(overrides[2], first), isTrue);
    expect(identical(overrides[3], second), isTrue);
  });

  test('an application override wins over the built-in one', () {
    const appConfig = SymphonyConfig(baseUrl: 'https://override.example.com');
    final builtInReporter = RecordingErrorReporter();
    final appReporter = RecordingErrorReporter();

    // Riverpod 3 rejects duplicated overrides in debug builds: creating the
    // container proves the built-in overrides were left out there.
    final container = track(
      ProviderContainer(
        overrides: symphonyOverrides(
          config: testConfig,
          errorReporter: builtInReporter,
          overrides: [
            symphonyConfigProvider.overrideWithValue(appConfig),
            errorReporterProvider.overrideWith((ref) => appReporter),
          ],
        ),
      ),
    );

    expect(container.read(symphonyConfigProvider), same(appConfig));
    expect(container.read(errorReporterProvider), same(appReporter));
  });

  test('an application override of the token delegate wins', () {
    const appDelegate = FakeTokenDelegate();
    final container = track(
      ProviderContainer(
        overrides: symphonyOverrides(
          config: testConfig,
          authAdapter: FakeAuthAdapter(),
          overrides: [authTokenDelegateProvider.overrideWithValue(appDelegate)],
        ),
      ),
    );

    expect(container.read(authTokenDelegateProvider), same(appDelegate));
  });
}
