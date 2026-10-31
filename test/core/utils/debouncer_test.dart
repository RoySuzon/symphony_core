import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  const delay = Duration(milliseconds: 300);

  group('Debouncer', () {
    testWidgets('runs only the last action once the delay elapsed', (
      tester,
    ) async {
      final debouncer = Debouncer(delay);
      final calls = <String>[];

      debouncer.run(() => calls.add('a'));
      await tester.pump(const Duration(milliseconds: 200));
      debouncer.run(() => calls.add('b'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, isEmpty, reason: 'the second call restarted the delay');
      expect(debouncer.isPending, isTrue);

      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, <String>['b']);
      expect(debouncer.isPending, isFalse);

      debouncer.dispose();
    });

    testWidgets('cancel discards the pending action', (tester) async {
      final debouncer = Debouncer(delay);
      var calls = 0;

      debouncer
        ..run(() => calls++)
        ..cancel();
      await tester.pump(delay * 2);

      expect(calls, 0);
      expect(debouncer.isPending, isFalse);
      debouncer.dispose();
    });

    testWidgets('flush runs the pending action immediately', (tester) async {
      final debouncer = Debouncer(delay);
      var calls = 0;

      debouncer.flush();
      expect(calls, 0, reason: 'nothing pending');

      debouncer
        ..run(() => calls++)
        ..flush();
      expect(calls, 1);
      expect(debouncer.isPending, isFalse);

      await tester.pump(delay * 2);
      expect(calls, 1, reason: 'the flushed action does not run again');
      debouncer.dispose();
    });

    testWidgets('dispose cancels and ignores later calls', (tester) async {
      final debouncer = Debouncer(delay);
      var calls = 0;

      debouncer
        ..run(() => calls++)
        ..dispose()
        ..run(() => calls++);
      await tester.pump(delay * 2);

      expect(calls, 0);
      expect(debouncer.isDisposed, isTrue);
      expect(debouncer.isPending, isFalse);
    });

    testWidgets('can be reused after an action ran', (tester) async {
      final debouncer = Debouncer(Duration.zero);
      var calls = 0;

      debouncer.run(() => calls++);
      await tester.pump(Duration.zero);
      debouncer.run(() => calls++);
      await tester.pump(Duration.zero);

      expect(calls, 2);
      debouncer.dispose();
    });

    test('rejects a negative delay', () {
      expect(
        () => Debouncer(const Duration(milliseconds: -1)),
        throwsAssertionError,
      );
    });
  });

  group('Throttler', () {
    testWidgets('runs the first call immediately and drops calls during the '
        'cooldown', (tester) async {
      final throttler = Throttler(delay);
      final calls = <int>[];

      throttler.run(() => calls.add(1));
      expect(calls, <int>[1]);
      expect(throttler.isThrottling, isTrue);

      throttler.run(() => calls.add(2));
      await tester.pump(const Duration(milliseconds: 299));
      throttler.run(() => calls.add(3));
      expect(calls, <int>[1]);

      await tester.pump(const Duration(milliseconds: 1));
      expect(throttler.isThrottling, isFalse);
      expect(calls, <int>[1], reason: 'dropped calls never run');

      throttler.run(() => calls.add(4));
      expect(calls, <int>[1, 4]);

      throttler.dispose();
    });

    testWidgets('trailing runs the latest dropped call after the cooldown', (
      tester,
    ) async {
      final throttler = Throttler(delay, trailing: true);
      final calls = <int>[];

      throttler
        ..run(() => calls.add(1))
        ..run(() => calls.add(2))
        ..run(() => calls.add(3));
      expect(calls, <int>[1]);

      await tester.pump(delay);
      expect(calls, <int>[1, 3]);
      expect(throttler.isThrottling, isTrue, reason: 'new cooldown started');

      await tester.pump(delay);
      expect(calls, <int>[1, 3]);
      expect(throttler.isThrottling, isFalse);

      throttler.dispose();
    });

    testWidgets('a throwing action still starts the cooldown', (tester) async {
      final throttler = Throttler(delay);
      var calls = 0;

      expect(
        () => throttler.run(() => throw StateError('boom')),
        throwsStateError,
      );
      throttler.run(() => calls++);

      expect(calls, 0);
      expect(throttler.isThrottling, isTrue);
      await tester.pump(delay);
      throttler.dispose();
    });

    testWidgets('cancel ends the cooldown and drops the trailing call', (
      tester,
    ) async {
      final throttler = Throttler(delay, trailing: true);
      final calls = <int>[];

      throttler
        ..run(() => calls.add(1))
        ..run(() => calls.add(2))
        ..cancel();
      expect(throttler.isThrottling, isFalse);

      throttler.run(() => calls.add(3));
      await tester.pump(delay * 2);

      expect(calls, <int>[1, 3]);
      throttler.dispose();
    });

    testWidgets('dispose ignores later calls and pending trailing calls', (
      tester,
    ) async {
      final throttler = Throttler(delay, trailing: true);
      final calls = <int>[];

      throttler
        ..run(() => calls.add(1))
        ..run(() => calls.add(2))
        ..dispose()
        ..run(() => calls.add(3));
      await tester.pump(delay * 2);

      expect(calls, <int>[1]);
      expect(throttler.isDisposed, isTrue);
      expect(throttler.isThrottling, isFalse);
    });

    test('rejects a negative interval', () {
      expect(
        () => Throttler(const Duration(seconds: -1)),
        throwsAssertionError,
      );
    });
  });
}
