import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/localized_text.dart';
import 'mawzoon_colors.dart';
import 'mawzoon_elevation.dart';
import 'mawzoon_fonts.dart';
import 'mawzoon_spacing.dart';
import 'mawzoon_typography.dart';

/// Assembles the Mawzoon [ThemeData].
///
/// Every token set is attached as a [ThemeExtension], so a widget reads roles
/// and scales through the theme rather than importing a palette directly. That
/// is what makes the light/dark and Arabic/English swaps total: nothing can
/// hold a stale reference to the other configuration.
///
/// Material components are restyled rather than left at their defaults. An
/// unstyled `SnackBar` or `Dialog` arriving in Roboto on a Material-purple
/// surface would undo the whole palette the moment an error appears.
abstract final class AppTheme {
  /// The dark theme — Smoked Obsidian. The app's primary appearance.
  static ThemeData dark({
    AppLanguage language = AppLanguage.arabic,
    MawzoonFonts fonts = const GoogleMawzoonFonts(),
  }) =>
      _build(
        colors: MawzoonColors.dark(),
        language: language,
        fonts: fonts,
      );

  /// The light theme — Warm Culinary Linen.
  static ThemeData light({
    AppLanguage language = AppLanguage.arabic,
    MawzoonFonts fonts = const GoogleMawzoonFonts(),
  }) =>
      _build(
        colors: MawzoonColors.light(),
        language: language,
        fonts: fonts,
      );

  /// The theme for [brightness].
  static ThemeData of(
    Brightness brightness, {
    AppLanguage language = AppLanguage.arabic,
    MawzoonFonts fonts = const GoogleMawzoonFonts(),
  }) =>
      brightness == Brightness.dark
          ? dark(language: language, fonts: fonts)
          : light(language: language, fonts: fonts);

  static ThemeData _build({
    required MawzoonColors colors,
    required AppLanguage language,
    required MawzoonFonts fonts,
  }) {
    final MawzoonTypography type =
        MawzoonTypography.forLanguage(language, fonts: fonts);
    const MawzoonSpacing space = MawzoonSpacing.standard();
    final MawzoonElevation elevation = MawzoonElevation.of(colors.brightness);
    final ColorScheme scheme = colors.toColorScheme();
    final TextTheme textTheme = type.toTextTheme().apply(
          bodyColor: colors.ink,
          displayColor: colors.ink,
          decorationColor: colors.ink,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerColor: colors.hairline,
      shadowColor: const Color(0xFF000000),
      // Material's surface tint lightens a raised surface toward the primary
      // hue. On Smoked Obsidian that reads as an ember-tinted fog across every
      // card, so it is switched off and depth is carried by MawzoonElevation.
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[
        colors,
        type,
        space,
        elevation,
      ],

      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: type.sectionTitle.copyWith(color: colors.ink),
        systemOverlayStyle: colors.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: colors.structure,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: space.surfaceRadius,
          side: BorderSide(color: colors.hairline, width: space.hairline),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: space.hairline,
        space: space.hairline,
      ),

      iconTheme: IconThemeData(color: colors.ink, size: 20),
      primaryIconTheme: IconThemeData(color: colors.ink, size: 20),

      // Checkout and every other primary action. Ember fill, never an outline:
      // the one appetite colour in the app should look like a thing you press.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? colors.structure
                  : colors.ember,),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? colors.inkFaint
                  : colors.onEmber,),
          overlayColor: WidgetStatePropertyAll<Color>(
            colors.onEmber.withValues(alpha: 0.10),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(type.buttonLabel),
          minimumSize: WidgetStatePropertyAll<Size>(
            Size(space.thumbTarget, space.thumbTarget),
          ),
          padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsetsDirectional.symmetric(
              horizontal: space.loose,
              vertical: space.base,
            ),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: space.pillRadius),
          ),
          elevation: const WidgetStatePropertyAll<double>(0),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(colors.ember),
          textStyle: WidgetStatePropertyAll<TextStyle>(type.buttonLabel),
          minimumSize: WidgetStatePropertyAll<Size>(
            Size(space.thumbTarget, space.thumbTarget),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: space.controlRadius),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(colors.ink),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: colors.hairline, width: space.hairline),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(type.buttonLabel),
          minimumSize: WidgetStatePropertyAll<Size>(
            Size(space.thumbTarget, space.thumbTarget),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: space.pillRadius),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colors.structure,
        selectedColor: colors.structureElevated,
        disabledColor: colors.structure,
        surfaceTintColor: Colors.transparent,
        labelStyle: type.tagLabel.copyWith(color: colors.inkSoft),
        secondaryLabelStyle: type.tagLabel.copyWith(color: colors.ink),
        side: BorderSide(color: colors.hairline, width: space.hairline),
        shape: RoundedRectangleBorder(borderRadius: space.controlRadius),
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: space.snug,
          vertical: space.tight,
        ),
        showCheckmark: false,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.structure,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: colors.scrim,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: colors.inkFaint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(space.radiusPlatter),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colors.structureElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: type.sectionTitle.copyWith(color: colors.ink),
        contentTextStyle: type.body.copyWith(color: colors.inkSoft),
        shape: RoundedRectangleBorder(borderRadius: space.surfaceRadius),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.structureElevated,
        contentTextStyle: type.body.copyWith(color: colors.ink),
        actionTextColor: colors.ember,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: space.controlRadius),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.structureElevated,
          borderRadius: space.controlRadius,
          border: Border.all(color: colors.hairline, width: space.hairline),
        ),
        textStyle: type.caption.copyWith(color: colors.ink),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: colors.ember,
        inactiveTrackColor: colors.track,
        thumbColor: colors.ember,
        overlayColor: colors.ember.withValues(alpha: 0.12),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.olive,
        linearTrackColor: colors.track,
        circularTrackColor: colors.track,
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.ember,
        selectionColor: colors.ember.withValues(alpha: 0.26),
        selectionHandleColor: colors.ember,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(colors.track),
        thickness: const WidgetStatePropertyAll<double>(3),
        radius: const Radius.circular(3),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
