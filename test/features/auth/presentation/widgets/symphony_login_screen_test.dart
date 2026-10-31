import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/auth/auth.dart';

import '../../support/auth_test_support.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget screen) {
    final container = createAuthContainer(
      adapter: InMemoryAuthAdapter(accounts: demoAccounts),
    );
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
  }

  testWidgets('renders the default texts and form', (tester) async {
    await pumpScreen(tester, const SymphonyLoginScreen());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.byType(SymphonyLoginForm), findsOneWidget);
  });

  testWidgets('accepts a custom form, logo, header and footer', (tester) async {
    await pumpScreen(
      tester,
      const SymphonyLoginScreen(
        title: 'Acme',
        subtitle: null,
        logo: Icon(Icons.business),
        header: Text('Maintenance tonight'),
        footer: Text('v1.0.0'),
        form: SymphonyLoginForm(submitLabel: 'Enter'),
      ),
    );

    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsNothing);
    expect(find.byIcon(Icons.business), findsOneWidget);
    expect(find.text('Maintenance tonight'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
  });

  testWidgets('SymphonyAuthLayout constrains the content width',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      const SymphonyAuthLayout(
        maxWidth: 400,
        child: SizedBox(key: Key('content'), height: 20),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('content'))).width, 400);
  });
}
