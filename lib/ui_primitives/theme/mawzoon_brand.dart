import 'dart:math' as math;
import 'dart:ui' show Color;

/// The immutable brand constants for موزون.
///
/// These are the hexes on the brand sheet. Nothing in the app may alter them:
/// they are the identity. Where a raw brand colour cannot carry enough contrast
/// for a given role on a given ground — Roasted Ember as body text on Warm
/// Culinary Linen, for instance — the theme derives a *tuned* variant and
/// declares it explicitly in [MawzoonColors], rather than quietly bending the
/// brand value here.
abstract final class MawzoonBrand {
  // ---- 60% · Canvas -------------------------------------------------------

  /// Smoked Obsidian — the dominant ground in dark.
  static const Color smokedObsidian = Color(0xFF111312);

  /// Warm Culinary Linen — the dominant ground in light.
  static const Color warmCulinaryLinen = Color(0xFFF8F7F3);

  // ---- 30% · Structure ----------------------------------------------------

  /// Warm Charcoal — surfaces, docks and the plate platter in dark.
  static const Color warmCharcoal = Color(0xFF1C1F1D);

  /// The raised companion to [warmCharcoal].
  static const Color warmCharcoalElevated = Color(0xFF242826);

  /// Soft Steamed Stone — surfaces, docks and the plate platter in light.
  static const Color softSteamedStone = Color(0xFFEAE6DF);

  /// The raised companion to [softSteamedStone].
  static const Color softSteamedStoneElevated = Color(0xFFF2EFE9);

  // ---- 10% · Intentional accents -----------------------------------------

  /// Roasted Ember — appetite. Checkout, primary action, interactive snaps.
  static const Color roastedEmber = Color(0xFFDE6B35);

  /// Cold-Pressed Olive — equilibrium. The balance lock and macro progress.
  static const Color coldPressedOlive = Color(0xFF5B8A65);

  // ---- Macronutrient tones ------------------------------------------------

  /// Charred Terracotta — the protein compartment.
  static const Color charredTerracotta = Color(0xFFD95D39);

  /// Warm Maize — the smart-carb compartment.
  static const Color warmMaize = Color(0xFFE0A948);

  /// Crisp Sage — the vital-fibre compartment. Shares its value with
  /// [coldPressedOlive]: greens and equilibrium are the same idea here.
  static const Color crispSage = Color(0xFF5B8A65);

  // ---- Contrast -----------------------------------------------------------

  /// WCAG 2.1 relative luminance of [color], in `0.0..1.0`.
  ///
  /// Alpha is ignored: composite before measuring if the colour is translucent.
  static double relativeLuminance(Color color) {
    double channel(double c) =>
        c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// WCAG 2.1 contrast ratio between [a] and [b], from 1.0 to 21.0.
  static double contrastRatio(Color a, Color b) {
    final double la = relativeLuminance(a);
    final double lb = relativeLuminance(b);
    final double hi = math.max(la, lb);
    final double lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The minimum contrast for body text under WCAG AA.
  static const double aaBodyText = 4.5;

  /// The minimum contrast for large text and for non-text UI marks — the macro
  /// arcs, compartment borders and swatches — under WCAG AA.
  static const double aaLargeTextAndGraphics = 3.0;
}
