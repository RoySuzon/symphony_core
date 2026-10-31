import 'dart:async';

import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/auth/domain/adapters/auth_adapter.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_credentials.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_session.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_tokens.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_user.dart';
import 'package:symphony_core/src/features/networking/domain/auth_token_delegate.dart';

/// A configuration used by most core tests.
const SymphonyConfig testConfig = SymphonyConfig(
  baseUrl: 'https://api.example.com',
  appName: 'Core Test App',
  handleGlobalErrors: false,
);

/// One call to [ErrorReporter.report].
class ReportedError {
  /// Creates a record.
  const ReportedError({
    required this.error,
    required this.stackTrace,
    required this.reason,
    required this.fatal,
    required this.context,
  });

  /// The reported error.
  final Object error;

  /// The reported stack trace.
  final StackTrace? stackTrace;

  /// The reported reason.
  final String? reason;

  /// Whether the error was reported as fatal.
  final bool fatal;

  /// Additional context.
  final Map<String, Object?> context;
}

/// Records every report.
class RecordingErrorReporter extends ErrorReporter {
  /// Received reports, oldest first.
  final List<ReportedError> reports = <ReportedError>[];

  /// Optional hook executed while reporting.
  void Function(Object error)? onReport;

  @override
  void report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    reports.add(
      ReportedError(
        error: error,
        stackTrace: stackTrace,
        reason: reason,
        fatal: fatal,
        context: context,
      ),
    );
    onReport?.call(error);
  }
}

/// Throws synchronously from [report].
class ThrowingErrorReporter extends ErrorReporter {
  /// Creates a throwing reporter.
  const ThrowingErrorReporter();

  @override
  void report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    throw StateError('reporter exploded');
  }
}

/// Returns a failed future from [report].
class AsyncFailingErrorReporter extends ErrorReporter {
  /// Creates an asynchronously failing reporter.
  const AsyncFailingErrorReporter();

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    await Future<void>.delayed(Duration.zero);
    throw StateError('async reporter exploded');
  }
}

/// Keeps every written entry.
class RecordingLogSink extends LogSink {
  /// Written entries, oldest first.
  final List<LogEntry> entries = <LogEntry>[];

  @override
  void write(LogEntry entry) => entries.add(entry);
}

/// Throws on every write.
class ThrowingLogSink extends LogSink {
  /// Creates a throwing sink.
  const ThrowingLogSink();

  @override
  void write(LogEntry entry) => throw StateError('sink exploded');
}

/// Minimal [AuthAdapter] that accepts every login.
class FakeAuthAdapter extends AuthAdapter {
  /// Creates a fake adapter.
  FakeAuthAdapter({this.user = const AuthUser(id: 'user-1')});

  /// User returned by [login].
  final AuthUser user;

  /// Number of [login] calls.
  int loginCalls = 0;

  /// Number of [validateSession] calls.
  int validateCalls = 0;

  @override
  Future<AuthSession> login(AuthCredentials credentials) async {
    loginCalls++;
    return AuthSession(
      tokens: const AuthTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      ),
      user: user,
    );
  }

  @override
  Future<void> validateSession(AuthSession session) async {
    validateCalls++;
  }
}

/// [AuthTokenDelegate] returning fixed values.
class FakeTokenDelegate extends AuthTokenDelegate {
  /// Creates a fake delegate.
  const FakeTokenDelegate();

  @override
  Future<String?> getAccessToken() async => 'fake-token';

  @override
  Future<String?> refreshAccessToken() async => null;

  @override
  Future<void> onSessionExpired() async {}
}

/// Lets pending microtasks and zero-duration timers run (real async only).
Future<void> flushAsync() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
