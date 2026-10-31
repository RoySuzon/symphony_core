import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

Future<SymphonyColors> _colorsOf(WidgetTester tester, ThemeData theme) async {
  late SymphonyColors colors;
  await tester.pumpWidget(
    Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          colors = SymphonyColors.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return colors;
}

void main() {
  group('SymphonyColors', () {
    testWidgets('of returns the registered extension', (tester) async {
      const custom = SymphonyColors(
        success: Color(0xFF00FF00),
        onSuccess: Color(0xFF000000),
        warning: Color(0xFFFFA000),
        onWarning: Color(0xFF000000),
        info: Color(0xFF2196F3),
        onInfo: Color(0xFFFFFFFF),
      );
      final colors = await _colorsOf(
        tester,
        ThemeData(extensions: const <ThemeExtension<dynamic>>[custom]),
      );

      expect(colors, same(custom));
    });

    testWidgets('of falls back to the light defaults', (tester) async {
      final colors = await _colorsOf(tester, ThemeData());

      expect(colors, SymphonyColors.light);
    });

    testWidgets('of falls back to the dark defaults', (tester) async {
      final colors = await _colorsOf(
        tester,
        ThemeData(brightness: Brightness.dark),
      );

      expect(colors, SymphonyColors.dark);
    });

    test('fallback picks the defaults matching the brightness', () {
      expect(SymphonyColors.fallback(Brightness.light), SymphonyColors.light);
      expect(SymphonyColors.fallback(Brightness.dark), SymphonyColors.dark);
    });

    test('fromAccents derives readable foregrounds', () {
      final colors = SymphonyColors.fromAccents(
        success: const Color(0xFF1B5E20),
        warning: const Color(0xFFFFEB3B),
        info: const Color(0xFFE3F2FD),
      );

      expect(colors.success, const Color(0xFF1B5E20));
      expect(colors.onSuccess, const Color(0xFFFFFFFF));
      expect(colors.onWarning, const Color(0xFF000000));
      expect(colors.onInfo, const Color(0xFF000000));
    });

    test('foregroundFor returns white on dark and black on light colours', () {
      expect(
        SymphonyColors.foregroundFor(const Color(0xFF000000)),
        const Color(0xFFFFFFFF),
      );
      expect(
        SymphonyColors.foregroundFor(const Color(0xFFFFFFFF)),
        const Color(0xFF000000),
      );
    });

    test('copyWith replaces only the given colours', () {
      final copy = SymphonyColors.light.copyWith(
        success: const Color(0xFF111111),
        onInfo: const Color(0xFF222222),
      );

      expect(copy.success, const Color(0xFF111111));
      expect(copy.onInfo, const Color(0xFF222222));
      expect(copy.onSuccess, SymphonyColors.light.onSuccess);
      expect(copy.warning, SymphonyColors.light.warning);
      expect(copy.onWarning, SymphonyColors.light.onWarning);
      expect(copy.info, SymphonyColors.light.info);
    });

    test('copyWith without arguments returns an equal instance', () {
      expect(SymphonyColors.dark.copyWith(), SymphonyColors.dark);
    });

    test('lerp interpolates every colour', () {
      const a = SymphonyColors.light;
      const b = SymphonyColors.dark;
      final middle = a.lerp(b, 0.5);

      expect(middle.success, Color.lerp(a.success, b.success, 0.5));
      expect(middle.onSuccess, Color.lerp(a.onSuccess, b.onSuccess, 0.5));
      expect(middle.warning, Color.lerp(a.warning, b.warning, 0.5));
      expect(middle.onWarning, Color.lerp(a.onWarning, b.onWarning, 0.5));
      expect(middle.info, Color.lerp(a.info, b.info, 0.5));
      expect(middle.onInfo, Color.lerp(a.onInfo, b.onInfo, 0.5));
      expect(a.lerp(b, 0), a);
      expect(a.lerp(b, 1), b);
    });

    test('lerp with null returns the same instance', () {
      expect(SymphonyColors.light.lerp(null, 0.3), same(SymphonyColors.light));
    });

    test('implements value equality', () {
      final copy = SymphonyColors.light.copyWith();

      expect(copy, SymphonyColors.light);
      expect(copy.hashCode, SymphonyColors.light.hashCode);
      expect(SymphonyColors.light == SymphonyColors.dark, isFalse);
      expect(SymphonyColors.light.toString(), contains('success'));
    });

    test('is interpolated by ThemeData.lerp', () {
      final lerped = ThemeData.lerp(
        SymphonyTheme.light(),
        SymphonyTheme.dark(),
        0.5,
      );

      expect(
        lerped.extension<SymphonyColors>(),
        SymphonyColors.light.lerp(SymphonyColors.dark, 0.5),
      );
    });
  });
}
