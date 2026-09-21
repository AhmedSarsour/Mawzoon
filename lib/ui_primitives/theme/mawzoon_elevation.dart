import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// The shadow ladder.
///
/// Material's default elevation model tints a surface lighter as it rises,
/// which on Smoked Obsidian reads as grey haze and flattens the warmth out of
/// the palette. Mawzoon separates the two ideas instead: the *surface colour*
/// comes from [MawzoonColors] and moves at most one step, while *depth* is
/// carried entirely by shadow. A raised thing casts; it does not glow.
///
/// Four levels, and no more. A fifth would mean nothing is actually primary.
@immutable
final class MawzoonElevation extends ThemeExtension<MawzoonElevation> {
  /// Creates an elevation ladder. Prefer [MawzoonElevation.of].
  const MawzoonElevation({
    required this.flush,
    required this.resting,
    required this.lifted,
    required this.platter,
    required this.dock,
  });

  /// The ladder tuned for [brightness].
  ///
  /// Dark needs deeper, tighter shadows: on an almost-black ground a wide soft
  /// shadow is invisible, so the contact shadow does the work. Light can
  /// afford a broader, weaker cast.
  factory MawzoonElevation.of(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    const Color shadow = Color(0xFF000000);

    Color at(double opacity) => shadow.withValues(alpha: opacity);

    return MawzoonElevation(
      flush: const <BoxShadow>[],
      resting: <BoxShadow>[
        BoxShadow(
          color: at(dark ? 0.30 : 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
      lifted: <BoxShadow>[
        BoxShadow(
          color: at(dark ? 0.34 : 0.06),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: at(dark ? 0.40 : 0.10),
          blurRadius: 18,
          spreadRadius: -8,
          offset: const Offset(0, 8),
        ),
      ],
      // The hero tray. The only place in the app that earns a shadow this size.
      platter: <BoxShadow>[
        BoxShadow(
          color: at(dark ? 0.46 : 0.09),
          blurRadius: 28,
          spreadRadius: -10,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: at(dark ? 0.30 : 0.05),
          blurRadius: 3,
          offset: const Offset(0, 2),
        ),
      ],
      // The dock sits on the bottom edge, so its shadow casts upward — a
      // downward one would fall off the screen and read as a hairline.
      dock: <BoxShadow>[
        BoxShadow(
          color: at(dark ? 0.38 : 0.07),
          blurRadius: 22,
          spreadRadius: -6,
          offset: const Offset(0, -6),
        ),
      ],
    );
  }

  /// Level 0 — flush with the canvas. No shadow at all.
  final List<BoxShadow> flush;

  /// Level 1 — a resting surface: a carousel chip, a list row, a tag.
  final List<BoxShadow> resting;

  /// Level 2 — a lifted surface: a selected chip, a menu, a tooltip.
  final List<BoxShadow> lifted;

  /// Level 3 — the plate platter. Reserved for the hero.
  final List<BoxShadow> platter;

  /// Level 4 — the bottom dock. Casts upward.
  final List<BoxShadow> dock;

  @override
  MawzoonElevation copyWith({
    List<BoxShadow>? flush,
    List<BoxShadow>? resting,
    List<BoxShadow>? lifted,
    List<BoxShadow>? platter,
    List<BoxShadow>? dock,
  }) =>
      MawzoonElevation(
        flush: flush ?? this.flush,
        resting: resting ?? this.resting,
        lifted: lifted ?? this.lifted,
        platter: platter ?? this.platter,
        dock: dock ?? this.dock,
      );

  @override
  MawzoonElevation lerp(ThemeExtension<MawzoonElevation>? other, double t) {
    if (other is! MawzoonElevation) return this;
    List<BoxShadow> s(List<BoxShadow> a, List<BoxShadow> b) =>
        BoxShadow.lerpList(a, b, t) ?? b;
    return MawzoonElevation(
      flush: s(flush, other.flush),
      resting: s(resting, other.resting),
      lifted: s(lifted, other.lifted),
      platter: s(platter, other.platter),
      dock: s(dock, other.dock),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MawzoonElevation &&
          listEquals(other.flush, flush) &&
          listEquals(other.resting, resting) &&
          listEquals(other.lifted, lifted) &&
          listEquals(other.platter, platter) &&
          listEquals(other.dock, dock);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(flush),
        Object.hashAll(resting),
        Object.hashAll(lifted),
        Object.hashAll(platter),
        Object.hashAll(dock),
      );

  @override
  String toString() => 'MawzoonElevation(4 levels)';
}
