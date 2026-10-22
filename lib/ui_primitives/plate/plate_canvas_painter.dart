import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/mawzoon_brand.dart';
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
    this.emptyPrompts = const <String>['', '', ''],
    this.compartmentImages = const <ui.Image?>[null, null, null],
  })  : assert(filled.length == 3),
        assert(energyShares.length == 3),
        assert(compartmentLabels.length == 3),
        assert(compartmentDetails.length == 3),
        assert(emptyPrompts.length == 3),
        assert(compartmentImages.length == 3);

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

  /// The invitation shown in the pill below an empty compartment's name.
  /// Ignored once the compartment is filled.
  final List<String> emptyPrompts;

  /// A decoded photo for a filled compartment. `null` falls back to today's
  /// tone wash — no asset exists for any dish yet, so this is always `null`
  /// in the app today; the slot exists for the day one does.
  final List<ui.Image?> compartmentImages;

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
          listEquals(other.compartmentDetails, compartmentDetails) &&
          listEquals(other.emptyPrompts, emptyPrompts) &&
          listEquals(other.compartmentImages, compartmentImages);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(filled),
        Object.hashAll(energyShares),
        Object.hashAll(compartmentLabels),
        Object.hashAll(compartmentDetails),
        Object.hashAll(emptyPrompts),
        Object.hashAll(compartmentImages),
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
    required this.lock,
    required this.data,
    required this.colors,
    required this.textDirection,
    required this.geometryCache,
    required this.labelStyle,
    required this.detailStyle,
    required this.emptyStyle,
  }) : super(repaint: Listenable.merge(<Listenable>[model, lock]));

  /// The spring values, and a repaint source.
  final PlateAnimationModel model;

  /// The Tier 4 milestone, and the other repaint source.
  ///
  /// Merged with [model] rather than nested, so the lock's stroke and colour
  /// arrive on the same frame as the arcs they modify.
  final BalanceLockChoreography lock;

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

    // The ceramic itself is [PlateCeramicPainter], on its own layer below.
    _paintCompartments(canvas, g);
    _paintGrooves(canvas, g);
    _paintRing(canvas, g);
  }

  /// Dividers pressed into the glaze: a shadow line, then a highlight 1.2px
  /// to its right. Light comes from the upper left and does not mirror in RTL,
  /// because a real lamp does not move when the language changes.
  void _paintGrooves(Canvas canvas, PlateGeometry g) {
    final _CeramicTones tones = _CeramicTones.of(colors);
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final Path divider in g.dividers) {
      canvas.drawPath(divider, stroke..color = tones.groove);
      canvas.drawPath(
        divider.shift(const Offset(1.2, 0)),
        stroke..color = tones.grooveLight,
      );
    }
  }

  /// Opacity of a filled compartment's tone wash (no photo).
  ///
  /// Richer than the first pass (0.10 + 0.09 * fill), which read faint next
  /// to reference A (P2). Dark needs more: a wash on a dark well has less
  /// luminance difference to show. Public so a test can hold the label
  /// contrast on the *blended* fill above 3:1.
  static double compartmentWashAlpha({
    required bool dark,
    required double fill,
  }) =>
      dark ? 0.22 + 0.14 * fill : 0.14 + 0.10 * fill;

  /// The label colour for a compartment washed in [tone].
  ///
  /// The label is the tone itself, and the richer wash (P2) is that same tone
  /// behind it, which pulls the two together: some tones fell under 3:1
  /// (large-text AA). Where that happens the tone is pulled toward `ink` just
  /// far enough to clear it, so colour-coding survives wherever it can.
  /// Measured against the fully filled wash on both well surfaces, so the
  /// colour doesn't shift while the fill animates.
  static Color compartmentLabelInk(MawzoonColors colors, Color tone) {
    final bool dark = colors.brightness == Brightness.dark;
    final Color wash = tone.withValues(
      alpha: compartmentWashAlpha(dark: dark, fill: 1),
    );
    return _inkClearing(colors, tone, <Color>[
      Color.alphaBlend(wash, colors.structure),
      Color.alphaBlend(wash, colors.structureElevated),
    ]);
  }

  /// The label colour on a photo compartment's porcelain band (P1). Same rule
  /// as [compartmentLabelInk], measured against the band instead.
  static Color bandLabelInk(MawzoonColors colors, Color tone) =>
      _inkClearing(colors, tone, <Color>[colors.porcelain]);

  /// [tone], pulled toward `ink` only as far as it takes to clear 3:1
  /// (large-text AA) on every one of [surfaces]. Linear search over 11
  /// steps, stopping at the first that clears: O(1), and colour-coding
  /// survives wherever the tone is already legible.
  static Color _inkClearing(
    MawzoonColors colors,
    Color tone,
    List<Color> surfaces,
  ) {
    double worst(Color ink) => surfaces
        .map((Color s) => MawzoonBrand.contrastRatio(ink, s))
        .reduce(math.min);
    for (int i = 0; i <= 10; i++) {
      final Color candidate = Color.lerp(tone, colors.ink, i / 10)!;
      if (worst(candidate) >= 3.05) return candidate;
    }
    return colors.ink;
  }

  /// Share of a photo compartment's height the label band covers, at least.
  static const double bandFraction = 0.36;

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

      // An empty well is bare glaze: the grooves already mark its edges, so
      // it gets no wash and no outline.
      if (isFilled) {
        // The wash goes under a photo too: photos are transparent cut-outs,
        // so the compartment's tone shows around the food.
        canvas.drawPath(
          zone,
          Paint()
            ..color = tone.withValues(
              alpha: compartmentWashAlpha(
                dark: colors.brightness == Brightness.dark,
                fill: fill,
              ),
            ),
        );
        final ui.Image? image = data.compartmentImages[logical];
        if (image != null) {
          final Rect band = _bandFor(zone, logical);
          _paintCompartmentImage(canvas, zone, band, image, fill);
          _paintLabelBand(canvas, zone, band, fill);
        }
        canvas.drawPath(
          zone,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = tone.withValues(alpha: 0.30 + 0.50 * fill),
        );
      }

      // Compartments are different widths by design, so a label is measured
      // against its own well rather than a shared guess. The greens
      // compartment is the narrowest, and is where this first shows.
      _paintCompartmentText(
        canvas,
        logical,
        centre,
        tone,
        isFilled,
        zone.getBounds().width - 16,
        zone,
      );
    }
  }

  /// A filled compartment's cut-out, cover-fit over the well (running under
  /// the top of the label [band]) and clipped to its zone, with a soft shadow
  /// falling bottom-right (the plate's light is top-left).
  ///
  /// Cover, so the food fills its compartment; the cut-outs carry transparent
  /// margins, so the clip trims those rather than the food. Opacity follows the compartment's
  /// fill spring, so the food fades in with the motion that already exists.
  /// Drawn every frame on purpose: the image arrives decoded and downsized,
  /// so each frame costs a few texture blits, not a decode.
  void _paintCompartmentImage(
    Canvas canvas,
    Path zone,
    Rect band,
    ui.Image image,
    double fill,
  ) {
    final Rect bounds = zone.getBounds();
    // The food runs under the top of the label band (the band is nearly
    // opaque, so only the plate's edge shows through), and fills the well:
    // side is the larger of the room's two sides, so the food is cover-fit
    // and the zone's clip trims the transparent margins, not the food.
    final double reach = math.min(band.top + band.height * 0.3, bounds.bottom);
    final Rect room = Rect.fromLTRB(bounds.left, bounds.top, bounds.right, reach);
    if (room.width <= 0 || room.height <= 0) return;
    final double side = math.max(room.width, room.height) * 1.08;
    final Rect target = Rect.fromCenter(
      center: room.center,
      width: side,
      height: side,
    );

    canvas.save();
    canvas.clipPath(zone);
    // Shadow: the same alpha silhouette, tinted, blurred and nudged.
    canvas.saveLayer(
      target.inflate(12),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4)
        ..colorFilter = ColorFilter.mode(
          Colors.black.withValues(
            alpha: (colors.brightness == Brightness.dark ? 0.55 : 0.30) * fill,
          ),
          BlendMode.srcIn,
        ),
    );
    paintImage(
      canvas: canvas,
      rect: target.shift(Offset(side * 0.03, side * 0.04)),
      image: image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    canvas.restore();
    paintImage(
      canvas: canvas,
      rect: target,
      image: image,
      fit: BoxFit.contain,
      opacity: fill,
      filterQuality: FilterQuality.medium,
    );
    canvas.restore();
  }

  /// The bottom strip of a photo compartment where its label sits: at least
  /// [bandFraction] of the zone's height, taller if the label and detail
  /// need it. A rect, not a path; the zone clips it when painted.
  Rect _bandFor(Path zone, int logical) {
    final Rect bounds = zone.getBounds();
    final double needed =
        _textHeight(data.compartmentLabels[logical], labelStyle) +
            _textHeight(data.compartmentDetails[logical], detailStyle) +
            12;
    final double height = math.min(
      math.max(bounds.height * bandFraction, needed),
      bounds.height * 0.6,
    );
    return Rect.fromLTRB(
      bounds.left,
      bounds.bottom - height,
      bounds.right,
      bounds.bottom,
    );
  }

  double _textHeight(String text, TextStyle style) {
    if (text.isEmpty) return 0;
    final TextPainter p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    final double h = p.height;
    p.dispose();
    return h;
  }

  /// Porcelain over the bottom of the photo, so the figures read on a calm
  /// surface instead of on food. Symmetric top-to-bottom, so it needs no RTL
  /// handling: the zone it is clipped to is already mirrored.
  void _paintLabelBand(Canvas canvas, Path zone, Rect band, double fill) {
    canvas.save();
    canvas.clipPath(zone);
    canvas.drawRect(
      band,
      Paint()..color = colors.porcelain.withValues(alpha: 0.94 * fill),
    );
    canvas.restore();
  }

  void _paintCompartmentText(
    Canvas canvas,
    int logical,
    Offset centre,
    Color tone,
    bool isFilled,
    double room,
    Path zone,
  ) {
    final Rect zoneBounds = zone.getBounds();
    final String label = data.compartmentLabels[logical];
    if (label.isEmpty || room <= 0) return;

    if (!isFilled) {
      _paintWatermark(canvas, logical, centre, zoneBounds);
      // A prompt shrinks to fit rather than spilling across the dish.
      // Ellipsising instead would leave "الألياف…", which names nothing.
      _drawCentred(
        canvas,
        label,
        _shrunkToFit(label, emptyStyle.copyWith(color: colors.inkFaint), room),
        centre.translate(0, -10),
        maxWidth: room,
      );
      _paintPromptPill(
        canvas,
        data.emptyPrompts[logical],
        centre.translate(0, 15),
        room,
      );
      return;
    }

    final bool hasPhoto = data.compartmentImages[logical] != null;
    // With a photo the label moves into the band, and is measured against
    // the band's own width: the bottom of an outer compartment is narrower.
    final Rect? band = hasPhoto ? _bandFor(zone, logical) : null;
    final Offset anchor =
        band == null ? centre : Offset(centre.dx, band.center.dy);
    final double width = band == null ? room : band.width - 16;
    _drawCentred(
      canvas,
      label,
      labelStyle.copyWith(
        color: hasPhoto
            ? bandLabelInk(colors, tone)
            : compartmentLabelInk(colors, tone),
      ),
      anchor.translate(0, -8),
      maxWidth: width,
    );
    final String detail = data.compartmentDetails[logical];
    if (detail.isNotEmpty) {
      _drawCentred(
        canvas,
        detail,
        // Figures stay left-to-right in both languages: "175 kcal", never
        // "kcal 175".
        detailStyle.copyWith(color: colors.inkSoft),
        anchor.translate(0, 9),
        maxWidth: width,
        forceLtr: true,
      );
    }
  }

  /// A faint silhouette behind an empty compartment's prompt — a cut of
  /// protein, a cluster of grain, a leaf — so the invitation reads before the
  /// eye even reaches the text. Purely decorative: alpha stays low enough
  /// that it never competes with the name or the pill on top of it.
  void _paintWatermark(
    Canvas canvas,
    int logical,
    Offset centre,
    Rect zoneBounds,
  ) {
    final bool dark = colors.brightness == Brightness.dark;
    final Paint paint = Paint()
      ..color = colors.ink.withValues(alpha: dark ? 0.07 : 0.10)
      ..style = PaintingStyle.fill;
    // The silhouettes are drawn at a fixed 22-unit scale; shrink to fit the
    // zone rather than overflow it in the narrowest (vital-fibre) tray third.
    final double size =
        (zoneBounds.width.clamp(0, 96) * 0.42).clamp(0.0, 34.0);
    if (size < 10) return;
    final double scale = size / 22;

    canvas.save();
    canvas.translate(centre.dx, centre.dy - 4);
    canvas.scale(scale, scale);
    canvas.drawPath(_PlateSilhouettes.forOrdinal(logical), paint);
    canvas.restore();
  }

  /// The porcelain pill under an empty compartment's name, carrying the
  /// segment's invitation copy. Hidden — not shrunk — once it can no longer
  /// fit without touching the neighbouring compartment.
  void _paintPromptPill(
    Canvas canvas,
    String prompt,
    Offset centre,
    double room,
  ) {
    if (prompt.isEmpty) return;
    final TextStyle style = emptyStyle.copyWith(
      color: colors.inkSoft,
      fontSize: (emptyStyle.fontSize ?? 11) - 1.5,
    );
    final TextPainter painter = TextPainter(
      text: TextSpan(text: prompt, style: style),
      textDirection: textDirection,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout();

    const double hPad = 10;
    const double vPad = 5;
    final double pillWidth = painter.width + hPad * 2;
    final double pillHeight = painter.height + vPad * 2;
    // A pill that would overrun its own compartment is dropped rather than
    // shrunk to an unreadable size — the name above still names the slot.
    if (pillWidth > room) {
      painter.dispose();
      return;
    }

    final RRect pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: pillWidth, height: pillHeight),
      Radius.circular(pillHeight / 2),
    );
    canvas
      ..drawRRect(pill, Paint()..color = colors.porcelain)
      ..drawRRect(
        pill,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.hairline,
      );
    painter.paint(
      canvas,
      Offset(centre.dx - painter.width / 2, centre.dy - painter.height / 2),
    );
    painter.dispose();
  }

  /// The largest size at or below [style] that fits [text] into [room].
  TextStyle _shrunkToFit(String text, TextStyle style, double room) {
    final double start = style.fontSize ?? 11;
    for (double size = start; size >= _minimumLabelSize; size -= 0.5) {
      final TextPainter probe = TextPainter(
        text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      final double width = probe.width;
      probe.dispose();
      if (width <= room) return style.copyWith(fontSize: size);
    }
    return style.copyWith(fontSize: _minimumLabelSize);
  }

  /// Below this a prompt is decoration rather than information.
  static const double _minimumLabelSize = 7.5;

  void _drawCentred(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset centre, {
    required double maxWidth,
    bool forceLtr = false,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: forceLtr ? TextDirection.ltr : textDirection,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(
      canvas,
      Offset(centre.dx - painter.width / 2, centre.dy - painter.height / 2),
    );
    painter.dispose();
  }

  /// Draws the macro arcs as genuine sub-paths of the dish's own perimeter.
  void _paintRing(Canvas canvas, PlateGeometry g) {
    final double swell = model.lock.value;
    // Tier 4: the perimeter thickens and turns toward equilibrium together.
    final double strokeWidth = arcStroke + lock.strokeGain;
    final double olive = lock.oliveBlend;

    canvas.save();
    if (swell > 0.0001) {
      // The balance-lock settle: a 3% swell about the dish's centre. Scaling
      // the canvas rather than re-solving the geometry keeps this free.
      final Offset centre = g.ring.getBounds().center;
      final double scale = 1 + swell * MawzoonMotion.lockSwell;
      canvas
        ..translate(centre.dx, centre.dy)
        ..scale(scale, scale)
        ..translate(-centre.dx, -centre.dy);
    }

    canvas.drawPath(
      g.ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth - 0.5
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
              ..strokeWidth = strokeWidth
              ..strokeCap = StrokeCap.round
              // The arcs keep their gaps, so the energy split stays legible
              // by proportion even once the hue stops reporting it.
              ..color = Color.lerp(
                colors.toneForSegmentOrdinal(logical),
                colors.olive,
                olive,
              )!,
          );
        }
        cursor += allotted + arcGapFraction;
      }
    }

    if (swell > 0.004) {
      canvas.drawPath(
        g.ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = colors.olive.withValues(alpha: 0.30 * swell),
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

/// The ceramic platter: raised lip, glazed well, and the rim's inner shadow.
///
/// Static, so it lives on its own layer: the blurs here rasterise once
/// instead of on every spring frame of [PlateCanvasPainter].
final class PlateCeramicPainter extends CustomPainter {
  /// Creates the ceramic layer.
  PlateCeramicPainter({
    required this.colors,
    required this.textDirection,
    required this.geometryCache,
    this.depth = 0,
  });

  /// Side-wall thickness below the plate, in pixels. Zero is a flat plate.
  final double depth;

  /// The role palette.
  final MawzoonColors colors;

  /// Layout direction; the geometry mirrors under RTL.
  final TextDirection textDirection;

  /// Solved geometry, shared with [PlateCanvasPainter].
  final PlateGeometryCache geometryCache;

  /// How far the lip reaches past the ring's centre line. Wider than half the
  /// arc stroke, so the macro arcs sit on the glaze instead of hanging off it.
  static const double lipOverhang = PlateCanvasPainter.arcStroke / 2 + 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final PlateGeometry g = geometryCache.of(
      size,
      mirror: textDirection == TextDirection.rtl,
    );
    final _CeramicTones tones = _CeramicTones.of(colors);
    final Rect box = Offset.zero & size;

    // Filled ring plus a wide stroke on the same path = ring grown outward.
    void lip(Paint paint) {
      canvas
        ..drawPath(g.ring, paint..style = PaintingStyle.fill)
        ..drawPath(
          g.ring,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = lipOverhang * 2
            ..strokeJoin = StrokeJoin.round,
        );
    }

    // 0. The platter's body: the lip stacked downward, one pixel per step
    // (O(depth) draws, on a layer that only repaints on a theme change).
    // Darker than the lip, so the wall reads as turned away from the light.
    if (depth > 0) {
      final Paint wall = Paint()..color = tones.body;
      for (double i = depth; i >= 1; i -= 1) {
        canvas.save();
        canvas.translate(0, i);
        lip(wall);
        canvas.restore();
      }
    }

    // 1. Cast shadow, below the dish because the light is above it.
    canvas.save();
    canvas.translate(0, 8 + depth);
    lip(
      Paint()
        ..color = tones.castShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();

    // 2. The lip's glaze: lit at the top, turning warmer toward the bottom.
    lip(
      Paint()
        ..shader = ui.Gradient.linear(
          box.topCenter,
          box.bottomCenter,
          <Color>[tones.lipTop, tones.lipBottom],
        ),
    );

    // 3. The well sits lower than the lip: darker under the top edge, where
    // the lip shades it, and brighter toward the bottom, which faces the light.
    final Rect well = g.dish.getBounds();
    canvas.drawPath(
      g.dish,
      Paint()
        ..shader = ui.Gradient.linear(
          well.topCenter,
          well.bottomCenter,
          <Color>[tones.wellTop, tones.wellBottom],
          <double>[0.0, 0.55],
        ),
    );

    // 4. Rim depth, clipped to the well. Shifting a blurred outline down puts
    // shadow on the inner top wall; shifting a thin one up puts a highlight on
    // the inner bottom wall. The other edge of each lands outside the clip.
    canvas.save();
    canvas.clipPath(g.dish);
    canvas.drawPath(
      g.dish.shift(const Offset(0, 4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = tones.rimShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      g.dish.shift(const Offset(0, -2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = tones.rimLight
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.restore();

    // 5. The step between lip and well.
    canvas.drawPath(
      g.dish,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.hairline.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(PlateCeramicPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.depth != depth;

  @override
  bool hitTest(Offset position) => false;
}

/// Small abstract shapes for the empty-compartment watermark, each drawn at
/// a fixed 22×22 scale centred on the origin: a cut of protein, a cluster of
/// grain, a leaf. [PlateCanvasPainter._paintWatermark] scales and translates
/// whichever one matches the compartment's ordinal.
final class _PlateSilhouettes {
  const _PlateSilhouettes._();

  /// A rounded cut of meat: an oval lobe with a smaller one overlapping it.
  static final Path _protein = Path()
    ..addOval(Rect.fromCenter(center: const Offset(-1, 1), width: 20, height: 14))
    ..addOval(Rect.fromCenter(center: const Offset(6, -4), width: 11, height: 9));

  /// A loose cluster of grains — five small ovals, none aligned to a grid.
  static final Path _smartCarb = Path()
    ..addOval(Rect.fromCenter(center: const Offset(-6, -5), width: 8, height: 5))
    ..addOval(Rect.fromCenter(center: const Offset(2, -7), width: 7, height: 4.5))
    ..addOval(Rect.fromCenter(center: const Offset(7, 1), width: 8, height: 5))
    ..addOval(Rect.fromCenter(center: const Offset(-3, 3), width: 7, height: 4.5))
    ..addOval(Rect.fromCenter(center: const Offset(-8, 6), width: 6, height: 4));

  /// A single leaf: two arcs meeting at a point top and bottom. No separate
  /// vein — at this alpha and scale, a second fill colour would be needed to
  /// make one read, and this stays a one-colour watermark like the others.
  static final Path _vitalFiber = Path()
    ..moveTo(0, -11)
    ..quadraticBezierTo(10, -6, 0, 11)
    ..quadraticBezierTo(-10, -6, 0, -11)
    ..close();

  /// The silhouette for a segment's ordinal (protein, smart carb, vital
  /// fibre, in that order) — an index, not a domain type, matching how
  /// [MawzoonColors.toneForSegmentOrdinal] keeps this layer off the menu.
  static Path forOrdinal(int ordinal) => switch (ordinal) {
        0 => _protein,
        1 => _smartCarb,
        _ => _vitalFiber,
      };
}

/// Glaze, shadow and highlight tones, derived from the theme roles.
///
/// No new brand colours: every tone is a structure role nudged toward the
/// light (white in light mode, [MawzoonColors.ink] in dark) or toward shadow.
@immutable
final class _CeramicTones {
  const _CeramicTones({
    required this.lipTop,
    required this.lipBottom,
    required this.wellTop,
    required this.wellBottom,
    required this.castShadow,
    required this.rimShadow,
    required this.rimLight,
    required this.groove,
    required this.grooveLight,
    required this.body,
  });

  factory _CeramicTones.of(MawzoonColors c) {
    final bool dark = c.brightness == Brightness.dark;
    final Color light = dark ? c.ink : const Color(0xFFFFFFFF);
    final Color shade = dark ? const Color(0xFF000000) : c.ink;
    return _CeramicTones(
      lipTop: Color.lerp(c.structureElevated, light, dark ? 0.05 : 0.6)!,
      lipBottom: c.structure,
      wellTop: Color.lerp(c.structure, shade, dark ? 0.18 : 0.03)!,
      wellBottom: Color.lerp(c.structureElevated, light, dark ? 0.02 : 0.35)!,
      castShadow: shade.withValues(alpha: dark ? 0.55 : 0.14),
      rimShadow: shade.withValues(alpha: dark ? 0.45 : 0.10),
      rimLight: light.withValues(alpha: dark ? 0.05 : 0.8),
      groove: shade.withValues(alpha: dark ? 0.55 : 0.16),
      grooveLight: light.withValues(alpha: dark ? 0.06 : 0.9),
      body: Color.lerp(c.structure, shade, dark ? 0.5 : 0.28)!,
    );
  }

  final Color lipTop;
  final Color lipBottom;
  final Color wellTop;
  final Color wellBottom;
  final Color castShadow;
  final Color rimShadow;
  final Color rimLight;
  final Color groove;
  final Color grooveLight;
  final Color body;
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
