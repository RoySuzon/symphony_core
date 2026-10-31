import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  group('SymphonyConfig', () {
    test('only requires a base URL and has sensible defaults', () {
      const config = SymphonyConfig(baseUrl: 'https://api.example.com');

      expect(config.baseUrl, 'https://api.example.com');
      expect(config.appName, 'Symphony App');
      expect(config.environment, AppEnvironment.development);
      expect(config.enableInspector, isFalse);
      expect(config.enableLogging, isFalse);
      expect(config.logLevel, LogLevel.debug);
      expect(config.logRequestBodies, isTrue);
      expect(config.logResponseBodies, isTrue);
      expect(config.connectTimeout, const Duration(seconds: 30));
      expect(config.receiveTimeout, const Duration(seconds: 30));
      expect(config.sendTimeout, const Duration(seconds: 30));
      expect(config.defaultHeaders, isEmpty);
      expect(config.authHeaderName, 'Authorization');
      expect(config.authTokenPrefix, 'Bearer');
      expect(config.refreshTokenStatusCodes, <int>{401});
      expect(config.maxRetries, 0);
      expect(config.retryDelay, const Duration(milliseconds: 500));
      expect(config.retryStatusCodes, <int>{408, 429, 502, 503, 504});
      expect(config.inspectorMaxEntries, 200);
      expect(config.maxLoggedBodyLength, 4000);
      expect(config.sensitiveKeys, LogRedactor.defaultSensitiveKeys);
      expect(config.handleGlobalErrors, isTrue);
      expect(config.extras, isEmpty);
    });

    test('supports the documented non-const constructor call', () {
      // Written exactly like the README / doc example.
      // ignore: prefer_const_constructors
      final config = SymphonyConfig(
        baseUrl: 'https://api.example.com',
        enableInspector: true,
        enableLogging: true,
        // ignore: prefer_const_constructors
        connectTimeout: Duration(seconds: 30),
      );

      expect(config.enableInspector, isTrue);
      expect(config.enableLogging, isTrue);
      expect(config.connectTimeout, const Duration(seconds: 30));
    });

    test('copyWith replaces every given field', () {
      const original = SymphonyConfig(baseUrl: 'https://a.example.com');
      final copy = original.copyWith(
        baseUrl: 'https://b.example.com',
        appName: 'Other',
        environment: AppEnvironment.production,
        enableInspector: true,
        enableLogging: true,
        logLevel: LogLevel.warning,
        logRequestBodies: false,
        logResponseBodies: false,
        connectTimeout: const Duration(seconds: 1),
        receiveTimeout: const Duration(seconds: 2),
        sendTimeout: const Duration(seconds: 3),
        defaultHeaders: const <String, String>{'Accept-Language': 'fr'},
        authHeaderName: 'X-Auth',
        authTokenPrefix: '',
        refreshTokenStatusCodes: const <int>{401, 419},
        maxRetries: 3,
        retryDelay: const Duration(seconds: 1),
        retryStatusCodes: const <int>{503},
        inspectorMaxEntries: 10,
        maxLoggedBodyLength: 100,
        sensitiveKeys: const <String>{'pin'},
        handleGlobalErrors: false,
        extras: const <String, Object?>{'flag': true},
      );

      expect(copy.baseUrl, 'https://b.example.com');
      expect(copy.appName, 'Other');
      expect(copy.environment, AppEnvironment.production);
      expect(copy.enableInspector, isTrue);
      expect(copy.enableLogging, isTrue);
      expect(copy.logLevel, LogLevel.warning);
      expect(copy.logRequestBodies, isFalse);
      expect(copy.logResponseBodies, isFalse);
      expect(copy.connectTimeout, const Duration(seconds: 1));
      expect(copy.receiveTimeout, const Duration(seconds: 2));
      expect(copy.sendTimeout, const Duration(seconds: 3));
      expect(copy.defaultHeaders, <String, String>{'Accept-Language': 'fr'});
      expect(copy.authHeaderName, 'X-Auth');
      expect(copy.authTokenPrefix, isEmpty);
      expect(copy.refreshTokenStatusCodes, <int>{401, 419});
      expect(copy.maxRetries, 3);
      expect(copy.retryDelay, const Duration(seconds: 1));
      expect(copy.retryStatusCodes, <int>{503});
      expect(copy.inspectorMaxEntries, 10);
      expect(copy.maxLoggedBodyLength, 100);
      expect(copy.sensitiveKeys, <String>{'pin'});
      expect(copy.handleGlobalErrors, isFalse);
      expect(copy.extras, <String, Object?>{'flag': true});
    });

    test('copyWith without arguments keeps every value', () {
      const original = SymphonyConfig(
        baseUrl: 'https://a.example.com',
        appName: 'Keep me',
        maxRetries: 2,
        extras: <String, Object?>{'tenant': 'acme'},
      );
      final copy = original.copyWith();

      expect(copy.baseUrl, original.baseUrl);
      expect(copy.appName, original.appName);
      expect(copy.maxRetries, original.maxRetries);
      expect(copy.extras, original.extras);
      expect(copy.sensitiveKeys, original.sensitiveKeys);
    });

    test('extra<T> returns typed values and null for missing or mistyped', () {
      const config = SymphonyConfig(
        baseUrl: 'https://api.example.com',
        extras: <String, Object?>{'flag': true, 'count': 3, 'nothing': null},
      );

      expect(config.extra<bool>('flag'), isTrue);
      expect(config.extra<int>('count'), 3);
      expect(config.extra<String>('flag'), isNull);
      expect(config.extra<int>('missing'), isNull);
      expect(config.extra<Object>('nothing'), isNull);
    });

    test('redactor uses the configured sensitive keys', () {
      const config = SymphonyConfig(
        baseUrl: 'https://api.example.com',
        sensitiveKeys: <String>{'pin', 'X-Tenant-Secret'},
      );

      final redactor = config.redactor;
      expect(redactor.sensitiveKeys, config.sensitiveKeys);
      expect(redactor.isSensitive('user_pin'), isTrue);
      expect(redactor.isSensitive('x_tenant_secret'), isTrue);
      expect(redactor.isSensitive('Authorization'), isFalse);
    });

    test('rejects invalid numeric settings in debug builds', () {
      // Runtime values: a constant invocation would fail at compile time.
      final negative = int.parse('-1');
      final zero = int.parse('0');

      expect(
        () => SymphonyConfig(baseUrl: 'x', maxRetries: negative),
        throwsAssertionError,
      );
      expect(
        () => SymphonyConfig(baseUrl: 'x', inspectorMaxEntries: zero),
        throwsAssertionError,
      );
      expect(
        () => SymphonyConfig(baseUrl: 'x', maxLoggedBodyLength: zero),
        throwsAssertionError,
      );
    });

    test('toString describes the configuration', () {
      const config = SymphonyConfig(
        baseUrl: 'https://api.example.com',
        appName: 'Shop',
        environment: AppEnvironment.staging,
      );

      expect(
        config.toString(),
        allOf(
          contains('Shop'),
          contains('staging'),
          contains('https://api.example.com'),
        ),
      );
    });
  });

  group('AppEnvironment', () {
    test('predefined environments', () {
      expect(AppEnvironment.development.name, 'development');
      expect(AppEnvironment.development.isProduction, isFalse);
      expect(AppEnvironment.staging.name, 'staging');
      expect(AppEnvironment.staging.isProduction, isFalse);
      expect(AppEnvironment.production.name, 'production');
      expect(AppEnvironment.production.isProduction, isTrue);
    });

    test('custom environments compare by value', () {
      const qa = AppEnvironment('qa');
      final runtimeName = <String>['q', 'a'].join();
      final qaAgain = AppEnvironment(runtimeName);

      expect(qa, qaAgain);
      expect(qa.hashCode, qaAgain.hashCode);
      expect(qa, isNot(const AppEnvironment('qa', isProduction: true)));
      expect(qa, isNot(AppEnvironment.development));
      expect(qa.toString(), 'AppEnvironment(qa)');
    });
  });
}
