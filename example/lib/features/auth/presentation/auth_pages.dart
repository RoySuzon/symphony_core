import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/backend/demo_database.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/widgets/app_widgets.dart';

/// Start-up screen shown while the persisted session is restored.
///
/// [SymphonySplashScreen] runs the app's start-up tasks ([onInitialize]),
/// then restores the session, and shows an error view with a retry button
/// if a task fails. It never navigates: the router leaves the splash as
/// soon as the authentication status is known.
class SplashPage extends StatelessWidget {
  /// Creates the page.
  const SplashPage({super.key, this.onInitialize});

  /// Start-up tasks run before the session is restored.
  final Future<void> Function(WidgetRef ref)? onInitialize;

  @override
  Widget build(BuildContext context) {
    return SymphonySplashScreen(
      logo: const AppLogo(size: 96),
      subtitle: 'Reusable application core for Flutter',
      loadingMessage: 'Restoring your session…',
      onInitialize: onInitialize,
      errorTitle: 'Unable to reach the server',
    );
  }
}

/// A demo account listed on the login screen.
class DemoAccountInfo {
  /// Creates an entry.
  const DemoAccountInfo(this.email, this.title, this.description, this.icon);

  /// Sign-in e-mail.
  final String email;

  /// Short title.
  final String title;

  /// What the account can do.
  final String description;

  /// Icon.
  final IconData icon;
}

/// The demo accounts (password [demoPassword]).
const List<DemoAccountInfo> demoAccounts = <DemoAccountInfo>[
  DemoAccountInfo(
    'admin@example.com',
    'Admin',
    'Role admin · every permission',
    Icons.admin_panel_settings_outlined,
  ),
  DemoAccountInfo(
    'staff@example.com',
    'Staff',
    'Role staff · orders.read',
    Icons.support_agent_outlined,
  ),
  DemoAccountInfo(
    'viewer@example.com',
    'Viewer',
    'No permission',
    Icons.visibility_outlined,
  ),
  DemoAccountInfo(
    'unverified@example.com',
    'Unverified',
    'Rejected by a sessionValidator rule',
    Icons.mark_email_unread_outlined,
  ),
];

/// Sign-in screen: [SymphonyLoginScreen] + [SymphonyLoginForm], with the
/// demo accounts as one-tap sign-in shortcuts.
class LoginPage extends StatelessWidget {
  /// Creates the page.
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SymphonyLoginScreen(
      logo: const AppLogo(),
      title: 'Welcome back',
      subtitle: 'Sign in to the symphony_core demo',
      header: const SessionExpiredBanner(),
      form: SymphonyLoginForm(
        onForgotPassword: () => context.go(AppRoutes.forgotPassword),
        onRegister: () => context.go(AppRoutes.register),
      ),
      footer: const DemoAccountsCard(),
    );
  }
}

/// Explains why the user was signed out (`AuthUnauthenticated.failure`):
/// an expired or revoked session, or a session that could not be restored.
class SessionExpiredBanner extends ConsumerWidget {
  /// Creates the banner.
  const SessionExpiredBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final failure = state is AuthUnauthenticated ? state.failure : null;
    if (failure == null) return const SizedBox.shrink();
    final expired = failure is UnauthorizedFailure;
    return Padding(
      padding: const EdgeInsets.only(bottom: SymphonySpacing.lg),
      child: SymphonyErrorView(
        failure: failure,
        title: expired ? 'Your session has expired' : 'You were signed out',
        message: expired ? 'Please sign in again.' : failure.message,
        compact: true,
      ),
    );
  }
}

/// Lists the demo accounts; tapping one signs in with it.
class DemoAccountsCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const DemoAccountsCard({super.key});

  /// Key of the quick sign-in tile of [email] (widget tests).
  static Key tileKey(String email) => ValueKey<String>('demo-account:$email');

  @override
  ConsumerState<DemoAccountsCard> createState() => _DemoAccountsCardState();
}

class _DemoAccountsCardState extends ConsumerState<DemoAccountsCard> {
  String? _signingIn;

  Future<void> _signIn(DemoAccountInfo account) async {
    setState(() => _signingIn = account.email);
    final result = await ref
        .read(authControllerProvider.notifier)
        .login(
          AuthCredentials.emailPassword(
            email: account.email,
            password: demoPassword,
          ),
        );
    if (!mounted) return;
    setState(() => _signingIn = null);
    // On success the router leaves the login screen by itself.
    if (result case ResultFailure<AuthSession>(:final failure)) {
      SymphonySnackbar.showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: SymphonySpacing.xl),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SymphonySpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Demo accounts', style: theme.textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Password for every account: $demoPassword — or tap an '
                  'account to sign in directly.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              for (final account in demoAccounts)
                ListTile(
                  key: DemoAccountsCard.tileKey(account.email),
                  enabled: _signingIn == null,
                  leading: Icon(account.icon),
                  title: Text('${account.title} · ${account.email}'),
                  subtitle: Text(account.description),
                  trailing:
                      _signingIn == account.email
                          ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.login),
                  onTap: () => _signIn(account),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Registration screen ([SymphonyRegisterForm]); the demo backend signs the
/// new user in immediately (role viewer, no permission).
class RegisterPage extends StatelessWidget {
  /// Creates the page.
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SymphonyAuthLayout(
      logo: const AppLogo(size: 56),
      title: 'Create your account',
      subtitle: 'New accounts get the viewer role.',
      child: SymphonyRegisterForm(onSignIn: () => context.go(AppRoutes.login)),
    );
  }
}

/// Password recovery ([SymphonyForgotPasswordForm] with its confirmation
/// step: code + new password).
class ForgotPasswordPage extends StatelessWidget {
  /// Creates the page.
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SymphonyAuthLayout(
      logo: const AppLogo(size: 56),
      title: 'Reset your password',
      footer: const Padding(
        padding: EdgeInsets.only(top: SymphonySpacing.lg),
        child: Text(
          'Demo backend: the verification code is always $demoResetCode.',
          textAlign: TextAlign.center,
        ),
      ),
      child: SymphonyForgotPasswordForm(
        enableConfirmStep: true,
        onBackToSignIn: () => context.go(AppRoutes.login),
        onCompleted: () {
          SymphonySnackbar.success(
            context,
            'Password updated. You can now sign in.',
          );
          context.go(AppRoutes.login);
        },
      ),
    );
  }
}
