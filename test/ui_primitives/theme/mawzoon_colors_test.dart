import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/ui_primitives/theme/mawzoon_brand.dart';
import 'package:mawzoon/ui_primitives/theme/mawzoon_colors.dart';

/// Every surface a guest can read text against.
Map<String, Color> _surfacesOf(MawzoonColors c) => <String, Color>{
      'canvas': c.canvas,
      'structure': c.structure,
      'structureElevated': c.structureElevated,
    };

void main() {
  final Map<String, MawzoonColors> palettes = <String, MawzoonColors>{
    'dark': MawzoonColors.dark(),
    'light': MawzoonColors.light(),
  };

  group('brand constants are never altered', () {
    test('the brand sheet values are exactly as published', () {
      expect(MawzoonBrand.smokedObsidian, const Color(0xFF111312));
      expect(MawzoonBrand.warmCharcoal, const Color(0xFF1C1F1D));
      expect(MawzoonBrand.warmCharcoalElevated, const Color(0xFF242826));
      expect(MawzoonBrand.roastedEmber, const Color(0xFFDE6B35));
      expect(MawzoonBrand.coldPressedOlive, const Color(0xFF5B8A65));
      expect(MawzoonBrand.warmCulinaryLinen, const Color(0xFFF8F7F3));
      expect(MawzoonBrand.softSteamedStone, const Color(0xFFEAE6DF));
      expect(MawzoonBrand.charredTerracotta, const Color(0xFFD95D39));
      expect(MawzoonBrand.warmMaize, const Color(0xFFE0A948));
      expect(MawzoonBrand.crispSage, const Color(0xFF5B8A65));
    });

    test('the dark theme uses the brand values unmodified', () {
      final MawzoonColors dark = MawzoonColors.dark();
      expect(dark.canvas, MawzoonBrand.smokedObsidian);
      expect(dark.structure, MawzoonBrand.warmCharcoal);
      expect(dark.structureElevated, MawzoonBrand.warmCharcoalElevated);
      expect(dark.ember, MawzoonBrand.roastedEmber);
      expect(dark.olive, MawzoonBrand.coldPressedOlive);
      expect(dark.protein, MawzoonBrand.charredTerracotta);
      expect(dark.carb, MawzoonBrand.warmMaize);
      expect(dark.fiber, MawzoonBrand.crispSage);
    });

    test('Crisp Sage and Cold-Pressed Olive are deliberately the same value',
        () {
      expect(MawzoonBrand.crispSage, MawzoonBrand.coldPressedOlive);
    });
  });

  group('contrast ratio maths', () {
    test('matches the WCAG reference values', () {
      expect(
        MawzoonBrand.contrastRatio(Colors.black, Colors.white),
        closeTo(21, 0.01),
      );
      expect(
        MawzoonBrand.contrastRatio(Colors.white, Colors.white),
        closeTo(1, 0.001),
      );
      // #767676 on white is the canonical 4.54:1 AA boundary example.
      expect(
        MawzoonBrand.contrastRatio(const Color(0xFF767676), Colors.white),
        closeTo(4.54, 0.02),
      );
    });

    test('is symmetric', () {
      expect(
        MawzoonBrand.contrastRatio(MawzoonBrand.roastedEmber, Colors.white),
        closeTo(
          MawzoonBrand.contrastRatio(Colors.white, MawzoonBrand.roastedEmber),
          1e-9,
        ),
      );
    });
  });

  // The palette makes a promise the eye cannot verify by itself. These tests
  // are what turn "accessible" from an intention into a property of the build.
  group('text roles clear WCAG AA on every surface they can sit on', () {
    palettes.forEach((String name, MawzoonColors c) {
      _surfacesOf(c).forEach((String surfaceName, Color surface) {
        for (final MapEntry<String, Color> role in <String, Color>{
          'ink': c.ink,
          'inkSoft': c.inkSoft,
          'inkFaint': c.inkFaint,
        }.entries) {
          test('$name: ${role.key} on $surfaceName', () {
            final double ratio =
                MawzoonBrand.contrastRatio(role.value, surface);
            expect(
              ratio,
              greaterThanOrEqualTo(MawzoonBrand.aaBodyText),
              reason: '$name ${role.key} on $surfaceName is '
                  '${ratio.toStringAsFixed(2)}:1, below AA body text',
            );
          });
        }
      });
    });
  });

  group('accents clear WCAG AA as text on the canvas', () {
    palettes.forEach((String name, MawzoonColors c) {
      test('$name: ember', () {
        final double ratio = MawzoonBrand.contrastRatio(c.ember, c.canvas);
        expect(ratio, greaterThanOrEqualTo(MawzoonBrand.aaBodyText),
            reason: '$name ember is ${ratio.toStringAsFixed(2)}:1',);
      });
      test('$name: olive', () {
        final double ratio = MawzoonBrand.contrastRatio(c.olive, c.canvas);
        expect(ratio, greaterThanOrEqualTo(MawzoonBrand.aaBodyText),
            reason: '$name olive is ${ratio.toStringAsFixed(2)}:1',);
      });
    });
  });

  group('a label on an accent fill is readable', () {
    palettes.forEach((String name, MawzoonColors c) {
      test('$name: onEmber over ember', () {
        final double ratio = MawzoonBrand.contrastRatio(c.onEmber, c.ember);
        expect(ratio, greaterThanOrEqualTo(MawzoonBrand.aaBodyText),
            reason: '$name onEmber is ${ratio.toStringAsFixed(2)}:1',);
      });
      test('$name: onOlive over olive', () {
        final double ratio = MawzoonBrand.contrastRatio(c.onOlive, c.olive);
        expect(ratio, greaterThanOrEqualTo(MawzoonBrand.aaBodyText),
            reason: '$name onOlive is ${ratio.toStringAsFixed(2)}:1',);
      });
    });
  });

  // Macro arcs, compartment borders and swatches are non-text UI marks, so the
  // bar is 3:1 — but it is still a bar, and Warm Maize on linen fails it at
  // its brand value, which is why the light theme deepens it.
  group('macro tones clear the 3:1 graphics threshold', () {
    palettes.forEach((String name, MawzoonColors c) {
      _surfacesOf(c).forEach((String surfaceName, Color surface) {
        for (final MapEntry<String, Color> tone in <String, Color>{
          'protein': c.protein,
          'carb': c.carb,
          'fiber': c.fiber,
        }.entries) {
          test('$name: ${tone.key} on $surfaceName', () {
            final double ratio =
                MawzoonBrand.contrastRatio(tone.value, surface);
            expect(
              ratio,
              greaterThanOrEqualTo(MawzoonBrand.aaLargeTextAndGraphics),
              reason: '$name ${tone.key} on $surfaceName is '
                  '${ratio.toStringAsFixed(2)}:1, below the graphics threshold',
            );
          });
        }
      });
    });

    test('the three tones are distinguishable from one another', () {
      for (final MawzoonColors c in palettes.values) {
        expect(c.protein, isNot(c.carb));
        expect(c.carb, isNot(c.fiber));
        expect(c.protein, isNot(c.fiber));
      }
    });
  });

  group('segment tones', () {
    test('map by tray position, not by dish', () {
      final MawzoonColors c = MawzoonColors.dark();
      expect(c.toneForSegmentOrdinal(0), c.protein);
      expect(c.toneForSegmentOrdinal(1), c.carb);
      expect(c.toneForSegmentOrdinal(2), c.fiber);
    });

    test('an out-of-range ordinal degrades to a neutral rather than throwing',
        () {
      final MawzoonColors c = MawzoonColors.dark();
      expect(c.toneForSegmentOrdinal(9), c.inkFaint);
      expect(c.toneForSegmentOrdinal(-1), c.inkFaint);
    });
  });

  group('bestInkOn', () {
    test('picks the higher-contrast foreground for a runtime surface', () {
      final MawzoonColors dark = MawzoonColors.dark();
      final Color onWhite = dark.bestInkOn(Colors.white);
      final Color onBlack = dark.bestInkOn(Colors.black);

      expect(
        MawzoonBrand.contrastRatio(onWhite, Colors.white),
        greaterThan(MawzoonBrand.aaBodyText),
      );
      expect(
        MawzoonBrand.contrastRatio(onBlack, Colors.black),
        greaterThan(MawzoonBrand.aaBodyText),
      );
      expect(onWhite, isNot(onBlack));
    });
  });

  group('ThemeExtension contract', () {
    test('copyWith replaces only the named role', () {
      final MawzoonColors dark = MawzoonColors.dark();
      final MawzoonColors tweaked = dark.copyWith(ember: Colors.pink);
      expect(tweaked.ember, Colors.pink);
      expect(tweaked.canvas, dark.canvas);
      expect(tweaked.brightness, dark.brightness);
    });

    test('lerp interpolates every role and flips brightness at the midpoint',
        () {
      final MawzoonColors dark = MawzoonColors.dark();
      final MawzoonColors light = MawzoonColors.light();

      expect(dark.lerp(light, 0).canvas, dark.canvas);
      expect(dark.lerp(light, 1).canvas, light.canvas);
      expect(dark.lerp(light, 0.49).brightness, Brightness.dark);
      expect(dark.lerp(light, 0.51).brightness, Brightness.light);

      final MawzoonColors mid = dark.lerp(light, 0.5);
      expect(mid.canvas, isNot(dark.canvas));
      expect(mid.canvas, isNot(light.canvas));
    });

    test('lerp against a foreign extension returns this unchanged', () {
      final MawzoonColors dark = MawzoonColors.dark();
      expect(dark.lerp(null, 0.5), same(dark));
    });
  });

  group('ColorScheme projection', () {
    palettes.forEach((String name, MawzoonColors c) {
      test('$name: carries the brand into stock Material widgets', () {
        final ColorScheme scheme = c.toColorScheme();
        expect(scheme.brightness, c.brightness);
        expect(scheme.primary, c.ember);
        expect(scheme.onPrimary, c.onEmber);
        expect(scheme.secondary, c.olive);
        expect(scheme.surface, c.canvas);
        expect(scheme.onSurface, c.ink);
        expect(scheme.outline, c.hairline);
      });

      test('$name: onError is readable on error', () {
        final ColorScheme scheme = c.toColorScheme();
        expect(
          MawzoonBrand.contrastRatio(scheme.onError, scheme.error),
          greaterThanOrEqualTo(MawzoonBrand.aaLargeTextAndGraphics),
        );
      });
    });
  });

  group('of()', () {
    test('resolves by brightness', () {
      expect(MawzoonColors.of(Brightness.dark).canvas,
          MawzoonBrand.smokedObsidian,);
      expect(MawzoonColors.of(Brightness.light).canvas,
          MawzoonBrand.warmCulinaryLinen,);
    });
  });
}
