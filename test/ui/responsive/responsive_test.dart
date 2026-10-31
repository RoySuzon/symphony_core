import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../ui_test_utils.dart';

/// Pumps a [MediaQuery] reporting a screen of [size] and returns a context
/// below it.
Future<BuildContext> _pumpScreen(
  WidgetTester tester,
  Size size, {
  SymphonyBreakpoints? breakpoints,
}) async {
  late BuildContext captured;
  Widget child = Builder(
    builder: (context) {
      captured = context;
      return const SizedBox.shrink();
    },
  );
  if (breakpoints != null) {
    child = SymphonyBreakpointsScope(breakpoints: breakpoints, child: child);
  }
  await tester.pumpWidget(
    MediaQuery(data: MediaQueryData(size: size), child: child),
  );
  return captured;
}

void main() {
  group('SymphonyBreakpoints', () {
    test('classifies widths with the Material 3 defaults', () {
      const breakpoints = SymphonyBreakpoints.standard;
      final expectations = <double, ScreenSizeClass>{
        0: ScreenSizeClass.compact,
        360: ScreenSizeClass.compact,
        599.9: ScreenSizeClass.compact,
        600: ScreenSizeClass.medium,
        839: ScreenSizeClass.medium,
        840: ScreenSizeClass.expanded,
        1199: ScreenSizeClass.expanded,
        1200: ScreenSizeClass.large,
        2560: ScreenSizeClass.large,
      };

      for (final entry in expectations.entries) {
        expect(breakpoints.classify(entry.key), entry.value,
            reason: '${entry.key}');
      }
    });

    test('supports custom thresholds', () {
      const breakpoints = SymphonyBreakpoints(
        medium: 500,
        expanded: 900,
        large: 1600,
      );

      expect(breakpoints.classify(499), ScreenSizeClass.compact);
      expect(breakpoints.classify(500), ScreenSizeClass.medium);
      expect(breakpoints.classify(1000), ScreenSizeClass.expanded);
      expect(breakpoints.classify(1600), ScreenSizeClass.large);
    });

    test('implements value equality', () {
      expect(const SymphonyBreakpoints(), SymphonyBreakpoints.standard);
      expect(
        const SymphonyBreakpoints().hashCode,
        SymphonyBreakpoints.standard.hashCode,
      );
      expect(
        const SymphonyBreakpoints(medium: 700),
        isNot(SymphonyBreakpoints.standard),
      );
      expect(SymphonyBreakpoints.standard.toString(), contains('600'));
    });

    test('rejects thresholds that are not increasing', () {
      // Computed at runtime so the assertion is not evaluated as a constant.
      double width(double value) => value;

      expect(
        () => SymphonyBreakpoints(medium: width(900)),
        throwsAssertionError,
      );
      expect(
        () => SymphonyBreakpoints(expanded: width(1300)),
        throwsAssertionError,
      );
    });
  });

  group('ScreenSizeClass', () {
    test('compares size classes', () {
      expect(
        ScreenSizeClass.expanded.isAtLeast(ScreenSizeClass.medium),
        isTrue,
      );
      expect(ScreenSizeClass.medium.isAtLeast(ScreenSizeClass.medium), isTrue);
      expect(
        ScreenSizeClass.compact.isAtLeast(ScreenSizeClass.medium),
        isFalse,
      );
      expect(ScreenSizeClass.compact.isAtMost(ScreenSizeClass.medium), isTrue);
      expect(ScreenSizeClass.large.isAtMost(ScreenSizeClass.expanded), isFalse);
    });
  });

  group('SymphonyResponsiveContextX', () {
    testWidgets('classifies the screen width', (tester) async {
      var context = await _pumpScreen(tester, const Size(400, 800));
      expect(context.screenSizeClass, ScreenSizeClass.compact);
      expect(context.isCompact, isTrue);
      expect(context.isMediumOrLarger, isFalse);
      expect(context.isExpandedOrLarger, isFalse);

      context = await _pumpScreen(tester, const Size(700, 800));
      expect(context.screenSizeClass, ScreenSizeClass.medium);
      expect(context.isCompact, isFalse);
      expect(context.isMediumOrLarger, isTrue);
      expect(context.isExpandedOrLarger, isFalse);

      context = await _pumpScreen(tester, const Size(1000, 800));
      expect(context.screenSizeClass, ScreenSizeClass.expanded);
      expect(context.isExpandedOrLarger, isTrue);

      context = await _pumpScreen(tester, const Size(1400, 900));
      expect(context.screenSizeClass, ScreenSizeClass.large);
      expect(context.isMediumOrLarger, isTrue);
      expect(context.isExpandedOrLarger, isTrue);
    });

    testWidgets('honours the breakpoints scope', (tester) async {
      final context = await _pumpScreen(
        tester,
        const Size(700, 800),
        breakpoints: const SymphonyBreakpoints(medium: 720),
      );

      expect(context.screenSizeClass, ScreenSizeClass.compact);
      expect(SymphonyBreakpoints.of(context).medium, 720);
    });

    testWidgets('rebuilds dependents when the scope changes', (tester) async {
      final classes = <ScreenSizeClass>[];
      Widget build(SymphonyBreakpoints breakpoints) => MediaQuery(
            data: const MediaQueryData(size: Size(700, 800)),
            child: SymphonyBreakpointsScope(
              breakpoints: breakpoints,
              child: Builder(
                builder: (context) {
                  classes.add(context.screenSizeClass);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );

      await tester.pumpWidget(build(SymphonyBreakpoints.standard));
      await tester.pumpWidget(build(const SymphonyBreakpoints(medium: 720)));

      expect(classes, <ScreenSizeClass>[
        ScreenSizeClass.medium,
        ScreenSizeClass.compact,
      ]);
    });
  });

  group('ResponsiveBuilder', () {
    testWidgets('classifies the available width, not the screen',
        (tester) async {
      final widths = <double, ScreenSizeClass>{
        320: ScreenSizeClass.compact,
        700: ScreenSizeClass.medium,
        1000: ScreenSizeClass.expanded,
        1300: ScreenSizeClass.large,
      };

      for (final entry in widths.entries) {
        ScreenSizeClass? received;
        BoxConstraints? constraints;
        await tester.pumpWidget(
          withWidth(
            entry.key,
            ResponsiveBuilder(
              builder: (context, sizeClass, boxConstraints) {
                received = sizeClass;
                constraints = boxConstraints;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(received, entry.value, reason: '${entry.key}');
        expect(constraints!.maxWidth, entry.key);
      }
    });

    testWidgets('uses custom breakpoints', (tester) async {
      ScreenSizeClass? received;
      await tester.pumpWidget(
        withWidth(
          700,
          ResponsiveBuilder(
            breakpoints: const SymphonyBreakpoints(medium: 750),
            builder: (context, sizeClass, _) {
              received = sizeClass;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(received, ScreenSizeClass.compact);
    });

    testWidgets('falls back to the screen width when unbounded',
        (tester) async {
      ScreenSizeClass? received;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1300, 900)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ResponsiveBuilder(
                builder: (context, sizeClass, _) {
                  received = sizeClass;
                  return const SizedBox(width: 10, height: 10);
                },
              ),
            ),
          ),
        ),
      );

      expect(received, ScreenSizeClass.large);
    });
  });

  group('ResponsiveLayout', () {
    Future<void> pumpLayout(
      WidgetTester tester,
      double width,
      ResponsiveLayout layout,
    ) =>
        tester.pumpWidget(withWidth(width, layout));

    testWidgets('selects the layout of each size class', (tester) async {
      const layout = ResponsiveLayout(
        compact: Text('compact'),
        medium: Text('medium'),
        expanded: Text('expanded'),
        large: Text('large'),
      );

      await pumpLayout(tester, 400, layout);
      expect(find.text('compact'), findsOneWidget);
      await pumpLayout(tester, 700, layout);
      expect(find.text('medium'), findsOneWidget);
      await pumpLayout(tester, 1000, layout);
      expect(find.text('expanded'), findsOneWidget);
      await pumpLayout(tester, 1300, layout);
      expect(find.text('large'), findsOneWidget);
    });

    testWidgets('falls back to the next smaller layout', (tester) async {
      const layout = ResponsiveLayout(
        compact: Text('compact'),
        expanded: Text('expanded'),
      );

      await pumpLayout(tester, 700, layout);
      expect(find.text('compact'), findsOneWidget);
      await pumpLayout(tester, 1300, layout);
      expect(find.text('expanded'), findsOneWidget);

      const compactOnly = ResponsiveLayout(compact: Text('only'));
      await pumpLayout(tester, 1300, compactOnly);
      expect(find.text('only'), findsOneWidget);
    });

    test('layoutFor applies the fallback rules', () {
      const compact = Text('compact');
      const medium = Text('medium');
      const layout = ResponsiveLayout(compact: compact, medium: medium);

      expect(layout.layoutFor(ScreenSizeClass.compact), same(compact));
      expect(layout.layoutFor(ScreenSizeClass.medium), same(medium));
      expect(layout.layoutFor(ScreenSizeClass.expanded), same(medium));
      expect(layout.layoutFor(ScreenSizeClass.large), same(medium));
    });
  });

  group('ResponsiveValue', () {
    test('resolveFor falls back to the next smaller value', () {
      const value = ResponsiveValue<int>(compact: 1, expanded: 3);

      expect(value.resolveFor(ScreenSizeClass.compact), 1);
      expect(value.resolveFor(ScreenSizeClass.medium), 1);
      expect(value.resolveFor(ScreenSizeClass.expanded), 3);
      expect(value.resolveFor(ScreenSizeClass.large), 3);
      expect(
        const ResponsiveValue<int>.all(7).resolveFor(ScreenSizeClass.large),
        7,
      );
    });

    testWidgets('resolve uses the screen size class', (tester) async {
      const value = ResponsiveValue<double>(
        compact: 16,
        medium: 24,
        expanded: 32,
        large: 40,
      );

      var context = await _pumpScreen(tester, const Size(400, 800));
      expect(value.resolve(context), 16);
      context = await _pumpScreen(tester, const Size(700, 800));
      expect(value.resolve(context), 24);
      context = await _pumpScreen(tester, const Size(1000, 800));
      expect(value.resolve(context), 32);
      context = await _pumpScreen(tester, const Size(1400, 800));
      expect(value.resolve(context), 40);
      expect(
        value.resolve(
          context,
          breakpoints: const SymphonyBreakpoints(large: 1500),
        ),
        32,
      );
    });

    test('implements value equality', () {
      expect(
        const ResponsiveValue<int>(compact: 1, large: 2),
        const ResponsiveValue<int>(compact: 1, large: 2),
      );
      expect(
        const ResponsiveValue<int>(compact: 1).hashCode,
        const ResponsiveValue<int>(compact: 1).hashCode,
      );
      expect(
        const ResponsiveValue<int>(compact: 1),
        isNot(const ResponsiveValue<int>(compact: 2)),
      );
      expect(const ResponsiveValue<int>(compact: 1).toString(), contains('1'));
    });
  });

  group('SymphonyContentConstraint', () {
    testWidgets('limits the content width and centers it', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyContentConstraint(
            child: SizedBox(key: Key('content'), height: 50),
          ),
        ),
      );
      final content = find.byKey(const Key('content'));

      expect(tester.getSize(content).width, 600);
      expect(tester.getTopLeft(content), const Offset(100, 0));
    });

    testWidgets('fills narrow spaces and applies the padding', (tester) async {
      await tester.pumpWidget(
        withWidth(
          400,
          const SymphonyContentConstraint(
            padding: EdgeInsets.all(16),
            child: SizedBox(key: Key('content'), height: 50),
          ),
        ),
      );
      final content = find.byKey(const Key('content'));

      expect(tester.getSize(content).width, 368);
      expect(tester.getTopLeft(content), const Offset(16, 16));
    });

    testWidgets('supports a custom width and alignment', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyContentConstraint(
            maxWidth: 300,
            alignment: Alignment.topLeft,
            child: SizedBox(key: Key('content'), height: 50),
          ),
        ),
      );
      final content = find.byKey(const Key('content'));

      expect(tester.getSize(content).width, 300);
      expect(tester.getTopLeft(content), Offset.zero);
    });
  });

  group('responsiveColumns', () {
    test('counts the tiles that fit', () {
      expect(responsiveColumns(1000), 3);
      expect(responsiveColumns(560), 2);
      expect(responsiveColumns(559), 1);
      expect(responsiveColumns(1000, minTileWidth: 200), 5);
    });

    test('takes the spacing into account', () {
      // 3 tiles of 300 + 2 gaps of 20 = 940.
      expect(responsiveColumns(940, minTileWidth: 300, spacing: 20), 3);
      expect(responsiveColumns(939, minTileWidth: 300, spacing: 20), 2);
    });

    test('clamps the result', () {
      expect(responsiveColumns(100), 1);
      expect(responsiveColumns(100, minColumns: 2), 2);
      expect(responsiveColumns(5000, maxColumns: 4), 4);
      expect(responsiveColumns(0), 1);
      expect(responsiveColumns(double.infinity, minColumns: 2), 2);
    });
  });
}
