import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/ui_primitives/theme/mawzoon_fonts.dart';
import 'package:mawzoon/ui_primitives/theme/mawzoon_typography.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

MawzoonTypography _arabic() =>
    MawzoonTypography.forLanguage(AppLanguage.arabic, fonts: _fonts);
MawzoonTypography _english() =>
    MawzoonTypography.forLanguage(AppLanguage.english, fonts: _fonts);

/// Every script-sensitive role in the scale.
List<TextStyle> _scriptedRoles(MawzoonTypography t) => <TextStyle>[
      t.wordmark,
      t.display,
      t.sectionTitle,
      t.dishName,
      t.dishDescription,
      t.body,
      t.capsuleLabel,
      t.buttonLabel,
      t.tagLabel,
      t.eyebrow,
      t.caption,
    ];

void main() {
  group('script selection', () {
    test('Arabic copy is set in the Arabic face', () {
      for (final TextStyle s in _scriptedRoles(_arabic())) {
        expect(s.fontFamily, _fonts.arabicFamily);
      }
    });

    test('English copy is set in the Latin face', () {
      for (final TextStyle s in _scriptedRoles(_english())) {
        expect(s.fontFamily, _fonts.latinFamily);
      }
    });

    test('the Arabic fallback stack contains no Latin-only face', () {
      // A Latin fallback would drop harakat silently rather than render a
      // tofu box, which is the worst possible failure mode: wrong, but
      // plausible-looking. Matched against an allowlist rather than by name —
      // Geeza Pro is a perfectly good Arabic face and says so nowhere in its
      // name.
      const Set<String> arabicCapable = <String>{
        'SF Arabic',
        'Geeza Pro',
        'Noto Naskh Arabic',
        'Noto Sans Arabic',
        'IBM Plex Sans Arabic',
        'Cairo',
      };
      final List<String> fallback =
          _arabic().body.fontFamilyFallback ?? <String>[];
      expect(fallback, isNotEmpty);
      for (final String family in fallback) {
        expect(arabicCapable, contains(family),
            reason: '$family is not a known Arabic-capable face',);
      }
    });

    test('direction follows the language', () {
      expect(_arabic().textDirection, TextDirection.rtl);
      expect(_arabic().isRightToLeft, isTrue);
      expect(_english().textDirection, TextDirection.ltr);
      expect(_english().isRightToLeft, isFalse);
    });
  });

  group('Arabic line height', () {
    test('running copy sits at the 1.8 called for on the brand sheet', () {
      final MawzoonTypography ar = _arabic();
      expect(MawzoonTypography.arabicBodyHeight, 1.8);
      expect(ar.body.height, MawzoonTypography.arabicBodyHeight);
      expect(ar.dishDescription.height, MawzoonTypography.arabicBodyHeight);
      expect(ar.caption.height, MawzoonTypography.arabicBodyHeight);
    });

    test('every Arabic role is generous enough for stacked marks', () {
      for (final TextStyle s in _scriptedRoles(_arabic())) {
        expect(s.height, isNotNull);
        expect(s.height!, greaterThanOrEqualTo(1.5),
            reason: 'an Arabic line box under 1.5 clips harakat',);
      }
    });

    test('Latin is set tighter — 1.8 would read as a legal disclaimer', () {
      final MawzoonTypography en = _english();
      expect(en.body.height!, lessThan(MawzoonTypography.arabicBodyHeight));
      expect(en.display.height!, lessThan(1.3));
    });

    test('Arabic leading is distributed evenly, not all below the baseline',
        () {
      for (final TextStyle s in _scriptedRoles(_arabic())) {
        expect(s.leadingDistribution, TextLeadingDistribution.even);
      }
    });
  });

  // Letter-spacing a cursive script breaks the joins between letters and turns
  // a word into disconnected shapes. This is the single most common way an
  // Arabic UI is ruined by a designer working in English.
  group('Arabic is never letter-spaced', () {
    test('no Arabic role carries tracking', () {
      for (final TextStyle s in _scriptedRoles(_arabic())) {
        expect(s.letterSpacing ?? 0, 0,
            reason: 'letter-spacing breaks Arabic letter joining',);
      }
    });

    test('the Latin eyebrow does carry tracking, as small caps should', () {
      expect(_english().eyebrow.letterSpacing, greaterThan(0));
    });

    test('the Arabic eyebrow is differentiated by weight and size instead', () {
      final MawzoonTypography ar = _arabic();
      expect(ar.eyebrow.letterSpacing ?? 0, 0);
      expect(ar.eyebrow.fontSize!, lessThan(ar.body.fontSize!));
    });
  });

  group('numeric figures', () {
    test('always take the Latin face, in both languages', () {
      for (final MawzoonTypography t in <MawzoonTypography>[
        _arabic(),
        _english(),
      ]) {
        expect(t.macroFigure.fontFamily, _fonts.latinFamily);
        expect(t.macroUnit.fontFamily, _fonts.latinFamily);
      }
    });

    test('are tabular, so a changing calorie count does not shuffle digits',
        () {
      for (final MawzoonTypography t in <MawzoonTypography>[
        _arabic(),
        _english(),
      ]) {
        expect(
          t.macroFigure.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
        expect(
          t.macroUnit.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });

    test('the figure dominates its unit', () {
      final MawzoonTypography t = _arabic();
      expect(t.macroFigure.fontSize!, greaterThan(t.macroUnit.fontSize! * 2));
    });
  });

  // The strut is the piece that actually prevents clipping. A TextStyle alone
  // cannot, because without it the line box is measured from whichever glyphs
  // happen to land on that line.
  group('strut', () {
    test('Arabic forces a uniform line box', () {
      final MawzoonTypography ar = _arabic();
      final StrutStyle strut = ar.strutFor(ar.body);

      expect(strut.forceStrutHeight, isTrue);
      expect(strut.height, ar.body.height);
      expect(strut.fontSize, ar.body.fontSize);
      expect(strut.fontFamily, ar.body.fontFamily);
      expect(strut.leading, MawzoonTypography.arabicStrutLeading);
      expect(strut.leading!, greaterThan(0));
    });

    test('Latin is left to its natural strut', () {
      // Forcing a 1.1 display line box would push descenders into the line
      // below, so Latin opts out of forcing while keeping the metrics.
      final MawzoonTypography en = _english();
      final StrutStyle strut = en.strutFor(en.display);

      expect(strut.forceStrutHeight, isFalse);
      expect(strut.leading, 0);
      expect(strut.height, en.display.height);
    });

    test('carries the fallback stack, or the strut measures the wrong face',
        () {
      final MawzoonTypography ar = _arabic();
      expect(
        ar.strutFor(ar.dishName).fontFamilyFallback,
        ar.dishName.fontFamilyFallback,
      );
    });

    test('a strut for an arbitrary style still follows the script rule', () {
      const TextStyle custom = TextStyle(fontSize: 22, height: 2.0);
      expect(_arabic().strutFor(custom).forceStrutHeight, isTrue);
      expect(_english().strutFor(custom).forceStrutHeight, isFalse);
      expect(_arabic().strutFor(custom).fontSize, 22);
    });

    test('height behaviour keeps the first ascent and last descent', () {
      final TextHeightBehavior b = _arabic().heightBehavior;
      expect(b.applyHeightToFirstAscent, isTrue);
      expect(b.applyHeightToLastDescent, isTrue);
      expect(b.leadingDistribution, TextLeadingDistribution.even);
    });
  });

  group('scale sanity', () {
    test('every role declares a size and a weight', () {
      for (final MawzoonTypography t in <MawzoonTypography>[
        _arabic(),
        _english(),
      ]) {
        for (final TextStyle s in <TextStyle>[
          ..._scriptedRoles(t),
          t.macroFigure,
          t.macroUnit,
        ]) {
          expect(s.fontSize, isNotNull);
          expect(s.fontSize!, greaterThan(0));
          expect(s.fontWeight, isNotNull);
        }
      }
    });

    test('the hierarchy is monotonic where it should be', () {
      for (final MawzoonTypography t in <MawzoonTypography>[
        _arabic(),
        _english(),
      ]) {
        expect(t.display.fontSize!, greaterThan(t.sectionTitle.fontSize!));
        expect(t.sectionTitle.fontSize!, greaterThanOrEqualTo(t.dishName.fontSize!));
        expect(t.dishName.fontSize!, greaterThan(t.tagLabel.fontSize!));
        expect(t.caption.fontSize!, lessThan(t.body.fontSize!));
      }
    });

    test('Arabic runs a little larger than Latin at body size', () {
      // The same nominal size reads smaller in Arabic; matching optically
      // rather than numerically is the point.
      expect(_arabic().body.fontSize!, greaterThan(_english().body.fontSize!));
    });

    test('Arabic headings stay lighter than Latin ones', () {
      // An 800-weight Arabic heading turns to mud where the letters join.
      expect(
        _arabic().display.fontWeight!.value,
        lessThan(_english().display.fontWeight!.value),
      );
    });
  });

  group('TextTheme projection', () {
    test('fills every slot stock Material widgets read', () {
      final TextTheme theme = _arabic().toTextTheme();
      expect(theme.displayLarge, isNotNull);
      expect(theme.headlineMedium, isNotNull);
      expect(theme.titleLarge, isNotNull);
      expect(theme.bodyMedium, isNotNull);
      expect(theme.labelLarge, isNotNull);
      expect(theme.labelSmall, isNotNull);
    });

    test('carries the Arabic face into Material slots', () {
      expect(_arabic().toTextTheme().bodyMedium!.fontFamily,
          _fonts.arabicFamily,);
    });
  });

  group('ThemeExtension contract', () {
    test('copyWith replaces only the named role', () {
      final MawzoonTypography ar = _arabic();
      final MawzoonTypography tweaked =
          ar.copyWith(body: const TextStyle(fontSize: 99));
      expect(tweaked.body.fontSize, 99);
      expect(tweaked.dishName, ar.dishName);
      expect(tweaked.language, ar.language);
    });

    test('lerp flips script at the midpoint instead of smearing two faces', () {
      final MawzoonTypography ar = _arabic();
      final MawzoonTypography en = _english();
      expect(ar.lerp(en, 0.49).language, AppLanguage.arabic);
      expect(ar.lerp(en, 0.51).language, AppLanguage.english);
    });

    test('lerp interpolates sizes', () {
      final MawzoonTypography ar = _arabic();
      final MawzoonTypography en = _english();
      final double mid = ar.lerp(en, 0.5).body.fontSize!;
      expect(mid, closeTo((ar.body.fontSize! + en.body.fontSize!) / 2, 1e-6));
    });

    test('lerp against a foreign extension returns this unchanged', () {
      final MawzoonTypography ar = _arabic();
      expect(ar.lerp(null, 0.5), same(ar));
    });
  });
}
