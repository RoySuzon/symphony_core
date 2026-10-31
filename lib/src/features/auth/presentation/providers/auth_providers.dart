import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/access/access_context.dart';
import '../../../../core/di/core_providers.dart';
import '../../../networking/domain/auth_token_delegate.dart';
import '../../../storage/presentation/storage_providers.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/session_token_delegate.dart';
import '../../domain/adapters/auth_adapter.dart';
import '../../domain/auth_state.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../controllers/auth_controller.dart';

/// The project's [AuthAdapter]. Must be provided by the application
/// (`SymphonyCore.initialize(authAdapter: ...)` or an override).
final authAdapterProvider = Provider<AuthAdapter>(
  (ref) =>
      throw StateError(
        'authAdapterProvider is not configured. Pass an AuthAdapter to '
        'SymphonyCore.initialize(authAdapter: ...) or override '
        'authAdapterProvider.',
      ),
  name: 'authAdapterProvider',
);

/// The [AuthRepository] combining the adapter and the session storage.
///
/// Defaults to an [AuthRepositoryImpl] built from [authAdapterProvider],
/// `sessionStorageProvider` and the shared logger (tag `Auth`). Override it
/// to tune the repository, for example its `expiryLeeway`.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    adapter: ref.watch(authAdapterProvider),
    storage: ref.watch(sessionStorageProvider),
    logger: ref.watch(symphonyLoggerProvider).withTag('Auth'),
  ),
  name: 'authRepositoryProvider',
);

/// Global authentication state and actions.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
  name: 'authControllerProvider',
);

/// Access snapshot (status, roles, permissions) of the current user. Drives
/// route guards and dashboard visibility.
final accessContextProvider = Provider<AccessContext>(
  (ref) => ref.watch(authControllerProvider).accessContext,
  name: 'accessContextProvider',
);

/// The signed-in user, if any.
final currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(authControllerProvider).user,
  name: 'currentUserProvider',
);

/// Whether a user is signed in.
final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).isAuthenticated,
  name: 'isAuthenticatedProvider',
);

/// [AuthTokenDelegate] backed by the current session. `SymphonyCore` installs
/// it as `authTokenDelegateProvider` so the `ApiClient` can attach and
/// refresh tokens.
///
/// The repository and the controller are resolved lazily (inside the
/// callbacks) so that `ApiClient → delegate → repository → adapter →
/// ApiClient` never forms a provider cycle.
final sessionTokenDelegateProvider = Provider<AuthTokenDelegate>(
  (ref) => SessionTokenDelegate(
    repository: () => ref.read(authRepositoryProvider),
    onSessionRefreshed:
        (session) =>
            ref.read(authControllerProvider.notifier).updateSession(session),
    onExpired:
        (failure) => ref
            .read(authControllerProvider.notifier)
            .handleSessionExpired(failure),
    logger: ref.watch(symphonyLoggerProvider).withTag('Auth'),
  ),
  name: 'sessionTokenDelegateProvider',
);
