import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';

void main() {
  late SymphonyDashboardController controller;
  late int notifications;

  setUp(() {
    controller = SymphonyDashboardController();
    notifications = 0;
    controller.addListener(() => notifications++);
  });

  tearDown(() => controller.dispose());

  test('starts at the top level', () {
    expect(controller.path, isEmpty);
    expect(controller.depth, 0);
    expect(controller.isAtRoot, isTrue);
    expect(controller.canGoBack, isFalse);
    expect(controller.currentGroupId, isNull);
  });

  test('starts at the initial path', () {
    final initial = SymphonyDashboardController(
      initialPath: <String>['a', 'b'],
    );
    addTearDown(initial.dispose);

    expect(initial.path, <String>['a', 'b']);
    expect(initial.currentGroupId, 'b');
    expect(initial.depth, 2);
  });

  test('open, goBack, goToDepth and goToRoot update the path', () {
    controller
      ..open('a')
      ..open('b')
      ..open('c');
    expect(controller.path, <String>['a', 'b', 'c']);
    expect(controller.canGoBack, isTrue);
    expect(notifications, 3);

    expect(controller.goBack(), isTrue);
    expect(controller.path, <String>['a', 'b']);

    controller.goToDepth(1);
    expect(controller.path, <String>['a']);

    controller.goToRoot();
    expect(controller.path, isEmpty);
    expect(controller.goBack(), isFalse);
    expect(notifications, 6);
  });

  test('only notifies when the path changes', () {
    controller.path = const <String>[];
    expect(notifications, 0);

    controller.path = <String>['a'];
    controller.path = <String>['a'];
    expect(notifications, 1);

    controller.goToDepth(1);
    expect(notifications, 1);
  });

  test('exposes an unmodifiable path', () {
    final source = <String>['a'];
    controller.path = source;
    source.add('b');

    expect(controller.path, <String>['a']);
    expect(() => controller.path.add('x'), throwsUnsupportedError);
  });

  test('goToDepth validates the depth', () {
    controller.open('a');

    expect(() => controller.goToDepth(-1), throwsRangeError);
    expect(() => controller.goToDepth(2), throwsRangeError);
  });
}
