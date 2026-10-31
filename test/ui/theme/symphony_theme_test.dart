import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

BorderRadiusGeometry? _buttonRadius(ButtonStyle? style) {
  final shape = style?.shape?.resolve(const {});
  return shape is RoundedRectangleBorder ? shape.borderRadius : null;
}

void main() {
  group('SymphonyTheme.light', () {
    test('builds a Material 3 light theme with the symphony extensions', () {
      final theme = SymphonyTheme.light();

      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.extension<SymphonyColors>(), SymphonyColors.light);
      expect(theme.extension<SymphonyRadius>(), SymphonyRadius.fromBase(12));
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
    });

    test('generates the colour scheme from the seed colour', () {
      const seed = Color(0xFF00796B);
      final theme = SymphonyTheme.light(
        const SymphonyThemeConfig(seedColor: seed),
      );
      final expected = ColorScheme.fromSeed(seedColor: seed);

      expect(theme.colorScheme.primary, expected.primary);
      expect(theme.colorScheme.secondary, expected.secondary);
    });

    test('uses the default seed colour when none is configured', () {
      final expected = ColorScheme.fromSeed(
        seedColor: SymphonyThemeConfig.defaultSeedColor,
      );

      expect(SymphonyTheme.light().colorScheme.primary, expected.primary);
    });

    test('applies the corner radius to every button theme', () {
      final theme = SymphonyTheme.light(
        const SymphonyThemeConfig(cornerRadius: 20),
      );
      final expected = BorderRadius.circular(20);

      expect(_buttonRadius(theme.filledButtonTheme.style), expected);
      expect(_buttonRadius(theme.outlinedButtonTheme.style), expected);
      expect(_buttonRadius(theme.textButtonTheme.style), expected);
      expect(_buttonRadius(theme.elevatedButtonTheme.style), expected);
      expect(theme.extension<SymphonyRadius>()!.medium, 20);
    });

    test('applies the font family and the visual density', () {
      final theme = SymphonyTheme.light(
        const SymphonyThemeConfig(
          fontFamily: 'Inter',
          visualDensity: VisualDensity.compact,
        ),
      );

      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
      expect(theme.textTheme.titleLarge!.fontFamily, 'Inter');
      expect(theme.visualDensity, VisualDensity.compact);
    });

    test('configures snack bars, FABs and progress indicators', () {
      final theme = SymphonyTheme.light();
      final scheme = theme.colorScheme;

      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.backgroundColor, scheme.inverseSurface);
      expect(theme.snackBarTheme.actionTextColor, scheme.inversePrimary);
      expect(
        theme.floatingActionButtonTheme.backgroundColor,
        scheme.primaryContainer,
      );
      expect(
        theme.floatingActionButtonTheme.foregroundColor,
        scheme.onPrimaryContainer,
      );
      expect(theme.progressIndicatorTheme.color, scheme.primary);
      expect(
        theme.progressIndicatorTheme.linearTrackColor,
        scheme.primaryContainer,
      );
    });

    test('overrides status colours and derives readable foregrounds', () {
      final theme = SymphonyTheme.light(
        const SymphonyThemeConfig(
          successColor: Color(0xFFFFEB3B),
          warningColor: Color(0xFF1B1B1B),
          infoColor: Color(0xFF0D47A1),
        ),
      );
      final colors = theme.extension<SymphonyColors>()!;

      expect(colors.success, const Color(0xFFFFEB3B));
      expect(colors.onSuccess, const Color(0xFF000000));
      expect(colors.warning, const Color(0xFF1B1B1B));
      expect(colors.onWarning, const Color(0xFFFFFFFF));
      expect(colors.info, const Color(0xFF0D47A1));
      expect(colors.onInfo, const Color(0xFFFFFFFF));
    });

    test('registers additional extensions, replacing built-in ones', () {
      const custom = SymphonyColors(
        success: Color(0xFF000001),
        onSuccess: Color(0xFF000002),
        warning: Color(0xFF000003),
        onWarning: Color(0xFF000004),
        info: Color(0xFF000005),
        onInfo: Color(0xFF000006),
      );
      final theme = SymphonyTheme.light(
        const SymphonyThemeConfig(
          extensions: <ThemeExtension<dynamic>>[custom],
        ),
      );

      expect(theme.extension<SymphonyColors>(), same(custom));
      expect(theme.extension<SymphonyRadius>(), isNotNull);
    });
  });

  group('SymphonyTheme.dark', () {
    test('builds a dark theme with the dark status colours', () {
      final theme = SymphonyTheme.dark();

      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.extension<SymphonyColors>(), SymphonyColors.dark);
    });

    test('uses explicit colour schemes when provided', () {
      const config = SymphonyThemeConfig(
        lightColorScheme: ColorScheme.light(primary: Color(0xFF123456)),
        darkColorScheme: ColorScheme.dark(primary: Color(0xFF654321)),
      );

      expect(
        SymphonyTheme.light(config).colorScheme.primary,
        const Color(0xFF123456),
      );
      expect(
        SymphonyTheme.dark(config).colorScheme.primary,
        const Color(0xFF654321),
      );
    });
  });

  group('SymphonyThemeConfig', () {
    test('has sensible defaults', () {
      const config = SymphonyThemeConfig();

      expect(config.seedColor, SymphonyThemeConfig.defaultSeedColor);
      expect(config.cornerRadius, 12);
      expect(config.fontFamily, isNull);
      expect(config.visualDensity, isNull);
      expect(config.extensions, isEmpty);
    });

    test('copyWith replaces only the given values', () {
      const config = SymphonyThemeConfig(fontFamily: 'Inter');
      final copy = config.copyWith(cornerRadius: 4, seedColor: Colors.teal);

      expect(copy.cornerRadius, 4);
      expect(copy.seedColor, Colors.teal);
      expect(copy.fontFamily, 'Inter');
    });
  });

  testWidgets('widgets read the theme extensions', (tester) async {
    late SymphonyColors colors;
    late SymphonyRadius radius;
    await tester.pumpWidget(
      MaterialApp(
        theme: SymphonyTheme.light(
          const SymphonyThemeConfig(cornerRadius: 6),
        ),
        home: Builder(
          builder: (context) {
            colors = SymphonyColors.of(context);
            radius = SymphonyRadius.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(colors, SymphonyColors.light);
    expect(radius.medium, 6);
  });
}
