import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/domain/adapters/auth_adapter.dart';
import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import '../features/networking/data/api_client.dart';
import '../features/networking/presentation/networking_providers.dart';
import '../features/storage/domain/key_value_storage.dart';
import '../features/storage/domain/local_database.dart';
import 'config/symphony_config.dart';
import 'di/core_providers.dart';
// Required on Riverpod 3; redundant (but harmless) on Riverpod 2.
// ignore: unnecessary_import
import 'di/riverpod_compat.dart';
import 'di/symphony_overrides.dart';
import 'error/error_reporter.dart';
import 'error/global_error_handler.dart';
import 'error/safe_error_reporting.dart';
import 'logging/log_level.dart';
import 'logging/log_redactor.dart';
import 'logging/symphony_logger.dart';
import 'symphony_scope.dart';

/// Entry point of `symphony_core`.
///
/// A [SymphonyCore] owns the Riverpod [ProviderContainer] holding every
/// service of the package (configuration, logger, `ApiClient`, API
/// inspector, authentication, storage...) and, optionally, the global error
/// handlers.
///
/// ```dart
/// Future<void> main() async {
///   await SymphonyCore.initialize(
///     config: SymphonyConfig(
///       baseUrl: 'https://api.example.com',
///       enableInspector: true,
///       enableLogging: true,
///       connectTimeout: Duration(seconds: 30),
///     ),
///     authAdapter: MyAuthAdapter(),
///     restoreSession: true,
///   );
///   runApp(SymphonyCore.instance.wrap(const MyApp()));
/// }
/// ```
///
/// [initialize] registers the instance globally ([instance]); [create]
/// builds independent instances (tests, several instances side by side).
/// Widgets reach the services through [SymphonyScope] (see [wrap]) with the
/// usual Riverpod APIs (`ref.watch(apiClientProvider)`...). Code outside the
/// widget tree uses [read] or the shortcuts [apiClient], [logger] and
/// [auth].
class SymphonyCore {
  SymphonyCore._({
    required ProviderContainer container,
    required SymphonyConfig config,
    required bool? hasAuth,
  })  : _container = container,
        _config = config,
        _hasAuth = hasAuth;

  static SymphonyCore? _instance;

  static const String _tag = 'SymphonyCore';

  final ProviderContainer _container;
  final SymphonyConfig _config;

  /// Known at creation, except with a parent container (resolved lazily from
  /// the parent hierarchy, see [hasAuth]).
  bool? _hasAuth;
  GlobalErrorHandlerRegistration? _errorHandlers;
  bool _disposed = false;

  /// Creates the application-wide instance and registers it as [instance].
  ///
  /// Awaiting the returned future before `runApp` is recommended. The
  /// instance is nevertheless registered synchronously, before the first
  /// asynchronous step, so `SymphonyCore.instance` and [SymphonyScope] work
  /// even when the future is not awaited; only the optional session
  /// restoration then completes in the background.
  ///
  /// Steps:
  /// 1. Initializes the Flutter bindings.
  /// 2. Builds the container from [symphonyOverrides] ([config],
  ///    [authAdapter] or [authAdapterBuilder], [secureStorage],
  ///    [localDatabase], [errorReporter], then the application's
  ///    [overrides]) and resolves the services needed below (configuration,
  ///    logger and, when [SymphonyConfig.handleGlobalErrors] is `true`, the
  ///    error reporter). If anything fails up to here, the new container is
  ///    disposed, the error is thrown and the previous global instance is
  ///    kept unchanged.
  /// 3. Disposes the previous global instance, if any: calling [initialize]
  ///    again replaces it (widgets must be rebuilt with the new instance).
  /// 4. Installs the [GlobalErrorHandler] when
  ///    [SymphonyConfig.handleGlobalErrors] is `true`, reporting to
  ///    `errorReporterProvider`.
  /// 5. Registers the new instance as [instance].
  /// 6. When [restoreSession] is `true` and an auth adapter is configured,
  ///    awaits `AuthController.restoreSession()`. A failing restoration is
  ///    reported and logged; it does not fail the initialization.
  /// 7. Logs one summary line (no secrets) when logging is enabled.
  ///
  /// The `ApiClient` and the other services are created lazily, on first
  /// use.
  ///
  /// [localDatabase] replaces the default (volatile) `localDatabaseProvider`.
  /// The application owns that database: open it when needed and close it
  /// yourself, [dispose] does not close it.
  ///
  /// ## Parent container (advanced)
  ///
  /// [parent] creates the container as a child of an existing container
  /// whose hierarchy is **already configured** for this package (its root was
  /// created with [symphonyOverrides]); the providers of [parent] are then
  /// reachable through this instance. Riverpod resolves providers that do not
  /// declare `dependencies` — every provider of this package — in the root
  /// container of a hierarchy, and does not let a child container override
  /// their dependencies (Riverpod 2 asserts it in debug builds). Therefore,
  /// with a [parent]:
  /// * the configuration, auth adapter, storage, local database and error
  ///   reporter come from the parent hierarchy: [config] must be the
  ///   configuration it provides (the same instance) and [authAdapter],
  ///   [authAdapterBuilder], [secureStorage], [localDatabase] and
  ///   [errorReporter] must be `null` — an [ArgumentError] is thrown
  ///   otherwise;
  /// * only [overrides] are added to the new container: use them for
  ///   providers of the application that nothing in the parent depends on;
  /// * a [StateError] is thrown when the parent hierarchy cannot resolve
  ///   `symphonyConfigProvider`.
  ///
  /// Most applications do not need a parent: nest `ProviderScope`s below
  /// [SymphonyScope] instead.
  static Future<SymphonyCore> initialize({
    required SymphonyConfig config,
    AuthAdapter? authAdapter,
    AuthAdapter Function(Ref ref)? authAdapterBuilder,
    KeyValueStorage? secureStorage,
    ErrorReporter? errorReporter,
    List<Override> overrides = const <Override>[],
    bool restoreSession = false,
    ProviderContainer? parent,
    LocalDatabase? localDatabase,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    final previous = _instance;
    if (parent != null &&
        previous != null &&
        identical(parent, previous._container)) {
      throw ArgumentError.value(
        parent,
        'parent',
        'cannot be the container of the instance that initialize() replaces '
            '(it is disposed)',
      );
    }
    final core = _build(
      config: config,
      authAdapter: authAdapter,
      authAdapterBuilder: authAdapterBuilder,
      secureStorage: secureStorage,
      localDatabase: localDatabase,
      errorReporter: errorReporter,
      overrides: overrides,
      parent: parent,
    );
    // Resolved before the previous instance is disposed: a reporter that
    // cannot be created fails this call without losing the working instance.
    final ErrorReporter? reporter;
    try {
      reporter = core.config.handleGlobalErrors
          ? core._container.read(errorReporterProvider)
          : null;
    } on Object {
      core._disposeNow();
      rethrow;
    }
    previous?._disposeNow();
    if (reporter != null) core._installErrorHandlers(reporter);
    _instance = core;

    String? sessionStatus;
    if (restoreSession) {
      if (core.hasAuth) {
        sessionStatus = await core._restoreSessionSafely();
      } else {
        core.logger.warning(
          'restoreSession was requested but no auth adapter is configured; '
          'nothing to restore.',
          tag: _tag,
        );
      }
    }
    if (!core._disposed) core._logStartup(sessionStatus: sessionStatus);
    return core;
  }

  /// Creates an independent instance that is **not** registered as
  /// [instance].
  ///
  /// Useful in tests and for applications that need several isolated
  /// instances. The caller owns the instance and must [dispose] it.
  ///
  /// Unlike [initialize], [create] neither initializes the Flutter bindings
  /// nor restores the session (call `await core.auth.restoreSession()` when
  /// needed), and it installs the global error handlers only when
  /// [installErrorHandlers] is `true` ([SymphonyConfig.handleGlobalErrors] is
  /// ignored). See [initialize] for the other parameters.
  static SymphonyCore create({
    required SymphonyConfig config,
    AuthAdapter? authAdapter,
    AuthAdapter Function(Ref ref)? authAdapterBuilder,
    KeyValueStorage? secureStorage,
    ErrorReporter? errorReporter,
    List<Override> overrides = const <Override>[],
    ProviderContainer? parent,
    bool installErrorHandlers = false,
    LocalDatabase? localDatabase,
  }) {
    final core = _build(
      config: config,
      authAdapter: authAdapter,
      authAdapterBuilder: authAdapterBuilder,
      secureStorage: secureStorage,
      localDatabase: localDatabase,
      errorReporter: errorReporter,
      overrides: overrides,
      parent: parent,
    );
    if (installErrorHandlers) {
      try {
        core._installErrorHandlers(core._container.read(errorReporterProvider));
      } on Object {
        core._disposeNow();
        rethrow;
      }
    }
    return core;
  }

  /// The instance registered by [initialize].
  ///
  /// Throws a [StateError] when [initialize] has not been called (or the
  /// instance was disposed).
  static SymphonyCore get instance {
    final current = _instance;
    if (current == null) {
      throw StateError(
        'SymphonyCore is not initialized. Call '
        '`await SymphonyCore.initialize(config: ...)` in main() before '
        'runApp(), or pass an instance created with SymphonyCore.create(...) '
        'explicitly (for example SymphonyScope(core: core, child: ...)).',
      );
    }
    return current;
  }

  /// Whether a global instance is registered (see [initialize]).
  static bool get isInitialized => _instance != null;

  /// Disposes the global instance, if any, and clears the registration.
  ///
  /// Intended for tests (for example in `tearDown`).
  @visibleForTesting
  static Future<void> reset() async {
    _instance?._disposeNow();
    _instance = null;
  }

  /// The Riverpod container holding the services of this instance.
  ///
  /// Pass it to `UncontrolledProviderScope` (or use [wrap] / [SymphonyScope])
  /// to expose it to widgets.
  ProviderContainer get container => _container;

  /// The configuration of this instance, as resolved when it was created
  /// (an application override of `symphonyConfigProvider` included).
  SymphonyConfig get config => _config;

  /// Whether an auth adapter is configured, i.e. whether [auth] is available.
  ///
  /// `true` when `authAdapter` or `authAdapterBuilder` was given. With a
  /// parent container, it tells whether the parent hierarchy provides an
  /// adapter (resolving it on first access).
  bool get hasAuth => _hasAuth ??= _resolveAdapterFromHierarchy();

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Reads [provider] from [container].
  ///
  /// ```dart
  /// final user = SymphonyCore.instance.read(currentUserProvider);
  /// ```
  ///
  /// Throws a [StateError] once this instance is disposed.
  T read<T>(ProviderListenable<T> provider) {
    _ensureNotDisposed();
    return _container.read(provider);
  }

  /// The central `ApiClient` (created on first access).
  ApiClient get apiClient => read(apiClientProvider);

  /// The shared logger configured from [config].
  SymphonyLogger get logger => read(symphonyLoggerProvider);

  /// The authentication controller (login, logout, session restoration...).
  ///
  /// Throws a [StateError] when no auth adapter was configured (see
  /// [hasAuth]).
  AuthController get auth {
    _ensureNotDisposed();
    if (!hasAuth) {
      throw StateError(
        'No AuthAdapter is configured. Pass `authAdapter:` (or '
        '`authAdapterBuilder:`) to SymphonyCore.initialize / '
        'SymphonyCore.create to use authentication.',
      );
    }
    return read(authControllerProvider.notifier);
  }

  /// Wraps [app] in a [SymphonyScope] bound to this instance, so widgets
  /// below can use the providers of this package.
  ///
  /// ```dart
  /// runApp(SymphonyCore.instance.wrap(const MyApp()));
  /// ```
  Widget wrap(Widget app) {
    _ensureNotDisposed();
    return SymphonyScope(core: this, child: app);
  }

  /// Uninstalls the global error handlers installed by this instance,
  /// disposes [container] (and therefore every service) and, when this is
  /// the global instance, clears the registration. Calling it again does
  /// nothing.
  Future<void> dispose() async {
    _disposeNow();
  }

  @override
  String toString() => 'SymphonyCore(app: ${_config.appName}, '
      'environment: ${_config.environment.name}, '
      'auth: ${_hasAuth ?? 'from parent'}, disposed: $_disposed)';

  static SymphonyCore _build({
    required SymphonyConfig config,
    required AuthAdapter? authAdapter,
    required AuthAdapter Function(Ref ref)? authAdapterBuilder,
    required KeyValueStorage? secureStorage,
    required LocalDatabase? localDatabase,
    required ErrorReporter? errorReporter,
    required List<Override> overrides,
    required ProviderContainer? parent,
  }) {
    if (parent != null) {
      return _buildChild(
        parent: parent,
        config: config,
        configuredHere: authAdapter != null ||
            authAdapterBuilder != null ||
            secureStorage != null ||
            localDatabase != null ||
            errorReporter != null,
        overrides: overrides,
      );
    }
    final container = ProviderContainer(
      overrides: symphonyOverrides(
        config: config,
        authAdapter: authAdapter,
        authAdapterBuilder: authAdapterBuilder,
        secureStorage: secureStorage,
        localDatabase: localDatabase,
        errorReporter: errorReporter,
        overrides: overrides,
      ),
    );
    try {
      final resolvedConfig = container.read(symphonyConfigProvider);
      // Resolving the logger validates the application overrides early.
      container.read(symphonyLoggerProvider);
      return SymphonyCore._(
        container: container,
        config: resolvedConfig,
        hasAuth: authAdapter != null || authAdapterBuilder != null,
      );
    } on Object {
      container.dispose();
      rethrow;
    }
  }

  /// Builds an instance whose container is a child of [parent]; see
  /// "Parent container" in [initialize].
  static SymphonyCore _buildChild({
    required ProviderContainer parent,
    required SymphonyConfig config,
    required bool configuredHere,
    required List<Override> overrides,
  }) {
    if (configuredHere) {
      throw ArgumentError(
        'With a parent container, configure authAdapter, authAdapterBuilder, '
        'secureStorage, localDatabase and errorReporter in the parent '
        'hierarchy (with symphonyOverrides(...)) instead of passing them to '
        'SymphonyCore.',
      );
    }
    final SymphonyConfig parentConfig;
    try {
      parentConfig = parent.read(symphonyConfigProvider);
    } on Object catch (error, stackTrace) {
      // Riverpod 3 wraps provider errors in a ProviderException, Riverpod 2
      // rethrows them as they are: the hint does not depend on it.
      Error.throwWithStackTrace(
        StateError(
          'The parent container is not configured for symphony_core. Create '
          'the root of its hierarchy with '
          'ProviderContainer(overrides: symphonyOverrides(config: ...)). '
          'Original error: $error',
        ),
        stackTrace,
      );
    }
    if (!identical(parentConfig, config)) {
      throw ArgumentError.value(
        config,
        'config',
        'must be the SymphonyConfig instance provided by the parent hierarchy',
      );
    }
    final container = ProviderContainer(parent: parent, overrides: overrides);
    try {
      container.read(symphonyLoggerProvider);
      return SymphonyCore._(
        container: container,
        config: parentConfig,
        hasAuth: null,
      );
    } on Object {
      container.dispose();
      rethrow;
    }
  }

  bool _resolveAdapterFromHierarchy() {
    try {
      _container.read(authAdapterProvider);
      return true;
    } on Object {
      return false;
    }
  }

  void _installErrorHandlers(ErrorReporter reporter) {
    _errorHandlers = GlobalErrorHandler.install(
      reporter: reporter,
      logger: _container.read(symphonyLoggerProvider),
    );
  }

  /// Restores the session, returning the resulting status name (logged by
  /// [_logStartup]). Never throws.
  Future<String?> _restoreSessionSafely() async {
    try {
      await auth.restoreSession();
      if (_disposed) return null;
      return _container.read(authControllerProvider).status.name;
    } on Object catch (error, stackTrace) {
      // A superseded instance (initialize called again) stays silent.
      if (_disposed) return null;
      final logger = _container.read(symphonyLoggerProvider);
      logger.warning(
        'Session restoration failed',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
      final ErrorReporter reporter;
      try {
        reporter = _container.read(errorReporterProvider);
      } on Object catch (reporterError) {
        // A broken errorReporterProvider must not fail initialize().
        logger.warning(
          'The error reporter is unavailable; the restoration failure was '
          'not reported',
          tag: _tag,
          error: reporterError,
        );
        return 'restoration failed';
      }
      reportErrorSafely(
        reporter,
        error,
        stackTrace,
        reason: 'SymphonyCore.initialize: session restoration failed',
        context: const <String, Object?>{'phase': 'restoreSession'},
        logger: logger,
      );
      return 'restoration failed';
    }
  }

  void _logStartup({String? sessionStatus}) {
    final logger = _container.read(symphonyLoggerProvider);
    if (!logger.isEnabledFor(LogLevel.info)) return;
    final redactor = _container.read(logRedactorProvider);
    // Not resolved here when unknown: logging must not create the adapter.
    final auth = _hasAuth;
    final details = <String>[
      'environment: ${_config.environment.name}',
      'baseUrl: ${_describeUrl(_config.baseUrl, redactor)}',
      'inspector: ${_onOff(_config.enableInspector)}',
      'auth: ${auth == null ? 'from parent' : _onOff(auth)}',
      'global error handlers: ${_onOff(_errorHandlers != null)}',
      if (sessionStatus != null) 'session: $sessionStatus',
    ];
    logger.info(
      'Initialized "${_config.appName}" (${details.join(', ')})',
      tag: _tag,
    );
  }

  static String _onOff(bool value) => value ? 'on' : 'off';

  /// [url] without credentials: user info and sensitive query parameters are
  /// masked (see [LogRedactor.redactUri]).
  static String _describeUrl(String url, LogRedactor redactor) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '<invalid URL>';
    return redactor.redactUri(uri).toString();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'This SymphonyCore instance has been disposed. Use the instance '
        'returned by the latest SymphonyCore.initialize / create call.',
      );
    }
  }

  void _disposeNow() {
    if (_disposed) return;
    _disposed = true;
    if (identical(_instance, this)) _instance = null;
    _errorHandlers?.uninstall();
    _errorHandlers = null;
    _container.dispose();
  }
}
