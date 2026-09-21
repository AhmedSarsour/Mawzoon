import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../theme/mawzoon_colors.dart';
import 'plate_animation_model.dart';
import 'plate_geometry.dart';

/// What the painter needs to know about the plate, flattened.
///
/// The painter is handed shares and flags, never a `NutritionalSummary` and
/// never a menu option. Keeping the nutrition domain out of the paint phase is
/// what stops a future change to the calorie engine from quietly becoming a
/// rendering change.
@immutable
final class PlateCanvasData {
  /// Creates a snapshot of the plate for painting.
  ///
  /// Not `const`: the length assertions below cannot be evaluated in a
  /// constant expression, and keeping a three-compartment invariant that the
  /// compiler enforces is worth more than a const literal.
  const PlateCanvasData({
    required this.filled,
    required this.energyShares,
    required this.compartmentLabels,
    required this.compartmentDetails,
  })  : assert(filled.length == 3),
        assert(energyShares.length == 3),
        assert(compartmentLabels.length == 3),
        assert(compartmentDetails.length == 3);

  /// An untouched plate.
  static final PlateCanvasData empty = PlateCanvasData(
    filled: const <bool>[false, false, false],
    energyShares: const <double>[0, 0, 0],
    compartmentLabels: const <String>['', '', ''],
    compartmentDetails: const <String>['', '', ''],
  );

  /// Whether each compartment holds a component.
  final List<bool> filled;

  /// Each compartment's share of the plate's energy, summing to 1 when full.
  final List<double> energyShares;

  /// The line drawn inside a compartment — its mass when filled, its name
  /// when empty.
  final List<String> compartmentLabels;

  /// The second line inside a filled compartment, usually its energy.
  final List<String> compartmentDetails;

  /// How many compartments are filled.
  int get filledCount => filled.where((bool f) => f).length;

  /// Whether the plate is complete.
  bool get isComplete => filledCount == 3;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlateCanvasData &&
          listEquals(other.filled, filled) &&
          listEquals(other.energyShares, energyShares) &&
          listEquals(other.compartmentLabels, compartmentLabels) &&
          listEquals(other.compartmentDetails, compartmentDetails);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(filled),
        Object.hashAll(energyShares),
        Object.hashAll(compartmentLabels),
        Object.hashAll(compartmentDetails),
      );
}

/// Paints the tri-partition platter and its perimeter macro ring.
///
/// Repaint is driven entirely by the [PlateAnimationModel] passed as
/// `repaint:`, so an animating plate never enters build or layout. The only
/// things [shouldRepaint] is allowed to notice are genuine configuration
/// changes — new data, a new palette, a direction flip — because everything
/// frame-to-frame already arrives through the listenable.
final class PlateCanvasPainter extends CustomPainter {
  /// Creates the painter.
  PlateCanvasPainter({
    required this.model,
    required this.data,
    required this.colors,
    required this.textDirection,
    required this.geometryCache,
    required this.labelStyle,
    required this.detailStyle,
    required this.emptyStyle,
  }) : super(repaint: model);

  /// The spring values, and the repaint source.
  final PlateAnimationModel model;

  /// The flattened plate snapshot.
  final PlateCanvasData data;

  /// The role palette for the current theme.
  final MawzoonColors colors;

  /// Layout direction. Under RTL the compartments and the arcs both mirror.
  final TextDirection textDirection;

  /// Solved geometry, kept across frames.
  final PlateGeometryCache geometryCache;

  /// Style for the line inside a filled compartment.
  final TextStyle labelStyle;

  /// Style for the second line inside a filled compartment.
  final TextStyle detailStyle;

  /// Style for the prompt inside an empty compartment.
  final TextStyle emptyStyle;

  /// Gap between two macro arcs, as a fraction of the ring's perimeter.
  static const double arcGapFraction = 0.018;

  /// Stroke width of a macro arc.
  static const double arcStroke = 6.5;

  bool get _mirror => textDirection == TextDirection.rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final PlateGeometry g = geometryCache.of(size, mirror: _mirror);

    _paintDish(canvas, g);
    _paintCompartments(canvas, g);
    _paintRing(canvas, g);
  }

  void _paintDish(Canvas canvas, PlateGeometry g) {
    // A contact shadow, drawn from the dish's own path rather than a rounded
    // rectangle standing in for it, so the shadow's silhouette is the dish's.
    canvas.drawShadow(g.dish, const Color(0xFF000000), 6, false);
    canvas.drawPath(g.dish, Paint()..color = colors.structure);
    canvas.drawPath(
      g.dish,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.hairline,
    );
  }

  void _paintCompartments(Canvas canvas, PlateGeometry g) {
    for (int logical = 0; logical < 3; logical++) {
      // Logical order is protein, carb, fibre. Visually that runs right to
      // left under RTL, so the zone a compartment occupies is mirrored while
      // the data behind it is not.
      final int slot = _mirror ? 2 - logical : logical;
      final Path zone = g.zones[slot];
      final Offset centre = g.zoneCentroids[slot];
      final Color tone = colors.toneForSegmentOrdinal(logical);
      final double fill = model.fills[logical].value.clamp(0.0, 1.0);
      final bool isFilled = data.filled[logical];

      canvas.drawPath(
        zone,
        Paint()
          ..color = isFilled
              ? tone.withValues(alpha: 0.10 + 0.09 * fill)
              : colors.ink.withValues(alpha: 0.035),
      );

      canvas.drawPath(
        zone,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isFilled ? 1.4 : 1.0
          ..color = isFilled
              ? tone.withValues(alpha: 0.30 + 0.50 * fill)
              : colors.inkFaint.withValues(alpha: 0.40),
      );

      _paintCompartmentText(canvas, logical, centre, tone, isFilled);
    }
  }

  void _paintCompartmentText(
    Canvas canvas,
    int logical,
    Offset centre,
    Color tone,
    bool isFilled,
  ) {
    final String label = data.compartmentLabels[logical];
    if (label.isEmpty) return;

    if (!isFilled) {
      _drawCentred(canvas, label, emptyStyle.copyWith(color: colors.inkFaint),
          centre,);
      return;
    }

    _drawCentred(
      canvas,
      label,
      labelStyle.copyWith(color: tone),
      centre.translate(0, -8),
    );
    final String detail = data.compartmentDetails[logical];
    if (detail.isNotEmpty) {
      _drawCentred(
        canvas,
        detail,
        // Figures stay left-to-right in both languages: "175 kcal", never
        // "kcal 175".
        detailStyle.copyWith(color: colors.inkSoft),
        centre.translate(0, 9),
        forceLtr: true,
      );
    }
  }

  void _drawCentred(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset centre, {
    bool forceLtr = false,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: forceLtr ? TextDirection.ltr : textDirection,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);
    painter.paint(
      canvas,
      Offset(centre.dx - painter.width / 2, centre.dy - painter.height / 2),
    );
    painter.dispose();
  }

  /// Draws the macro arcs as genuine sub-paths of the dish's own perimeter.
  void _paintRing(Canvas canvas, PlateGeometry g) {
    final double lock = model.lock.value;

    canvas.save();
    if (lock > 0.0001) {
      // The balance-lock settle: a 3% swell about the dish's centre. Scaling
      // the canvas rather than re-solving the geometry keeps this free.
      final Offset centre = g.ring.getBounds().center;
      final double scale = 1 + lock * 0.030;
      canvas
        ..translate(centre.dx, centre.dy)
        ..scale(scale, scale)
        ..translate(-centre.dx, -centre.dy);
    }

    canvas.drawPath(
      g.ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = arcStroke - 0.5
        ..color = colors.track,
    );

    final int liveCount = data.filledCount;
    if (liveCount > 0) {
      final double totalGap = arcGapFraction * liveCount;
      final double usable = 1 - totalGap;
      double cursor = arcGapFraction / 2;

      for (int logical = 0; logical < 3; logical++) {
        if (!data.filled[logical]) continue;
        final double allotted = usable * data.energyShares[logical];
        final double swept = allotted * model.arcs[logical].value.clamp(0.0, 1.0);

        if (swept > 0.0005) {
          canvas.drawPath(
            g.arc(cursor, cursor + swept, mirror: _mirror),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = arcStroke
              ..strokeCap = StrokeCap.round
              ..color = colors.toneForSegmentOrdinal(logical),
          );
        }
        cursor += allotted + arcGapFraction;
      }
    }

    if (lock > 0.004) {
      canvas.drawPath(
        g.ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = colors.olive.withValues(alpha: 0.30 * lock),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PlateCanvasPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.colors != colors ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.detailStyle != detailStyle ||
      oldDelegate.emptyStyle != emptyStyle;

  @override
  bool shouldRebuildSemantics(PlateCanvasPainter oldDelegate) => false;

  @override
  bool hitTest(Offset position) => false;
}

/// Tier 1 ambient warmth: a slow radial breath behind the dish.
///
/// Deliberately a separate painter on its own layer. Folded into
/// [PlateCanvasPainter] it would keep that layer's ticker running forever and
/// make an untouched plate cost frames all evening; isolated, the interactive
/// layer can go completely idle while this one breathes.
final class AmbientWarmthPainter extends CustomPainter {
  /// Creates the ambient painter.
  AmbientWarmthPainter({
    required this.breath,
    required this.colors,
  }) : super(repaint: breath);

  /// A 0-1 cycle driven by a long, slow controller.
  final Animation<double> breath;

  /// The role palette.
  final MawzoonColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final double t = breath.value;
    final Offset centre = size.center(Offset.zero);
    final double alpha = 0.055 + 0.035 * t;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          size.width * 0.62,
          <Color>[
            colors.ember.withValues(alpha: alpha),
            colors.ember.withValues(alpha: 0),
          ],
          <double>[0, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(AmbientWarmthPainter oldDelegate) =>
      oldDelegate.colors != colors;

  @override
  bool hitTest(Offset position) => false;
}
