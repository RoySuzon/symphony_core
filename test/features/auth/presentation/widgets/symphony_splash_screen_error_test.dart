import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/di/core_providers.dart';
import 'package:symphony_core/src/core/error/error_reporter.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';

import '../../support/auth_test_support.dart';

class RecordingErrorReporter extends ErrorReporter {
  final List<Object> errors = <Object>[];
  final List<String?> reasons = <String?>[];

  @override
  void report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    errors.add(error);
    reasons.add(reason);
  }
}

/// Regression tests: start-up failures are never lost.
void main() {
  testWidgets(
    'an onInitialize failure is reported even when the splash screen was '
    'removed meanwhile (for example by a router redirect)',
    (tester) async {
      final reporter = RecordingErrorReporter();
      final container = createAuthContainer(
        adapter: InMemoryAuthAdapter(accounts: demoAccounts),
        overrides: <Object>[errorReporterProvider.overrideWithValue(reporter)],
      );
      final initialization = Completer<void>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SymphonySplashScreen(
              minDisplayDuration: Duration.zero,
              onInitialize: (ref) => initialization.future,
            ),
          ),
        ),
      );
      await tester.pump();

      // The application navigated away before the start-up tasks completed.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Text('Home')),
        ),
      );
      initialization.completeError(const NetworkFailure('Config unreachable'));
      await tester.pump();
      await tester.pump();

      expect(reporter.errors, <Object>[
        const NetworkFailure('Config unreachable'),
      ]);
      expect(reporter.reasons, <String?>['Application start-up failed']);
    },
  );
}
