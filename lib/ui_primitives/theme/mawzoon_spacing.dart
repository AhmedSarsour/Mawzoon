import 'package:flutter/material.dart';

/// The spacing and radius scale.
///
/// Named by *purpose*, not by size. A t-shirt scale (`sm`, `md`, `lg`) forces
/// every reader to hold a lookup table in their head and invites the next
/// person to add `mdPlus`; a purposeful name says where the value belongs and
/// makes a wrong choice legible in review.
///
/// The underlying rhythm is a 4dp grid. Two values break it deliberately and
/// say so: [hairline] is a physical one-pixel rule, and [thumbTarget] is the
/// 48dp accessibility floor for anything a finger lands on.
@immutable
final class MawzoonSpacing extends ThemeExtension<MawzoonSpacing> {
  /// Creates a spacing scale. Prefer [MawzoonSpacing.standard].
  const MawzoonSpacing({
    required this.hairline,
    required this.micro,
    required this.tight,
    required this.snug,
    required this.base,
    required this.comfortable,
    required this.loose,
    required this.section,
    required this.chapter,
    required this.thumbTarget,
    required this.screenGutter,
    required this.dockPadding,
    required this.radiusSubtle,
    required this.radiusControl,
    required this.radiusSurface,
    required this.radiusCompartment,
    required this.radiusPlatter,
  });

  /// The scale the app ships with.
  const MawzoonSpacing.standard()
      : hairline = 1,
        micro = 2,
        tight = 4,
        snug = 8,
        base = 12,
        comfortable = 16,
        loose = 24,
        section = 32,
        chapter = 48,
        thumbTarget = 48,
        screenGutter = 16,
        dockPadding = 12,
        radiusSubtle = 6,
        radiusControl = 12,
        radiusSurface = 18,
        radiusCompartment = 14,
        radiusPlatter = 26;

  /// A one-pixel rule. Off-grid on purpose — it is a line, not a space.
  final double hairline;

  /// 2dp. The gap inside a segmented control's track.
  final double micro;

  /// 4dp. Between a label and the figure it labels.
  final double tight;

  /// 8dp. Between siblings in a row: chips, swatches, macro columns.
  final double snug;

  /// 12dp. Inner padding of a chip or a compact card.
  final double base;

  /// 16dp. Inner padding of a full-width surface; the screen gutter.
  final double comfortable;

  /// 24dp. Between a heading and its content.
  final double loose;

  /// 32dp. Between one section of a screen and the next.
  final double section;

  /// 48dp. Around the hero platter, and before a closing footnote.
  final double chapter;

  /// 48dp. The minimum edge of anything tappable. Never shrink this to fit a
  /// layout — move the layout.
  final double thumbTarget;

  /// The side gutter held at every width, so nothing ever touches the bezel.
  final double screenGutter;

  /// Inner padding of the bottom dock, before the safe-area inset is added.
  final double dockPadding;

  /// 6dp. Tags and swatches.
  final double radiusSubtle;

  /// 12dp. Buttons, chips, segmented controls.
  final double radiusControl;

  /// 18dp. Cards, sheets and the dock.
  final double radiusSurface;

  /// 14dp. A single compartment well inside the platter.
  final double radiusCompartment;

  /// 26dp. The platter's own silhouette — the elongated tray that the whole
  /// tri-partition model is drawn from.
  final double radiusPlatter;

  /// Symmetric padding of [comfortable] on every side.
  EdgeInsetsDirectional get surfacePadding =>
      EdgeInsetsDirectional.all(comfortable);

  /// A screen's horizontal gutter, with no vertical padding of its own.
  EdgeInsetsDirectional get gutter =>
      EdgeInsetsDirectional.symmetric(horizontal: screenGutter);

  /// Chip padding: [base] inline, slightly tighter block.
  EdgeInsetsDirectional get chipPadding => EdgeInsetsDirectional.symmetric(
        horizontal: base,
        vertical: snug + micro,
      );

  /// The rounding of a control.
  BorderRadius get controlRadius => BorderRadius.circular(radiusControl);

  /// The rounding of a card, sheet or dock.
  BorderRadius get surfaceRadius => BorderRadius.circular(radiusSurface);

  /// The rounding of a compartment well.
  BorderRadius get compartmentRadius => BorderRadius.circular(radiusCompartment);

  /// The rounding of the platter silhouette.
  BorderRadius get platterRadius => BorderRadius.circular(radiusPlatter);

  /// A fully rounded pill, for the scale toggle and the checkout action.
  BorderRadius get pillRadius => BorderRadius.circular(999);

  @override
  MawzoonSpacing copyWith({
    double? hairline,
    double? micro,
    double? tight,
    double? snug,
    double? base,
    double? comfortable,
    double? loose,
    double? section,
    double? chapter,
    double? thumbTarget,
    double? screenGutter,
    double? dockPadding,
    double? radiusSubtle,
    double? radiusControl,
    double? radiusSurface,
    double? radiusCompartment,
    double? radiusPlatter,
  }) =>
      MawzoonSpacing(
        hairline: hairline ?? this.hairline,
        micro: micro ?? this.micro,
        tight: tight ?? this.tight,
        snug: snug ?? this.snug,
        base: base ?? this.base,
        comfortable: comfortable ?? this.comfortable,
        loose: loose ?? this.loose,
        section: section ?? this.section,
        chapter: chapter ?? this.chapter,
        thumbTarget: thumbTarget ?? this.thumbTarget,
        screenGutter: screenGutter ?? this.screenGutter,
        dockPadding: dockPadding ?? this.dockPadding,
        radiusSubtle: radiusSubtle ?? this.radiusSubtle,
        radiusControl: radiusControl ?? this.radiusControl,
        radiusSurface: radiusSurface ?? this.radiusSurface,
        radiusCompartment: radiusCompartment ?? this.radiusCompartment,
        radiusPlatter: radiusPlatter ?? this.radiusPlatter,
      );

  @override
  MawzoonSpacing lerp(ThemeExtension<MawzoonSpacing>? other, double t) {
    if (other is! MawzoonSpacing) return this;
    double d(double a, double b) => a + (b - a) * t;
    return MawzoonSpacing(
      hairline: d(hairline, other.hairline),
      micro: d(micro, other.micro),
      tight: d(tight, other.tight),
      snug: d(snug, other.snug),
      base: d(base, other.base),
      comfortable: d(comfortable, other.comfortable),
      loose: d(loose, other.loose),
      section: d(section, other.section),
      chapter: d(chapter, other.chapter),
      thumbTarget: d(thumbTarget, other.thumbTarget),
      screenGutter: d(screenGutter, other.screenGutter),
      dockPadding: d(dockPadding, other.dockPadding),
      radiusSubtle: d(radiusSubtle, other.radiusSubtle),
      radiusControl: d(radiusControl, other.radiusControl),
      radiusSurface: d(radiusSurface, other.radiusSurface),
      radiusCompartment: d(radiusCompartment, other.radiusCompartment),
      radiusPlatter: d(radiusPlatter, other.radiusPlatter),
    );
  }

  @override
  String toString() => 'MawzoonSpacing(base: $base, gutter: $screenGutter)';
}
