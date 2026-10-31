import 'package:dio/dio.dart';

import '../../../../core/logging/symphony_logger.dart';
import '../api_client.dart';
import 'interceptor_support.dart';

/// Adds dynamic headers (locale, app version, tenant...) produced by
/// [HeaderProvider]s to every request.
///
/// Providers run in order for each request; when several providers return
/// the same header, the last one wins. Header precedence is:
///
/// 1. headers passed for a single request (`ApiRequestOptions.headers`),
/// 2. headers returned by the providers,
/// 3. default headers (`SymphonyConfig.defaultHeaders`,
///    `ApiClient.setHeader`) and headers set by earlier interceptors.
///
/// A provider that throws is logged (without its error message, which may
/// contain sensitive data) and skipped: it never fails the request.
class HeadersInterceptor extends Interceptor {
  /// Creates an interceptor applying [providers].
  HeadersInterceptor(
    Iterable<HeaderProvider> providers, {
    SymphonyLogger? logger,
  }) : _providers = List<HeaderProvider>.of(providers),
       _logger = logger ?? SymphonyLogger.disabled();

  final List<HeaderProvider> _providers;
  final SymphonyLogger _logger;

  /// The providers currently applied, in evaluation order.
  List<HeaderProvider> get providers =>
      List<HeaderProvider>.unmodifiable(_providers);

  /// Appends [provider]; it runs after the existing providers.
  void addProvider(HeaderProvider provider) => _providers.add(provider);

  /// Removes [provider]. Returns whether it was registered.
  bool removeProvider(HeaderProvider provider) => _providers.remove(provider);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_providers.isNotEmpty) {
      final protectedNames = requestHeaderNames(options.extra);
      // Iterate over a snapshot: providers may be added or removed while an
      // asynchronous provider is pending.
      final providers = List<HeaderProvider>.of(_providers);
      for (var index = 0; index < providers.length; index++) {
        final headers = await _resolve(providers[index], index);
        if (headers == null) continue;
        headers.forEach((name, value) {
          if (!protectedNames.contains(name.toLowerCase())) {
            options.headers[name] = value;
          }
        });
      }
    }
    handler.next(options);
  }

  Future<Map<String, String>?> _resolve(
    HeaderProvider provider,
    int index,
  ) async {
    try {
      return await provider();
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Header provider #$index failed (${error.runtimeType}); '
        'its headers were skipped.',
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
