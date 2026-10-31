import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

void main() {
  group('SymphonyRadius', () {
    test('defaults to the 8 / 12 / 16 / 28 scale', () {
      const radius = SymphonyRadius.standard;

      expect(radius.small, 8);
      expect(radius.medium, 12);
      expect(radius.large, 16);
      expect(radius.extraLarge, 28);
      expect(SymphonyRadius.fromBase(12), radius);
    });

    test('fromBase derives the whole scale from the base radius', () {
      final radius = SymphonyRadius.fromBase(24);

      expect(radius.small, 16);
      expect(radius.medium, 24);
      expect(radius.large, 32);
      expect(radius.extraLarge, 56);
      expect(
        SymphonyRadius.fromBase(0),
        const SymphonyRadius(small: 0, medium: 0, large: 0, extraLarge: 0),
      );
    });

    test('exposes border radii', () {
      const radius = SymphonyRadius.standard;

      expect(radius.smallBorderRadius, BorderRadius.circular(8));
      expect(radius.mediumBorderRadius, BorderRadius.circular(12));
      expect(radius.largeBorderRadius, BorderRadius.circular(16));
      expect(radius.extraLargeBorderRadius, BorderRadius.circular(28));
      expect(SymphonyRadius.full, greaterThan(radius.extraLarge));
    });

    test('copyWith and lerp', () {
      const a = SymphonyRadius.standard;
      final b = a.copyWith(medium: 20);

      expect(b.medium, 20);
      expect(b.small, a.small);
      expect(a.lerp(b, 0.5).medium, 16);
      expect(a.lerp(null, 0.5), same(a));
      expect(b, isNot(a));
      expect(a.copyWith().hashCode, a.hashCode);
      expect(a.toString(), contains('medium: 12'));
    });

    testWidgets('of falls back to the standard scale', (tester) async {
      late SymphonyRadius radius;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(),
          child: Builder(
            builder: (context) {
              radius = SymphonyRadius.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(radius, SymphonyRadius.standard);
    });
  });

  group('SymphonySpacing', () {
    test('is an increasing scale on a 4 point grid', () {
      const scale = <double>[
        SymphonySpacing.none,
        SymphonySpacing.xxs,
        SymphonySpacing.xs,
        SymphonySpacing.sm,
        SymphonySpacing.md,
        SymphonySpacing.lg,
        SymphonySpacing.xl,
        SymphonySpacing.xxl,
      ];

      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
      expect(SymphonySpacing.lg, 16);
    });

    test('provides matching EdgeInsets helpers', () {
      expect(SymphonySpacing.allLg, const EdgeInsets.all(16));
      expect(SymphonySpacing.allXxs, const EdgeInsets.all(2));
      expect(SymphonySpacing.allXxl, const EdgeInsets.all(32));
      expect(
        SymphonySpacing.horizontalMd,
        const EdgeInsets.symmetric(horizontal: 12),
      );
      expect(
        SymphonySpacing.verticalXl,
        const EdgeInsets.symmetric(vertical: 24),
      );
      expect(SymphonySpacing.screen, const EdgeInsets.all(16));
    });
  });
}
