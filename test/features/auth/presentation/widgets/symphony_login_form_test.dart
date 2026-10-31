import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/ui/widgets/buttons/symphony_button.dart';

import '../../support/auth_test_support.dart';

void main() {
  setUpAll(registerAuthFallbacks);

  Finder identifierInput() => find.byKey(SymphonyLoginForm.identifierInputKey);
  Finder passwordInput() => find.byKey(SymphonyLoginForm.passwordInputKey);
  Finder submitButton() => find.byKey(SymphonyLoginForm.submitButtonKey);

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String email = 'admin@example.com',
    String password = 'secret123',
  }) async {
    await tester.enterText(identifierInput(), email);
    await tester.enterText(passwordInput(), password);
    await tester.tap(submitButton());
  }

  group('with the in-memory backend', () {
    late InMemoryAuthAdapter adapter;

    setUp(() {
      adapter = InMemoryAuthAdapter(accounts: demoAccounts);
    });

    testWidgets('validates the inputs before submitting', (tester) async {
      final container = createAuthContainer(adapter: adapter);
      await pumpAuthWidget(tester, container, const SymphonyLoginForm());

      await tester.tap(submitButton());
      await tester.pump();

      expect(find.text('This field is required.'), findsNWidgets(2));

      await tester.enterText(identifierInput(), 'not-an-email');
      await tester.pump();

      expect(find.text('Enter a valid e-mail address.'), findsOneWidget);
      expect(container.read(authControllerProvider), isA<AuthUnknown>());
    });

    testWidgets('signs in and reports the session', (tester) async {
      final container = createAuthContainer(adapter: adapter);
      AuthSession? signedIn;
      await pumpAuthWidget(
        tester,
        container,
        SymphonyLoginForm(onSuccess: (session) => signedIn = session),
      );

      await fillAndSubmit(tester);
      await tester.pumpAndSettle();

      expect(signedIn?.user, adminUser);
      final state = container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect(state.user, adminUser);
    });

    testWidgets('shows the failure message', (tester) async {
      final container = createAuthContainer(adapter: adapter);
      Failure? reported;
      await pumpAuthWidget(
        tester,
        container,
        SymphonyLoginForm(onFailure: (failure) => reported = failure),
      );

      await fillAndSubmit(tester, password: 'wrong-password');
      await tester.pumpAndSettle();

      expect(find.text('Invalid e-mail or password.'), findsOneWidget);
      expect(reported, isA<AuthFailure>());
      expect(container.read(authControllerProvider).isAuthenticated, isFalse);
    });

    testWidgets('localizes failures with failureMessageBuilder',
        (tester) async {
      final container = createAuthContainer(adapter: adapter);
      await pumpAuthWidget(
        tester,
        container,
        SymphonyLoginForm(
          failureMessageBuilder: (failure) => 'Identifiants invalides',
        ),
      );

      await fillAndSubmit(tester, password: 'wrong-password');
      await tester.pumpAndSettle();

      expect(find.text('Identifiants invalides'), findsOneWidget);
    });

    testWidgets('shows the recovery and registration links when supported',
        (tester) async {
      final container = createAuthContainer(adapter: adapter);
      var forgotTaps = 0;
      var registerTaps = 0;
      await pumpAuthWidget(
        tester,
        container,
        SymphonyLoginForm(
          onForgotPassword: () => forgotTaps++,
          onRegister: () => registerTaps++,
        ),
      );

      await tester.tap(find.text('Forgot password?'));
      await tester.tap(find.text('Create one'));

      expect(forgotTaps, 1);
      expect(registerTaps, 1);
    });

    testWidgets('hides the links without callbacks', (tester) async {
      final container = createAuthContainer(adapter: adapter);
      await pumpAuthWidget(tester, container, const SymphonyLoginForm());

      expect(find.text('Forgot password?'), findsNothing);
      expect(find.text('Create one'), findsNothing);
    });

    testWidgets('hides the links when the adapter does not support them',
        (tester) async {
      final container = createAuthContainer(
        adapter: InMemoryAuthAdapter(
          accounts: demoAccounts,
          registrationEnabled: false,
          passwordRecoveryEnabled: false,
        ),
      );
      await pumpAuthWidget(
        tester,
        container,
        SymphonyLoginForm(onForgotPassword: () {}, onRegister: () {}),
      );

      expect(find.text('Forgot password?'), findsNothing);
      expect(find.text('Create one'), findsNothing);
    });

    testWidgets('supports username sign-in with custom texts',
        (tester) async {
      final container = createAuthContainer(
        adapter: InMemoryAuthAdapter(
          identifierField: 'username',
          accounts: const <InMemoryAccount>[
            InMemoryAccount(
              identifier: 'grace',
              password: 'cobol1959',
              user: plainUser,
            ),
          ],
        ),
      );
      await pumpAuthWidget(
        tester,
        container,
        const SymphonyLoginForm(
          identifierField: 'username',
          identifierLabel: 'Username',
          identifierKeyboardType: TextInputType.text,
          submitLabel: 'Log in',
          identifierValidator: _requiredOnly,
        ),
      );

      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
      await fillAndSubmit(tester, email: 'grace', password: 'cobol1959');
      await tester.pumpAndSettle();

      expect(container.read(currentUserProvider), plainUser);
    });
  });

  group('with a mocked backend', () {
    late MockAuthAdapter adapter;

    setUp(() {
      adapter = MockAuthAdapter();
      stubAdapterDefaults(adapter);
    });

    testWidgets('disables the button while signing in', (tester) async {
      final pending = Completer<AuthSession>();
      when(() => adapter.login(any())).thenAnswer((_) => pending.future);
      final container = createAuthContainer(adapter: adapter);
      await pumpAuthWidget(tester, container, const SymphonyLoginForm());

      await fillAndSubmit(tester);
      await tester.pump();

      final loading = tester.widget<SymphonyButton>(submitButton());
      expect(loading.isLoading, isTrue);
      expect(loading.onPressed, isNull);
      await tester.tap(submitButton(), warnIfMissed: false);
      await tester.pump();
      verify(() => adapter.login(any())).called(1);

      pending.complete(testSession());
      await tester.pumpAndSettle();

      final idle = tester.widget<SymphonyButton>(submitButton());
      expect(idle.isLoading, isFalse);
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
    });

    testWidgets('maps validation field errors to the inputs', (tester) async {
      when(() => adapter.login(any())).thenAnswer(
        (_) => Future<AuthSession>.error(
          const ValidationFailure(
            'The given data was invalid.',
            fieldErrors: <String, List<String>>{
              'email': <String>['This account is locked.'],
            },
          ),
        ),
      );
      final container = createAuthContainer(adapter: adapter);
      await pumpAuthWidget(tester, container, const SymphonyLoginForm());

      await fillAndSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('This account is locked.'), findsOneWidget);
      expect(find.text('The given data was invalid.'), findsNothing);

      await tester.enterText(identifierInput(), 'other@example.com');
      await tester.pump();

      expect(find.text('This account is locked.'), findsNothing);
    });

    testWidgets('builds credentials with the hooks', (tester) async {
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      final container = createAuthContainer(adapter: adapter);
      await pumpAuthWidget(
        tester,
        container,
        SymphonyLoginForm(
          credentialsBuilder: (identifier, password) =>
              AuthCredentials.usernamePassword(
            username: identifier,
            password: password,
          ),
          extraFields: const <Widget>[Text('Tenant: acme')],
          extraCredentials: () => <String, Object?>{'tenant': 'acme'},
        ),
      );

      expect(find.text('Tenant: acme'), findsOneWidget);
      await fillAndSubmit(tester, email: '  admin@example.com  ');
      await tester.pumpAndSettle();

      final captured =
          verify(() => adapter.login(captureAny())).captured.single;
      expect((captured as AuthCredentials).fields, <String, Object?>{
        'username': 'admin@example.com',
        'password': 'secret123',
        'tenant': 'acme',
      });
    });
  });
}

String? _requiredOnly(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;
