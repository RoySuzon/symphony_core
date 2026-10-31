import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/adapters/auth_adapter.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/networking/presentation/networking_providers.dart';
import '../../features/storage/domain/key_value_storage.dart';
import '../../features/storage/domain/local_database.dart';
import '../../features/storage/presentation/storage_providers.dart';
import '../config/symphony_config.dart';
import '../error/error_reporter.dart';
import 'core_providers.dart';
// Required on Riverpod 3; redundant (but harmless) on Riverpod 2.
// ignore: unnecessary_import
import 'riverpod_compat.dart';

/// Builds the provider overrides that configure `symphony_core`.
///
/// `SymphonyCore.initialize` / `SymphonyCore.create` use it internally.
/// Applications that manage their own `ProviderScope` can use it directly:
///
/// ```dart
/// runApp(
///   ProviderScope(
///     overrides: symphonyOverrides(
///       config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
///       authAdapter: MyAuthAdapter(),
///     ),
///     child: const MyApp(),
///   ),
/// );
/// ```
///
/// The returned list contains, in this order:
/// * `symphonyConfigProvider` ← [config];
/// * when an adapter is given ([authAdapter] or [authAdapterBuilder]):
///   `authAdapterProvider` ← the adapter, and `authTokenDelegateProvider` ←
///   `sessionTokenDelegateProvider`, so the central `ApiClient` attaches and
///   refreshes the session tokens;
/// * `secureStorageProvider` ← [secureStorage], when given (for example an
///   `InMemoryKeyValueStorage` in tests);
/// * `localDatabaseProvider` ← [localDatabase], when given;
/// * `errorReporterProvider` ← [errorReporter], when given;
/// * the application's own [overrides], last.
///
/// [localDatabase] is provided as a value: the application owns it, opens it
/// if needed and closes it (disposing the container does **not** close it).
/// To let the container create and close the database, override
/// `localDatabaseProvider` with `overrideWith` in [overrides] instead:
///
/// ```dart
/// final database = MyHiveDatabase();
/// await database.open();
/// final overrides = symphonyOverrides(config: config, localDatabase: database);
/// // ... later, when the application shuts down:
/// await database.close();
/// ```
///
/// [authAdapterBuilder] creates the adapter from the container, for adapters
/// that depend on other providers (such as the `ApiClient`):
///
/// ```dart
/// authAdapterBuilder: (ref) => MyAuthAdapter(ref.watch(apiClientProvider)),
/// ```
///
/// Pass at most one of [authAdapter] and [authAdapterBuilder] (an
/// [ArgumentError] is thrown otherwise). When the adapter is provided
/// through [overrides] instead, the token delegate is not wired
/// automatically: override `authTokenDelegateProvider` as well.
///
/// ## Overriding a built-in provider
///
/// An override in [overrides] always wins over the built-in override of the
/// same provider:
/// * Riverpod 3 rejects two overrides of the same provider in one container
///   (an `AssertionError` in debug builds). Overrides expose the provider
///   they replace there, so the built-in override of every provider that
///   [overrides] already overrides is left out of the result.
/// * Riverpod 2 does not expose the provider an override replaces, so both
///   overrides are kept. Riverpod 2 applies overrides in order and the last
///   one — the application's — wins. A `ProviderScope` that is rebuilt with
///   such a list may however assert in debug builds when both overrides are
///   of a different kind (`overrideWith` vs `overrideWithValue`).
///
/// Prefer the named parameters over overriding these providers yourself.
List<Override> symphonyOverrides({
  required SymphonyConfig config,
  AuthAdapter? authAdapter,
  AuthAdapter Function(Ref ref)? authAdapterBuilder,
  KeyValueStorage? secureStorage,
  ErrorReporter? errorReporter,
  List<Override> overrides = const <Override>[],
  LocalDatabase? localDatabase,
}) {
  if (authAdapter != null && authAdapterBuilder != null) {
    throw ArgumentError(
      'Pass either authAdapter or authAdapterBuilder to symphonyOverrides, '
      'not both.',
    );
  }
  final hasAuth = authAdapter != null || authAdapterBuilder != null;
  final builtIn = <(Object, Override)>[
    (symphonyConfigProvider, symphonyConfigProvider.overrideWithValue(config)),
    if (authAdapter != null)
      (authAdapterProvider, authAdapterProvider.overrideWithValue(authAdapter)),
    if (authAdapterBuilder != null)
      (
        authAdapterProvider,
        authAdapterProvider.overrideWith(authAdapterBuilder)
      ),
    if (hasAuth)
      (
        authTokenDelegateProvider,
        authTokenDelegateProvider.overrideWith(
          (ref) => ref.watch(sessionTokenDelegateProvider),
        ),
      ),
    if (secureStorage != null)
      (
        secureStorageProvider,
        secureStorageProvider.overrideWithValue(secureStorage),
      ),
    if (localDatabase != null)
      (
        localDatabaseProvider,
        localDatabaseProvider.overrideWithValue(localDatabase),
      ),
    if (errorReporter != null)
      (
        errorReporterProvider,
        errorReporterProvider.overrideWithValue(errorReporter),
      ),
  ];

  final overridden = _overriddenTargets(overrides);
  return <Override>[
    for (final (provider, override) in builtIn)
      if (!overridden.contains(provider)) override,
    ...overrides,
  ];
}

/// The providers (or families) targeted by [overrides], as far as the
/// installed Riverpod version exposes them.
Set<Object> _overriddenTargets(List<Override> overrides) {
  final targets = Set<Object>.identity();
  for (final override in overrides) {
    // Riverpod 3 accepts a provider itself as an override (scoping).
    targets.add(override);
    final target = _overriddenProvider(override);
    if (target != null) targets.add(target);
  }
  return targets;
}

/// Returns the provider replaced by [override], or `null` when it is not
/// observable.
///
/// Riverpod 3 overrides expose it as `origin`; Riverpod 2 keeps it private.
/// The member is read dynamically because it does not exist (statically) on
/// every supported version.
Object? _overriddenProvider(Override override) {
  try {
    final dynamic untyped = override;
    final Object? origin = untyped.origin;
    return origin;
  } on Object {
    return null;
  }
}
