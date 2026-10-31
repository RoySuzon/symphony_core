import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/auth/auth.dart';

import '../../support/auth_test_support.dart';

void main() {
  Future<void> fill(
    WidgetTester tester, {
    String name = 'Newton',
    String email = 'new@example.com',
    String password = 'brandNew1',
    String? confirmation,
  }) async {
    await tester.enterText(find.byKey(SymphonyRegisterForm.nameInputKey), name);
    await tester.enterText(
      find.byKey(SymphonyRegisterForm.identifierInputKey),
      email,
    );
    await tester.enterText(
      find.byKey(SymphonyRegisterForm.passwordInputKey),
      password,
    );
    await tester.enterText(
      find.byKey(SymphonyRegisterForm.confirmPasswordInputKey),
      confirmation ?? password,
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(SymphonyRegisterForm.submitButtonKey));
    await tester.pumpAndSettle();
  }

  testWidgets('registers and signs the new user in', (tester) async {
    final container = createAuthContainer(
      adapter: InMemoryAuthAdapter(accounts: demoAccounts),
    );
    AuthSession? registered;
    await pumpAuthWidget(
      tester,
      container,
      SymphonyRegisterForm(onSuccess: (session) => registered = session),
    );

    await fill(tester);
    await submit(tester);

    expect(registered?.user?.displayName, 'Newton');
    expect(container.read(authControllerProvider).isAuthenticated, isTrue);
  });

  testWidgets('validates the password confirmation and length',
      (tester) async {
    final container = createAuthContainer(
      adapter: InMemoryAuthAdapter(accounts: demoAccounts),
    );
    await pumpAuthWidget(tester, container, const SymphonyRegisterForm());

    await fill(tester, password: 'short', confirmation: 'different');
    await submit(tester);

    expect(find.text('Must be at least 8 characters.'), findsOneWidget);
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(container.read(authControllerProvider).isAuthenticated, isFalse);
  });

  testWidgets('shows server-side field errors', (tester) async {
    final container = createAuthContainer(
      adapter: InMemoryAuthAdapter(accounts: demoAccounts),
    );
    await pumpAuthWidget(tester, container, const SymphonyRegisterForm());

    await fill(tester, email: 'admin@example.com');
    await submit(tester);

    expect(
      find.text('An account with this identifier already exists.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the success message when no session is returned',
      (tester) async {
    final container = createAuthContainer(
      adapter: InMemoryAuthAdapter(
        accounts: demoAccounts,
        signInAfterRegistration: false,
      ),
    );
    var called = false;
    AuthSession? registered = testSession();
    await pumpAuthWidget(
      tester,
      container,
      SymphonyRegisterForm(
        successMessage: 'Check your inbox',
        onSuccess: (session) {
          called = true;
          registered = session;
        },
      ),
    );

    await fill(tester);
    await submit(tester);

    expect(called, isTrue);
    expect(registered, isNull);
    expect(find.text('Check your inbox'), findsOneWidget);
    expect(container.read(authControllerProvider).isAuthenticated, isFalse);
  });

  testWidgets('explains when registration is unavailable', (tester) async {
    final container = createAuthContainer(
      adapter: InMemoryAuthAdapter(
        accounts: demoAccounts,
        registrationEnabled: false,
      ),
    );
    var signInTaps = 0;
    await pumpAuthWidget(
      tester,
      container,
      SymphonyRegisterForm(onSignIn: () => signInTaps++),
    );

    expect(find.text('Registration is not available.'), findsOneWidget);
    expect(find.byKey(SymphonyRegisterForm.submitButtonKey), findsNothing);

    await tester.tap(find.text('Sign in'));
    expect(signInTaps, 1);
  });
}
