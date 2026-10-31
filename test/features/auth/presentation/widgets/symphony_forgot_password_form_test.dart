import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/auth/auth.dart';

import '../../support/auth_test_support.dart';

void main() {
  late InMemoryAuthAdapter adapter;
  final issuedCodes = <String>[];

  setUp(() {
    issuedCodes.clear();
    adapter = InMemoryAuthAdapter(
      accounts: demoAccounts,
      onResetCodeIssued: (identifier, code) => issuedCodes.add(code),
    );
  });

  Future<void> requestReset(WidgetTester tester, String email) async {
    await tester.enterText(
      find.byKey(SymphonyForgotPasswordForm.identifierInputKey),
      email,
    );
    await tester.tap(find.byKey(SymphonyForgotPasswordForm.requestButtonKey));
    await tester.pumpAndSettle();
  }

  testWidgets('requests a reset and shows the confirmation message',
      (tester) async {
    final container = createAuthContainer(adapter: adapter);
    String? sentTo;
    await pumpAuthWidget(
      tester,
      container,
      SymphonyForgotPasswordForm(onRequestSent: (email) => sentTo = email),
    );

    await requestReset(tester, 'admin@example.com');

    expect(sentTo, 'admin@example.com');
    expect(issuedCodes, hasLength(1));
    expect(
      find.textContaining('you will receive password reset instructions'),
      findsOneWidget,
    );
    expect(
      find.byKey(SymphonyForgotPasswordForm.identifierInputKey),
      findsNothing,
    );
  });

  testWidgets('validates the identifier', (tester) async {
    final container = createAuthContainer(adapter: adapter);
    await pumpAuthWidget(
      tester,
      container,
      const SymphonyForgotPasswordForm(),
    );

    await requestReset(tester, 'not-an-email');

    expect(find.text('Enter a valid e-mail address.'), findsOneWidget);
    expect(issuedCodes, isEmpty);
  });

  testWidgets('completes the reset with the code and a new password',
      (tester) async {
    final container = createAuthContainer(adapter: adapter);
    var completed = false;
    await pumpAuthWidget(
      tester,
      container,
      SymphonyForgotPasswordForm(
        enableConfirmStep: true,
        onCompleted: () => completed = true,
      ),
    );

    await requestReset(tester, 'admin@example.com');

    expect(find.byKey(SymphonyForgotPasswordForm.codeInputKey), findsOneWidget);
    await tester.enterText(
      find.byKey(SymphonyForgotPasswordForm.codeInputKey),
      'wrong',
    );
    await tester.enterText(
      find.byKey(SymphonyForgotPasswordForm.newPasswordInputKey),
      'changed99',
    );
    await tester.enterText(
      find.byKey(SymphonyForgotPasswordForm.confirmPasswordInputKey),
      'changed99',
    );
    await tester.tap(find.byKey(SymphonyForgotPasswordForm.confirmButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('The code is invalid or has expired.'), findsOneWidget);
    expect(completed, isFalse);

    await tester.enterText(
      find.byKey(SymphonyForgotPasswordForm.codeInputKey),
      issuedCodes.single,
    );
    await tester.tap(find.byKey(SymphonyForgotPasswordForm.confirmButtonKey));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(
      find.text('Your password has been reset. You can now sign in.'),
      findsOneWidget,
    );
    final session = await adapter.login(
      AuthCredentials.emailPassword(
        email: 'admin@example.com',
        password: 'changed99',
      ),
    );
    expect(session.user, adminUser);
  });

  testWidgets('resends the code from the confirmation step', (tester) async {
    final container = createAuthContainer(adapter: adapter);
    await pumpAuthWidget(
      tester,
      container,
      const SymphonyForgotPasswordForm(enableConfirmStep: true),
    );

    await requestReset(tester, 'admin@example.com');
    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();

    expect(issuedCodes, hasLength(2));
  });

  testWidgets('explains when recovery is unavailable', (tester) async {
    final container = createAuthContainer(
      adapter: InMemoryAuthAdapter(
        accounts: demoAccounts,
        passwordRecoveryEnabled: false,
      ),
    );
    var backTaps = 0;
    await pumpAuthWidget(
      tester,
      container,
      SymphonyForgotPasswordForm(onBackToSignIn: () => backTaps++),
    );

    expect(find.text('Password recovery is not available.'), findsOneWidget);

    await tester.tap(find.text('Back to sign in'));
    expect(backTaps, 1);
  });
}
