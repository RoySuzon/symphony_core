import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/error/error_reporter.dart';
import '../../../../core/error/failure.dart';
import '../../../../ui/widgets/feedback/symphony_error_view.dart';
import '../../../../ui/widgets/feedback/symphony_loading_indicator.dart';
import '../../domain/auth_state.dart';
import '../providers/auth_providers.dart';

/// Builds a fully custom splash body. [error] is the error thrown by
/// `SymphonySplashScreen.onInitialize` (or `null` while starting) and
/// [retry] restarts the start-up sequence.
typedef SymphonySplashBuilder =
    Widget Function(BuildContext context, Object? error, VoidCallback retry);

/// Start-up screen: runs the application's initialization tasks, restores
/// the persisted session and stays visible for at least
/// [minDisplayDuration].
///
/// After the first frame it runs [onInitialize] (for example loading remote
/// configuration or changing the base URL), then
/// `AuthController.restoreSession`, and waits for both these tasks and the
/// minimum display duration. It never navigates by itself:
///
/// * with `GoRouter` redirects, the router reacts to the authentication
///   state (unknown → authenticated / unauthenticated);
/// * without them, use [onCompleted] to navigate.
///
/// When [onInitialize] throws, an error view with a retry button is shown
/// and the error is forwarded to the configured `ErrorReporter` (also when
/// the screen was removed meanwhile, for example by a router redirect).
///
/// ```dart
/// SymphonySplashScreen(
///   logo: Image.asset('assets/logo.png', width: 96),
///   onInitialize: (ref) => ref.read(remoteConfigProvider.future),
///   onCompleted: (state) => Navigator.of(context).pushReplacementNamed(
///     state.isAuthenticated ? '/home' : '/login',
///   ),
/// );
/// ```
class SymphonySplashScreen extends ConsumerStatefulWidget {
  /// Creates a splash screen.
  const SymphonySplashScreen({
    super.key,
    this.logo,
    this.title,
    this.subtitle,
    this.backgroundColor,
    this.loadingMessage,
    this.showProgressIndicator = true,
    this.builder,
    this.minDisplayDuration = const Duration(milliseconds: 600),
    this.onInitialize,
    this.restoreAuthSession = true,
    this.onCompleted,
    this.errorTitle = 'Unable to start the application',
    this.errorMessage,
    this.retryLabel = 'Try again',
  });

  /// Widget displayed at the top (an image, an icon...).
  final Widget? logo;

  /// Headline. Defaults to `SymphonyConfig.appName` when a configuration is
  /// available. Pass an empty string to hide it.
  final String? title;

  /// Text below the [title].
  final String? subtitle;

  /// Background color. Defaults to the theme's surface color.
  final Color? backgroundColor;

  /// Text displayed below the progress indicator.
  final String? loadingMessage;

  /// Whether a progress indicator is displayed.
  final bool showProgressIndicator;

  /// Replaces the default body (logo, title, progress or error view).
  final SymphonySplashBuilder? builder;

  /// Minimum time the splash screen stays visible (avoids a flash on fast
  /// devices).
  final Duration minDisplayDuration;

  /// Application start-up tasks, run before the session is restored. Throw
  /// to show the error view.
  final Future<void> Function(WidgetRef ref)? onInitialize;

  /// Whether the persisted session is restored. Disable it for applications
  /// without authentication.
  final bool restoreAuthSession;

  /// Called with the authentication state once start-up finished (for
  /// applications without router redirects).
  final ValueChanged<AuthState>? onCompleted;

  /// Title of the error view.
  final String errorTitle;

  /// Message of the error view. Defaults to the failure message when
  /// [onInitialize] threw a `Failure`.
  final String? errorMessage;

  /// Label of the retry button of the error view.
  final String retryLabel;

  @override
  ConsumerState<SymphonySplashScreen> createState() =>
      _SymphonySplashScreenState();
}

class _SymphonySplashScreenState extends ConsumerState<SymphonySplashScreen> {
  Object? _error;
  bool _running = false;
  Timer? _minimumTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    super.dispose();
  }

  void _retry() => unawaited(_start());

  Future<void> _start() async {
    if (_running || !mounted) return;
    _running = true;
    if (_error != null) setState(() => _error = null);
    // Resolved up front: `ref` is unusable once this screen is disposed, and
    // a start-up failure must be reported even then (a router redirect can
    // remove the splash screen before `onInitialize` completes).
    final reporter = _errorReporter();

    final minimum = Completer<void>();
    _minimumTimer?.cancel();
    _minimumTimer = Timer(widget.minDisplayDuration, minimum.complete);

    Object? error;
    StackTrace? stackTrace;
    try {
      final initialize = widget.onInitialize;
      if (initialize != null) await initialize(ref);
      if (mounted && widget.restoreAuthSession) {
        await ref.read(authControllerProvider.notifier).restoreSession();
      }
    } on Object catch (e, s) {
      error = e;
      stackTrace = s;
    }
    if (error != null) _report(reporter, error, stackTrace);
    if (!mounted) return;
    await minimum.future;
    _running = false;
    if (!mounted) return;

    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.onCompleted?.call(ref.read(authControllerProvider));
  }

  ErrorReporter? _errorReporter() {
    try {
      return ref.read(errorReporterProvider);
    } on Object {
      // Reporting is best effort (the configuration may be missing).
      return null;
    }
  }

  void _report(ErrorReporter? reporter, Object error, StackTrace? stackTrace) {
    if (reporter == null) return;
    try {
      final pending = reporter.report(
        error,
        stackTrace,
        reason: 'Application start-up failed',
      );
      if (pending is Future<void>) {
        unawaited(pending.then<void>((_) {}, onError: (Object error) {}));
      }
    } on Object {
      // Reporters must never throw; ignore misbehaving ones.
    }
  }

  String? _title() {
    final title = widget.title;
    if (title != null) return title.isEmpty ? null : title;
    try {
      return ref.watch(symphonyConfigProvider.select((c) => c.appName));
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final builder = widget.builder;
    final Widget body;
    if (builder != null) {
      body = builder(context, error, _retry);
    } else if (error != null) {
      body = SymphonyErrorView(
        failure: error is Failure ? error : null,
        title: widget.errorTitle,
        message: widget.errorMessage,
        onRetry: _retry,
        retryLabel: widget.retryLabel,
      );
    } else {
      body = _SplashBody(
        logo: widget.logo,
        title: _title(),
        subtitle: widget.subtitle,
        loadingMessage: widget.loadingMessage,
        showProgressIndicator: widget.showProgressIndicator,
      );
    }
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? theme.colorScheme.surface,
      body: SafeArea(child: body),
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody({
    required this.logo,
    required this.title,
    required this.subtitle,
    required this.loadingMessage,
    required this.showProgressIndicator,
  });

  final Widget? logo;
  final String? title;
  final String? subtitle;
  final String? loadingMessage;
  final bool showProgressIndicator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = this.logo;
    final title = this.title;
    final subtitle = this.subtitle;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (logo != null) ...<Widget>[logo, const SizedBox(height: 24)],
            if (title != null)
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (showProgressIndicator) ...<Widget>[
              const SizedBox(height: 32),
              SymphonyLoadingIndicator(message: loadingMessage, size: 32),
            ],
          ],
        ),
      ),
    );
  }
}
