import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/ui_primitives/theme/mawzoon_elevation.dart';
import 'package:mawzoon/ui_primitives/theme/mawzoon_spacing.dart';

void main() {
  const MawzoonSpacing space = MawzoonSpacing.standard();

  group('spacing scale', () {
    test('rises monotonically', () {
      final List<double> scale = <double>[
        space.micro,
        space.tight,
        space.snug,
        space.base,
        space.comfortable,
        space.loose,
        space.section,
        space.chapter,
      ];
      for (int i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]),
            reason: 'step $i breaks the ladder',);
      }
    });

    test('sits on a 4dp grid, with the two documented exceptions', () {
      // hairline is a line, not a space; both are off-grid on purpose.
      final Map<String, double> onGrid = <String, double>{
        'tight': space.tight,
        'snug': space.snug,
        'base': space.base,
        'comfortable': space.comfortable,
        'loose': space.loose,
        'section': space.section,
        'chapter': space.chapter,
        'screenGutter': space.screenGutter,
        'dockPadding': space.dockPadding,
        'thumbTarget': space.thumbTarget,
      };
      onGrid.forEach((String name, double value) {
        expect(value % 4, 0, reason: '$name ($value) is off the 4dp grid');
      });
      expect(space.hairline, 1);
      expect(space.micro, 2);
    });

    test('the thumb target meets the 48dp accessibility floor', () {
      expect(space.thumbTarget, greaterThanOrEqualTo(48));
    });

    test('every value is positive', () {
      for (final double v in <double>[
        space.hairline,
        space.micro,
        space.tight,
        space.snug,
        space.base,
        space.comfortable,
        space.loose,
        space.section,
        space.chapter,
        space.thumbTarget,
        space.screenGutter,
        space.dockPadding,
        space.radiusSubtle,
        space.radiusControl,
        space.radiusSurface,
        space.radiusCompartment,
        space.radiusPlatter,
      ]) {
        expect(v, greaterThan(0));
      }
    });
  });

  group('radii', () {
    test('a compartment is rounder than a control but softer than the tray',
        () {
      expect(space.radiusSubtle, lessThan(space.radiusControl));
      expect(space.radiusControl, lessThan(space.radiusCompartment));
      expect(space.radiusCompartment, lessThan(space.radiusSurface));
      expect(space.radiusSurface, lessThan(space.radiusPlatter));
    });

    test('helpers build the matching BorderRadius', () {
      expect(space.controlRadius, BorderRadius.circular(space.radiusControl));
      expect(space.surfaceRadius, BorderRadius.circular(space.radiusSurface));
      expect(space.compartmentRadius,
          BorderRadius.circular(space.radiusCompartment),);
      expect(space.platterRadius, BorderRadius.circular(space.radiusPlatter));
      expect(space.pillRadius, BorderRadius.circular(999));
    });
  });

  // Padding must be directional, or an RTL layout silently keeps its LTR
  // asymmetry — the single most common RTL bug there is.
  group('padding helpers are direction-aware', () {
    test('every helper returns an EdgeInsetsDirectional', () {
      expect(space.surfacePadding, isA<EdgeInsetsDirectional>());
      expect(space.gutter, isA<EdgeInsetsDirectional>());
      expect(space.chipPadding, isA<EdgeInsetsDirectional>());
    });

    test('the gutter adds no vertical padding of its own', () {
      expect(space.gutter.top, 0);
      expect(space.gutter.bottom, 0);
      expect(space.gutter.start, space.screenGutter);
      expect(space.gutter.end, space.screenGutter);
    });

    test('a directional gutter resolves mirrored under RTL', () {
      final EdgeInsets ltr = space.gutter.resolve(TextDirection.ltr);
      final EdgeInsets rtl = space.gutter.resolve(TextDirection.rtl);
      expect(ltr.left, space.screenGutter);
      expect(rtl.right, space.screenGutter);
    });
  });

  group('spacing ThemeExtension contract', () {
    test('copyWith replaces only the named value', () {
      final MawzoonSpacing tweaked = space.copyWith(screenGutter: 40);
      expect(tweaked.screenGutter, 40);
      expect(tweaked.base, space.base);
    });

    test('lerp interpolates linearly', () {
      final MawzoonSpacing other = space.copyWith(base: 20);
      expect(space.lerp(other, 0).base, space.base);
      expect(space.lerp(other, 1).base, 20);
      expect(space.lerp(other, 0.5).base, closeTo((space.base + 20) / 2, 1e-9));
    });

    test('lerp against a foreign extension returns this unchanged', () {
      expect(space.lerp(null, 0.5), same(space));
    });
  });

  group('elevation ladder', () {
    final MawzoonElevation dark = MawzoonElevation.of(Brightness.dark);
    final MawzoonElevation light = MawzoonElevation.of(Brightness.light);

    test('flush casts nothing', () {
      expect(dark.flush, isEmpty);
      expect(light.flush, isEmpty);
    });

    test('each level casts more than the one below it', () {
      for (final MawzoonElevation e in <MawzoonElevation>[dark, light]) {
        double spread(List<BoxShadow> s) => s.fold(
              0,
              (double acc, BoxShadow b) => acc + b.blurRadius,
            );
        expect(spread(e.resting), greaterThan(spread(e.flush)));
        expect(spread(e.lifted), greaterThan(spread(e.resting)));
        expect(spread(e.platter), greaterThan(spread(e.lifted)));
      }
    });

    test('the dock casts upward, because it sits on the bottom edge', () {
      for (final MawzoonElevation e in <MawzoonElevation>[dark, light]) {
        expect(e.dock, isNotEmpty);
        for (final BoxShadow s in e.dock) {
          expect(s.offset.dy, lessThan(0),
              reason: 'a downward dock shadow falls off the screen',);
        }
      }
    });

    test('every other level casts downward', () {
      for (final MawzoonElevation e in <MawzoonElevation>[dark, light]) {
        for (final List<BoxShadow> level in <List<BoxShadow>>[
          e.resting,
          e.lifted,
          e.platter,
        ]) {
          for (final BoxShadow s in level) {
            expect(s.offset.dy, greaterThanOrEqualTo(0));
          }
        }
      }
    });

    test('dark casts harder than light — a soft shadow vanishes on obsidian',
        () {
      double opacity(List<BoxShadow> s) =>
          s.fold(0, (double acc, BoxShadow b) => acc + b.color.a);
      expect(opacity(dark.platter), greaterThan(opacity(light.platter)));
      expect(opacity(dark.resting), greaterThan(opacity(light.resting)));
    });

    test('the platter shadow is reserved for the hero and is the largest', () {
      for (final MawzoonElevation e in <MawzoonElevation>[dark, light]) {
        final double platterBlur = e.platter
            .map((BoxShadow s) => s.blurRadius)
            .reduce((double a, double b) => a > b ? a : b);
        final double liftedBlur = e.lifted
            .map((BoxShadow s) => s.blurRadius)
            .reduce((double a, double b) => a > b ? a : b);
        expect(platterBlur, greaterThan(liftedBlur));
      }
    });
  });

  group('elevation ThemeExtension contract', () {
    final MawzoonElevation dark = MawzoonElevation.of(Brightness.dark);
    final MawzoonElevation light = MawzoonElevation.of(Brightness.light);

    test('copyWith replaces only the named level', () {
      final MawzoonElevation tweaked =
          dark.copyWith(resting: const <BoxShadow>[]);
      expect(tweaked.resting, isEmpty);
      expect(tweaked.platter, dark.platter);
    });

    test('lerp blends the shadow lists', () {
      expect(dark.lerp(light, 0).platter.first.color.a,
          closeTo(dark.platter.first.color.a, 1e-6),);
      expect(dark.lerp(light, 1).platter.first.color.a,
          closeTo(light.platter.first.color.a, 1e-6),);
    });

    test('lerp against a foreign extension returns this unchanged', () {
      expect(dark.lerp(null, 0.5), same(dark));
    });
  });
}
