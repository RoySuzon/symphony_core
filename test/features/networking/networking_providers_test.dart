import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/di/core_providers.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/inspector/data/api_inspector_interceptor.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

import 'support/networking_fakes.dart';

class _MarkerInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Marker'] = 'on';
    handler.next(options);
  }
}

class _ConstantMapper extends ApiErrorMapper {
  const _ConstantMapper();

  @override
  Failure map(Object error, StackTrace stackTrace) =>
      const ServerFailure('mapped by override');
}

/// Stands for the auth module's delegate, which depends on the ApiClient
/// through its repository and adapter.
class _ClientBackedDelegate extends FakeTokenDelegate {
  _ClientBackedDelegate(this.client) : super(token: 'from-session');

  final ApiClient client;
}

void main() {
  late FakeHttpClientAdapter adapter;

  setUp(() {
    adapter = FakeHttpClientAdapter();
  });

  // Override lists are built here with inferred types, so the `Override`
  // type (exported by `package:flutter_riverpod/misc.dart`) is never named.
  ProviderContainer createContainer({
    SymphonyConfig? config,
    bool clientBackedDelegate = false,
    ApiErrorMapper? errorMapper,
    List<Interceptor>? interceptors,
    List<HeaderProvider>? headerProviders,
    bool autoDispose = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        symphonyConfigProvider.overrideWithValue(config ?? testConfig()),
        httpClientAdapterProvider.overrideWithValue(adapter),
        if (clientBackedDelegate)
          authTokenDelegateProvider.overrideWith(
            (ref) => _ClientBackedDelegate(ref.watch(apiClientProvider)),
          ),
        if (errorMapper != null)
          apiErrorMapperProvider.overrideWithValue(errorMapper),
        if (interceptors != null)
          apiInterceptorsProvider.overrideWithValue(interceptors),
        if (headerProviders != null)
          apiHeaderProvidersProvider.overrideWithValue(headerProviders),
      ],
    );
    if (autoDispose) addTearDown(container.dispose);
    return container;
  }

  test('defaults: no delegate, default mapper, no extra interceptors', () {
    final container = createContainer();

    expect(container.read(authTokenDelegateProvider), isNull);
    expect(
      container.read(apiErrorMapperProvider),
      isA<DefaultApiErrorMapper>(),
    );
    expect(container.read(apiInterceptorsProvider), isEmpty);
    expect(container.read(apiHeaderProvidersProvider), isEmpty);
    final client = container.read(apiClientProvider);
    expect(client.baseUrl, testBaseUrl);
    expect(client.dio.httpClientAdapter, same(adapter));
  });

  test(
    'resolves the token delegate lazily, so it may depend on the client',
    () async {
      final container = createContainer(clientBackedDelegate: true);

      final client = container.read(apiClientProvider);
      await client.get<void>('/me');

      expect(adapter.headerOf(0, 'Authorization'), 'Bearer from-session');
      final delegate =
          container.read(authTokenDelegateProvider)! as _ClientBackedDelegate;
      expect(delegate.client, same(client));
    },
  );

  test(
    'uses the overridden mapper, interceptors and header providers',
    () async {
      adapter.responder =
          (options, _) =>
              options.path == '/fail'
                  ? jsonBody(<String, Object?>{}, statusCode: 500)
                  : jsonBody(<String, Object?>{});
      final container = createContainer(
        errorMapper: const _ConstantMapper(),
        interceptors: <Interceptor>[_MarkerInterceptor()],
        headerProviders: <HeaderProvider>[
          () => <String, String>{'Accept-Language': 'fr'},
        ],
      );
      final client = container.read(apiClientProvider);

      await client.get<void>('/ok');
      Failure? failure;
      try {
        await client.get<void>('/fail');
      } on Failure catch (error) {
        failure = error;
      }

      expect(adapter.headerOf(0, 'X-Marker'), 'on');
      expect(adapter.headerOf(0, 'Accept-Language'), 'fr');
      expect(failure?.message, 'mapped by override');
    },
  );

  test('installs the inspector only when it is enabled', () {
    final disabled = createContainer().read(apiClientProvider);
    final enabled = createContainer(
      config: testConfig(enableInspector: true),
    ).read(apiClientProvider);

    expect(
      disabled.dio.interceptors.whereType<ApiInspectorInterceptor>(),
      isEmpty,
    );
    expect(
      enabled.dio.interceptors.whereType<ApiInspectorInterceptor>(),
      hasLength(1),
    );
  });

  test('closes the client on dispose without closing the shared adapter', () {
    final container = createContainer(autoDispose: false);
    final client = container.read(apiClientProvider);

    container.dispose();

    expect(client.isClosed, isTrue);
    expect(adapter.closed, isFalse);
  });
}
