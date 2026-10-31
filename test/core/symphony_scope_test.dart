import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

import 'helpers/core_test_helpers.dart';

class _ConfigLabel extends ConsumerWidget {
  const _ConfigLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(symphonyConfigProvider);
    return Text(config.appName, textDirection: TextDirection.ltr);
  }
}

void main() {
  tearDown(SymphonyCore.reset);

  testWidgets('wrap exposes the providers of the instance to widgets',
      (tester) async {
    final core = SymphonyCore.create(config: testConfig);

    await tester.pumpWidget(core.wrap(const _ConfigLabel()));

    expect(find.text('Core Test App'), findsOneWidget);
    final element = tester.element(find.byType(_ConfigLabel));
    expect(
      ProviderScope.containerOf(element, listen: false),
      same(core.container),
    );

    await tester.pumpWidget(const SizedBox());
    await core.dispose();
  });

  testWidgets('SymphonyScope defaults to the global instance', (tester) async {
    await SymphonyCore.initialize(
      config: testConfig.copyWith(appName: 'Global App'),
    );

    await tester.pumpWidget(
      const SymphonyScope(child: MaterialApp(home: _ConfigLabel())),
    );

    expect(find.text('Global App'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an explicit core takes precedence over the global instance',
      (tester) async {
    await SymphonyCore.initialize(
      config: testConfig.copyWith(appName: 'Global App'),
    );
    final local = SymphonyCore.create(
      config: testConfig.copyWith(appName: 'Local App'),
    );

    await tester
        .pumpWidget(SymphonyScope(core: local, child: const _ConfigLabel()));

    expect(find.text('Local App'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await local.dispose();
  });

  testWidgets('reports a helpful error without an initialized instance',
      (tester) async {
    await tester.pumpWidget(const SymphonyScope(child: _ConfigLabel()));

    final error = tester.takeException();
    expect(error, isA<StateError>());
    expect('$error', contains('SymphonyCore.initialize'));
  });
}
