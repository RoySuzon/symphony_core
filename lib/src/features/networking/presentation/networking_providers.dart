import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../inspector/presentation/inspector_providers.dart';
import '../data/api_client.dart';
import '../data/default_api_error_mapper.dart';
import '../domain/api_error_mapper.dart';
import '../domain/auth_token_delegate.dart';

/// The [AuthTokenDelegate] used by [apiClientProvider], or `null` when the
/// application does not use authenticated requests.
///
/// `SymphonyCore` overrides it with the session based delegate of the auth
/// module. Applications that manage tokens themselves can override it too.
///
/// [apiClientProvider] reads it lazily (on each request), so the delegate may
/// itself depend on [apiClientProvider].
final authTokenDelegateProvider = Provider<AuthTokenDelegate?>(
  (ref) => null,
  name: 'authTokenDelegateProvider',
);

/// The [ApiErrorMapper] used by [apiClientProvider] to convert errors into
/// failures. Override it to parse project specific error payloads, e.g.
/// `apiErrorMapperProvider.overrideWithValue(const MyErrorMapper())`.
final apiErrorMapperProvider = Provider<ApiErrorMapper>(
  (ref) => const DefaultApiErrorMapper(),
  name: 'apiErrorMapperProvider',
);

/// Custom interceptors installed by [apiClientProvider] after the logging
/// interceptor and before the header / token interceptors. Empty by default.
final apiInterceptorsProvider = Provider<List<Interceptor>>(
  (ref) => const <Interceptor>[],
  name: 'apiInterceptorsProvider',
);

/// Dynamic header providers (locale, app version, tenant...) applied to every
/// request made by [apiClientProvider]. Empty by default.
final apiHeaderProvidersProvider = Provider<List<HeaderProvider>>(
  (ref) => const <HeaderProvider>[],
  name: 'apiHeaderProvidersProvider',
);

/// The [HttpClientAdapter] used by [apiClientProvider], or `null` for Dio's
/// platform default. Override it for tests, mock servers or certificate
/// pinning. The adapter is never closed by the client: dispose it from the
/// overriding provider if needed.
final httpClientAdapterProvider = Provider<HttpClientAdapter?>(
  (ref) => null,
  name: 'httpClientAdapterProvider',
);

/// The central [ApiClient], configured from `symphonyConfigProvider` and the
/// networking providers above. It is closed when the provider is disposed
/// (for example when the configuration changes).
final apiClientProvider = Provider<ApiClient>(
  (ref) {
    final config = ref.watch(symphonyConfigProvider);
    // The token delegate is resolved lazily, on each request, because it
    // usually depends on this provider:
    // apiClient -> delegate -> auth repository -> adapter -> apiClient.
    // It is read through the container rather than `ref.read`: in debug
    // builds Riverpod (2.x and 3.x) throws a CircularDependencyError when a
    // provider reads another provider that depends on it, even lazily.
    final container = ref.container;
    final client = ApiClient(
      config: config,
      logger: ref.watch(symphonyLoggerProvider).withTag('HTTP'),
      inspector:
          config.enableInspector ? ref.watch(apiInspectorProvider) : null,
      tokenDelegate: () => container.read(authTokenDelegateProvider),
      errorMapper: ref.watch(apiErrorMapperProvider),
      interceptors: ref.watch(apiInterceptorsProvider),
      headerProviders: ref.watch(apiHeaderProvidersProvider),
      httpClientAdapter: ref.watch(httpClientAdapterProvider),
    );
    ref.onDispose(client.close);
    return client;
  },
  name: 'apiClientProvider',
);
