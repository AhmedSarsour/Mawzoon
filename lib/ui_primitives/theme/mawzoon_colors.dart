import 'package:flutter/material.dart';

import 'mawzoon_brand.dart';

/// The role-based colour palette, resolved for one [Brightness].
///
/// Widgets never reach for a brand hex. They ask for a *role* — the ink on the
/// canvas, the fill behind a primary action, the tone of the protein
/// compartment — and the theme supplies a value already checked for contrast
/// on that ground. Swapping brightness swaps every role at once, so a screen
/// cannot end up with one theme's text on the other theme's surface.
///
/// The 60-30-10 split is structural, not decorative:
/// [canvas] is the 60%, [structure] and [structureElevated] the 30%, and
/// [ember] plus [olive] the 10% that must stay scarce to keep meaning.
@immutable
final class MawzoonColors extends ThemeExtension<MawzoonColors> {
  /// Creates a palette. Prefer [MawzoonColors.dark] or [MawzoonColors.light].
  const MawzoonColors({
    required this.brightness,
    required this.canvas,
    required this.structure,
    required this.structureElevated,
    required this.hairline,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.ember,
    required this.onEmber,
    required this.olive,
    required this.onOlive,
    required this.protein,
    required this.carb,
    required this.fiber,
    required this.track,
    required this.scrim,
  });

  /// The dark palette: Smoked Obsidian ground, Warm Charcoal structure.
  ///
  /// The accents need no tuning here — Roasted Ember and Cold-Pressed Olive
  /// both clear AA against Smoked Obsidian at their brand values.
  factory MawzoonColors.dark() => const MawzoonColors(
        brightness: Brightness.dark,
        canvas: MawzoonBrand.smokedObsidian,
        structure: MawzoonBrand.warmCharcoal,
        structureElevated: MawzoonBrand.warmCharcoalElevated,
        hairline: Color(0xFF323733),
        ink: Color(0xFFECE8E0),
        inkSoft: Color(0xFFA2A79E),
        inkFaint: Color(0xFF8A9088),
        ember: MawzoonBrand.roastedEmber,
        // Obsidian on ember rather than white: the ember is bright enough in
        // dark that a white label is the lower-contrast choice, and the darker
        // label keeps the button feeling like a lit surface, not a sticker.
        onEmber: MawzoonBrand.smokedObsidian,
        olive: MawzoonBrand.coldPressedOlive,
        onOlive: MawzoonBrand.smokedObsidian,
        protein: MawzoonBrand.charredTerracotta,
        carb: MawzoonBrand.warmMaize,
        fiber: MawzoonBrand.crispSage,
        track: Color(0x1AECE8E0),
        scrim: Color(0xB3000000),
      );

  /// The light palette: Warm Culinary Linen ground, Soft Steamed Stone
  /// structure.
  ///
  /// Every accent is deepened from its brand value. Roasted Ember reaches only
  /// 3.1:1 as text on linen, and Warm Maize a fraction under 2:1 — unreadable
  /// and unusable respectively. The deepened variants keep the hue and the
  /// warmth while clearing AA; the brand values themselves are untouched in
  /// [MawzoonBrand].
  factory MawzoonColors.light() => const MawzoonColors(
        brightness: Brightness.light,
        canvas: MawzoonBrand.warmCulinaryLinen,
        structure: MawzoonBrand.softSteamedStone,
        structureElevated: MawzoonBrand.softSteamedStoneElevated,
        hairline: Color(0xFFD7D1C6),
        ink: Color(0xFF232624),
        inkSoft: Color(0xFF5E625C),
        inkFaint: Color(0xFF646863),
        ember: Color(0xFFB4501F),
        onEmber: Color(0xFFFFFFFF),
        olive: Color(0xFF3F6B4A),
        onOlive: Color(0xFFFFFFFF),
        protein: Color(0xFFB8492A),
        carb: Color(0xFF9A6C1E),
        fiber: Color(0xFF3F6B4A),
        track: Color(0x1A232624),
        scrim: Color(0x99000000),
      );

  /// The palette matching [brightness].
  factory MawzoonColors.of(Brightness brightness) =>
      brightness == Brightness.dark
          ? MawzoonColors.dark()
          : MawzoonColors.light();

  /// Which brightness this palette was resolved for.
  final Brightness brightness;

  /// 60% — the dominant ground. Scaffolds and full-bleed backgrounds.
  final Color canvas;

  /// 30% — resting surfaces: cards, carousel chips, the dock, the platter.
  final Color structure;

  /// 30% — the raised companion to [structure], for a selected or lifted
  /// surface. One step only; a third step would flatten the hierarchy.
  final Color structureElevated;

  /// The one-pixel separator. Never used as a text colour.
  final Color hairline;

  /// Primary text and icons on [canvas] or [structure].
  final Color ink;

  /// Secondary text: supporting sentences, descriptions, units.
  final Color inkSoft;

  /// Tertiary text: eyebrows, captions, disabled labels. Still clears AA —
  /// "faint" is a hierarchy position, not permission to be unreadable.
  final Color inkFaint;

  /// 10% — appetite. Checkout, the primary call to action, interactive snaps.
  final Color ember;

  /// Text and icons placed on top of [ember].
  final Color onEmber;

  /// 10% — equilibrium. The balance lock and macro progress.
  final Color olive;

  /// Text and icons placed on top of [olive].
  final Color onOlive;

  /// The protein compartment and its arc.
  final Color protein;

  /// The smart-carb compartment and its arc.
  final Color carb;

  /// The vital-fibre compartment and its arc.
  final Color fiber;

  /// The unfilled remainder behind a macro arc or progress mark.
  final Color track;

  /// The wash behind a modal sheet.
  final Color scrim;

  /// The tone for a plate compartment, by its position on the tray.
  ///
  /// Takes the segment's ordinal rather than the enum so that `ui_primitives`
  /// keeps no dependency on the menu domain — the canvas is handed an index,
  /// not a dish.
  Color toneForSegmentOrdinal(int ordinal) => switch (ordinal) {
        0 => protein,
        1 => carb,
        2 => fiber,
        _ => inkFaint,
      };

  /// Whichever of [ink] or its inverse reads better on [background].
  ///
  /// For a surface whose colour is not known until runtime — a dish image's
  /// average tone, a tinted compartment — rather than a guessed literal.
  Color bestInkOn(Color background) {
    final Color inverse =
        brightness == Brightness.dark ? MawzoonBrand.smokedObsidian : Colors.white;
    return MawzoonBrand.contrastRatio(ink, background) >=
            MawzoonBrand.contrastRatio(inverse, background)
        ? ink
        : inverse;
  }

  @override
  MawzoonColors copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? structure,
    Color? structureElevated,
    Color? hairline,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? ember,
    Color? onEmber,
    Color? olive,
    Color? onOlive,
    Color? protein,
    Color? carb,
    Color? fiber,
    Color? track,
    Color? scrim,
  }) =>
      MawzoonColors(
        brightness: brightness ?? this.brightness,
        canvas: canvas ?? this.canvas,
        structure: structure ?? this.structure,
        structureElevated: structureElevated ?? this.structureElevated,
        hairline: hairline ?? this.hairline,
        ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft,
        inkFaint: inkFaint ?? this.inkFaint,
        ember: ember ?? this.ember,
        onEmber: onEmber ?? this.onEmber,
        olive: olive ?? this.olive,
        onOlive: onOlive ?? this.onOlive,
        protein: protein ?? this.protein,
        carb: carb ?? this.carb,
        fiber: fiber ?? this.fiber,
        track: track ?? this.track,
        scrim: scrim ?? this.scrim,
      );

  @override
  MawzoonColors lerp(ThemeExtension<MawzoonColors>? other, double t) {
    if (other is! MawzoonColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return MawzoonColors(
      // Brightness is categorical; it flips at the midpoint rather than
      // blending into a meaningless in-between.
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      structure: c(structure, other.structure),
      structureElevated: c(structureElevated, other.structureElevated),
      hairline: c(hairline, other.hairline),
      ink: c(ink, other.ink),
      inkSoft: c(inkSoft, other.inkSoft),
      inkFaint: c(inkFaint, other.inkFaint),
      ember: c(ember, other.ember),
      onEmber: c(onEmber, other.onEmber),
      olive: c(olive, other.olive),
      onOlive: c(onOlive, other.onOlive),
      protein: c(protein, other.protein),
      carb: c(carb, other.carb),
      fiber: c(fiber, other.fiber),
      track: c(track, other.track),
      scrim: c(scrim, other.scrim),
    );
  }

  /// A Material [ColorScheme] derived from these roles, so that stock
  /// Material widgets inherit the brand instead of falling back to Material
  /// defaults the brand sheet never approved.
  ColorScheme toColorScheme() => ColorScheme(
        brightness: brightness,
        primary: ember,
        onPrimary: onEmber,
        primaryContainer: structureElevated,
        onPrimaryContainer: ink,
        secondary: olive,
        onSecondary: onOlive,
        secondaryContainer: structureElevated,
        onSecondaryContainer: ink,
        tertiary: carb,
        onTertiary: brightness == Brightness.dark
            ? MawzoonBrand.smokedObsidian
            : Colors.white,
        error: protein,
        onError: brightness == Brightness.dark
            ? MawzoonBrand.smokedObsidian
            : Colors.white,
        surface: canvas,
        onSurface: ink,
        surfaceContainerLowest: canvas,
        surfaceContainerLow: structure,
        surfaceContainer: structure,
        surfaceContainerHigh: structureElevated,
        surfaceContainerHighest: structureElevated,
        onSurfaceVariant: inkSoft,
        outline: hairline,
        outlineVariant: hairline,
        scrim: scrim,
        shadow: const Color(0xFF000000),
        inverseSurface: ink,
        onInverseSurface: canvas,
        inversePrimary: ember,
      );

  @override
  String toString() => 'MawzoonColors(${brightness.name})';
}
