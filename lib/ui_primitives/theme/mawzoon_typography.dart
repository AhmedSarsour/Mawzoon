import 'package:flutter/material.dart';

import '../../core/localization/localized_text.dart';
import 'mawzoon_fonts.dart';

/// The bilingual type scale.
///
/// Two scripts with genuinely different needs, resolved once per language
/// rather than patched per widget:
///
///  * **Arabic** is cursive and stacks diacritics above and below the base
///    line. It needs a line box near [arabicBodyHeight] and, critically, it
///    must never be letter-spaced — spacing a cursive script breaks the joins
///    between letters and renders the word as disconnected shapes. Arabic also
///    has no letter case, so uppercasing is meaningless.
///  * **Latin** sets tighter and takes letter-spacing and small-caps eyebrows
///    happily. At Arabic's 1.8 it would look like a legal disclaimer.
///
/// Numeric figures are the exception to the script split: they are always set
/// in the Latin face with [FontFeature.tabularFigures], in both languages, so
/// that a column of calorie counts lines up and a changing figure does not
/// shuffle the digits beside it.
@immutable
final class MawzoonTypography extends ThemeExtension<MawzoonTypography> {
  /// Creates a type scale. Prefer [MawzoonTypography.forLanguage].
  const MawzoonTypography({
    required this.language,
    required this.wordmark,
    required this.display,
    required this.sectionTitle,
    required this.dishName,
    required this.dishDescription,
    required this.body,
    required this.macroFigure,
    required this.macroUnit,
    required this.capsuleLabel,
    required this.buttonLabel,
    required this.tagLabel,
    required this.eyebrow,
    required this.caption,
  });

  /// Builds the scale for [language].
  ///
  /// [fonts] defaults to Google Fonts; pass [BundledMawzoonFonts] for an
  /// offline build or a test.
  factory MawzoonTypography.forLanguage(
    AppLanguage language, {
    MawzoonFonts fonts = const GoogleMawzoonFonts(),
  }) {
    final bool ar = language == AppLanguage.arabic;

    /// Applies the correct face for [language], and guards the two rules that
    /// are easy to break by accident: Arabic is never letter-spaced, and
    /// Arabic leading is distributed evenly so harakat get room above rather
    /// than all the slack landing below the baseline.
    TextStyle scripted({
      required double size,
      required FontWeight weight,
      required double height,
      double letterSpacing = 0,
    }) {
      final TextStyle base = TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: ar ? 0 : letterSpacing,
        leadingDistribution:
            ar ? TextLeadingDistribution.even : TextLeadingDistribution.proportional,
      );
      return ar ? fonts.arabic(base) : fonts.latin(base);
    }

    /// Figures always take the Latin face, whatever the UI language.
    TextStyle numeric({
      required double size,
      required FontWeight weight,
      required double height,
      double letterSpacing = 0,
    }) =>
        fonts.latin(
          TextStyle(
            fontSize: size,
            fontWeight: weight,
            height: height,
            letterSpacing: letterSpacing,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        );

    return MawzoonTypography(
      language: language,
      wordmark: scripted(
        size: ar ? 26 : 24,
        weight: ar ? FontWeight.w600 : FontWeight.w800,
        height: ar ? arabicDisplayHeight : 1.15,
        letterSpacing: -0.4,
      ),
      display: scripted(
        size: ar ? 28 : 30,
        weight: ar ? FontWeight.w600 : FontWeight.w800,
        height: ar ? arabicDisplayHeight : 1.1,
        letterSpacing: -0.6,
      ),
      sectionTitle: scripted(
        size: ar ? 16 : 15,
        weight: ar ? FontWeight.w600 : FontWeight.w700,
        height: ar ? arabicTitleHeight : 1.3,
      ),
      dishName: scripted(
        size: ar ? 15 : 14,
        weight: ar ? FontWeight.w600 : FontWeight.w600,
        height: ar ? arabicTitleHeight : 1.35,
      ),
      dishDescription: scripted(
        size: ar ? 13.5 : 12.5,
        weight: FontWeight.w400,
        height: ar ? arabicBodyHeight : 1.5,
      ),
      body: scripted(
        size: ar ? 15 : 14,
        weight: FontWeight.w400,
        height: ar ? arabicBodyHeight : 1.5,
      ),
      macroFigure: numeric(
        size: 28,
        weight: FontWeight.w800,
        height: 1.0,
        letterSpacing: -0.6,
      ),
      macroUnit: numeric(
        size: 10,
        weight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0.7,
      ),
      capsuleLabel: scripted(
        size: ar ? 13.5 : 12.5,
        weight: ar ? FontWeight.w500 : FontWeight.w600,
        height: ar ? arabicLabelHeight : 1.25,
      ),
      buttonLabel: scripted(
        size: ar ? 15 : 14,
        weight: ar ? FontWeight.w600 : FontWeight.w700,
        height: ar ? arabicLabelHeight : 1.2,
        letterSpacing: 0.1,
      ),
      tagLabel: scripted(
        size: ar ? 11 : 10,
        weight: ar ? FontWeight.w500 : FontWeight.w700,
        height: ar ? arabicLabelHeight : 1.3,
        letterSpacing: 0.5,
      ),
      eyebrow: scripted(
        size: ar ? 11 : 9.5,
        weight: ar ? FontWeight.w500 : FontWeight.w700,
        height: ar ? arabicLabelHeight : 1.3,
        letterSpacing: 1.5,
      ),
      caption: scripted(
        size: ar ? 12 : 11,
        weight: FontWeight.w500,
        height: ar ? arabicBodyHeight : 1.4,
      ),
    );
  }

  /// Arabic running copy. The figure from the brand sheet, and the reason
  /// harakat on a fatha-heavy dish name do not collide with the line above.
  static const double arabicBodyHeight = 1.8;

  /// Arabic headings and dish names.
  static const double arabicTitleHeight = 1.7;

  /// Arabic single-line labels, where wrapping is not expected but the
  /// diacritics still need vertical room.
  static const double arabicLabelHeight = 1.6;

  /// Arabic at display sizes, where 1.8 would tear the wordmark apart.
  /// Still generous in absolute terms: 1.5 of 28pt is a 42pt line box.
  static const double arabicDisplayHeight = 1.5;

  /// Extra room, as a fraction of font size, added to the Arabic strut for
  /// stacked marks — a shadda over a damma is the tallest thing Arabic sets.
  static const double arabicStrutLeading = 0.1;

  /// The language this scale was resolved for.
  final AppLanguage language;

  /// موزون itself, in the masthead.
  final TextStyle wordmark;

  /// The largest text on a screen.
  final TextStyle display;

  /// A carousel or section heading.
  final TextStyle sectionTitle;

  /// A dish name on a chip or in the plate line.
  final TextStyle dishName;

  /// The one appetising sentence under a dish name.
  final TextStyle dishDescription;

  /// Running copy.
  final TextStyle body;

  /// The calorie figure in the macro capsule. Latin face, tabular.
  final TextStyle macroFigure;

  /// The unit beside a figure — `kcal`, `g`. Latin face, tabular.
  final TextStyle macroUnit;

  /// A label inside the persistent macro capsule.
  final TextStyle capsuleLabel;

  /// The label on a button.
  final TextStyle buttonLabel;

  /// A dietary tag chip.
  final TextStyle tagLabel;

  /// A small label above a block. Letter-spaced in Latin, never in Arabic.
  final TextStyle eyebrow;

  /// The smallest supporting text.
  final TextStyle caption;

  /// Whether this scale is set right-to-left.
  bool get isRightToLeft => language.isRightToLeft;

  /// The direction text in this scale flows.
  TextDirection get textDirection =>
      isRightToLeft ? TextDirection.rtl : TextDirection.ltr;

  /// The strut that guarantees [style] a line box tall enough for its script.
  ///
  /// This is the piece that actually stops diacritic clipping, and it only
  /// works if it reaches the `Text` widget — a `TextStyle` alone cannot fix
  /// it, because without a strut the line box is measured from the glyphs
  /// that happen to be on that line. A dish name whose first line carries a
  /// shadda and whose second does not would otherwise render with two
  /// different line heights.
  ///
  /// [MawzoonText] applies this automatically; use it directly only when
  /// building a `Text.rich` or a `TextPainter` by hand.
  StrutStyle strutFor(TextStyle style) => StrutStyle(
        fontFamily: style.fontFamily,
        fontFamilyFallback: style.fontFamilyFallback,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        height: style.height,
        leading: isRightToLeft ? arabicStrutLeading : 0,
        // Forced only for Arabic. Latin is left to its natural strut: forcing
        // a 1.1 display line box would push descenders into the line below.
        forceStrutHeight: isRightToLeft,
        leadingDistribution: style.leadingDistribution,
      );

  /// Height behaviour that keeps the first line's ascent and the last line's
  /// descent intact, so a single-line Arabic label is not trimmed flush
  /// against its container.
  TextHeightBehavior get heightBehavior => const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Maps this scale onto Material's [TextTheme] so that stock widgets — a
  /// `SnackBar`, a `Dialog`, a `MenuAnchor` — inherit it rather than falling
  /// back to Roboto.
  TextTheme toTextTheme() => TextTheme(
        displayLarge: display,
        displayMedium: display,
        displaySmall: wordmark,
        headlineLarge: wordmark,
        headlineMedium: sectionTitle,
        headlineSmall: sectionTitle,
        titleLarge: sectionTitle,
        titleMedium: dishName,
        titleSmall: capsuleLabel,
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: dishDescription,
        labelLarge: buttonLabel,
        labelMedium: capsuleLabel,
        labelSmall: tagLabel,
      );

  @override
  MawzoonTypography copyWith({
    AppLanguage? language,
    TextStyle? wordmark,
    TextStyle? display,
    TextStyle? sectionTitle,
    TextStyle? dishName,
    TextStyle? dishDescription,
    TextStyle? body,
    TextStyle? macroFigure,
    TextStyle? macroUnit,
    TextStyle? capsuleLabel,
    TextStyle? buttonLabel,
    TextStyle? tagLabel,
    TextStyle? eyebrow,
    TextStyle? caption,
  }) =>
      MawzoonTypography(
        language: language ?? this.language,
        wordmark: wordmark ?? this.wordmark,
        display: display ?? this.display,
        sectionTitle: sectionTitle ?? this.sectionTitle,
        dishName: dishName ?? this.dishName,
        dishDescription: dishDescription ?? this.dishDescription,
        body: body ?? this.body,
        macroFigure: macroFigure ?? this.macroFigure,
        macroUnit: macroUnit ?? this.macroUnit,
        capsuleLabel: capsuleLabel ?? this.capsuleLabel,
        buttonLabel: buttonLabel ?? this.buttonLabel,
        tagLabel: tagLabel ?? this.tagLabel,
        eyebrow: eyebrow ?? this.eyebrow,
        caption: caption ?? this.caption,
      );

  @override
  MawzoonTypography lerp(ThemeExtension<MawzoonTypography>? other, double t) {
    if (other is! MawzoonTypography) return this;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return MawzoonTypography(
      // Script is categorical. Half-way between two typefaces is not a
      // typeface, so the scale flips rather than smearing.
      language: t < 0.5 ? language : other.language,
      wordmark: s(wordmark, other.wordmark),
      display: s(display, other.display),
      sectionTitle: s(sectionTitle, other.sectionTitle),
      dishName: s(dishName, other.dishName),
      dishDescription: s(dishDescription, other.dishDescription),
      body: s(body, other.body),
      macroFigure: s(macroFigure, other.macroFigure),
      macroUnit: s(macroUnit, other.macroUnit),
      capsuleLabel: s(capsuleLabel, other.capsuleLabel),
      buttonLabel: s(buttonLabel, other.buttonLabel),
      tagLabel: s(tagLabel, other.tagLabel),
      eyebrow: s(eyebrow, other.eyebrow),
      caption: s(caption, other.caption),
    );
  }

  @override
  String toString() => 'MawzoonTypography(${language.code})';
}
