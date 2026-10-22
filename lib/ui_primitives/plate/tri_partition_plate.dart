import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../../core/menu/plate_segment.dart';
import '../../core/nutrition/nutritional_summary.dart';
import '../motion/motion.dart';
import '../theme/mawzoon_colors.dart';
import '../theme/mawzoon_typography.dart';
import '../theme/theme_context.dart';
import 'plate_animation_model.dart';
import 'plate_canvas_painter.dart';
import 'plate_geometry.dart';

/// The hero plate: an organic tri-compartment dish with a perimeter macro
/// ring that sweeps as compartments fill.
///
/// ## Why this repaints the way it does
///
/// Three layers, each in its own [RepaintBoundary]:
///
/// 1. **Ambient** — a 16-second radial breath. Always moving, so it is
///    isolated; if it shared a layer with the plate it would keep the plate's
///    ticker alive all evening.
/// 2. **Plate** — dish, compartments and ring. Animates only while a spring is
///    in flight, then the ticker stops entirely.
/// 3. **Overlay** — anything a caller stacks on top, kept out of both.
///
/// The painter receives the [PlateAnimationModel] as its `repaint:` argument,
/// which is the load-bearing detail: a repainting `CustomPainter` re-enters
/// only the paint phase. No widget rebuilds while the plate animates — not
/// this one, not its parent, not the dock or the carousels beside it. The
/// obvious alternative, an `AnimatedBuilder` wrapped around the canvas,
/// rebuilds a widget 120 times a second to produce identical pixels.
///
/// Every animated property is a [Transform] or a colour alpha. Nothing here
/// animates a layout value, so no frame ever re-runs layout.
class TriPartitionPlate extends StatefulWidget {
  /// Creates the hero plate for [summary].
  const TriPartitionPlate({
    required this.summary,
    super.key,
    this.aspectRatio = 2.24,
    this.showAmbientWarmth = true,
    this.semanticLabel,
    this.componentImages,
    this.bodyDepth = 0,
  });

  /// The live plate reading. The widget takes a summary rather than a
  /// controller so it can be driven by a curated plate, a cart line or a test
  /// just as easily as by the Architect.
  final NutritionalSummary summary;

  /// Width to height. An elongated serving platter, not a dinner plate.
  final double aspectRatio;

  /// Whether to paint the Tier 1 ambient layer.
  final bool showAmbientWarmth;

  /// Screen-reader description. Defaults to a generated plate summary.
  final String? semanticLabel;

  /// A photo for a filled compartment, keyed by segment. No dish ships one
  /// today — this is the slot a future catalogue entry fills; a segment
  /// missing from the map (or the map itself being `null`) falls back to
  /// today's tone wash.
  final Map<PlateSegment, ImageProvider>? componentImages;

  /// Thickness of the platter's side wall, drawn below the plate's own
  /// height (the widget reserves this much extra space). Zero is the flat
  /// top-down plate.
  final double bodyDepth;

  @override
  State<TriPartitionPlate> createState() => _TriPartitionPlateState();
}

class _TriPartitionPlateState extends State<TriPartitionPlate>
    with TickerProviderStateMixin {
  late final PlateAnimationModel _model;
  late final BalanceLockChoreography _lock;
  final PlateGeometryCache _geometry = PlateGeometryCache();

  // One stream + listener per segment currently being resolved, so a
  // provider swap or a dispose can unsubscribe the exact right one instead
  // of leaking a callback into a torn-down State.
  final Map<PlateSegment, ImageStream> _imageStreams = <PlateSegment, ImageStream>{};
  final Map<PlateSegment, ImageStreamListener> _imageListeners =
      <PlateSegment, ImageStreamListener>{};
  final Map<PlateSegment, ui.Image> _resolvedImages = <PlateSegment, ui.Image>{};

  @override
  void initState() {
    super.initState();
    _model = PlateAnimationModel(vsync: this);
    _model.seed(filled: _filled, arcTargets: _arcTargets);
    _lock = BalanceLockChoreography(vsync: this)
      ..seed(locked: widget.summary.isComplete);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _model.reducedMotion = reduced;
    _lock.reducedMotion = reduced;
    _syncImages(widget.componentImages);
  }

  @override
  void didUpdateWidget(TriPartitionPlate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.componentImages, widget.componentImages)) {
      _syncImages(widget.componentImages);
    }
    if (oldWidget.summary == widget.summary) return;

    final bool wasComplete = oldWidget.summary.isComplete;
    _model.retarget(filled: _filled, arcTargets: _arcTargets);
    // The lock is a threshold, struck on the crossing. Swapping a component on
    // an already-complete plate must not spend the milestone again.
    if (widget.summary.isComplete && !wasComplete) {
      _model.strikeLock();
      _lock.lock();
    } else if (!widget.summary.isComplete && wasComplete) {
      _lock.release();
    }
  }

  /// Resolves each segment's [ImageProvider] to a decoded [ui.Image], and
  /// drops the subscription for any segment no longer in [images].
  ///
  /// [CustomPainter] paints synchronously — it cannot await a network or
  /// asset decode — so the decode happens here, once per provider change,
  /// and the result is handed to the painter as an already-resolved image.
  void _syncImages(Map<PlateSegment, ImageProvider>? images) {
    for (final PlateSegment segment in PlateSegment.buildOrder) {
      final ImageStreamListener? oldListener = _imageListeners.remove(segment);
      final ImageStream? oldStream = _imageStreams.remove(segment);
      if (oldListener != null) oldStream?.removeListener(oldListener);

      final ImageProvider? provider = images?[segment];
      if (provider == null) {
        _resolvedImages.remove(segment);
        continue;
      }

      final ImageStream stream =
          provider.resolve(createLocalImageConfiguration(context));
      final ImageStreamListener listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          if (!mounted) return;
          setState(() => _resolvedImages[segment] = info.image);
        },
      );
      _imageStreams[segment] = stream;
      _imageListeners[segment] = listener;
      stream.addListener(listener);
    }
  }

  List<bool> get _filled => PlateSegment.buildOrder
      .map((PlateSegment s) => widget.summary.contributionFor(s).isFilled)
      .toList(growable: false);

  /// An arc sweeps fully once its compartment is chosen; how far around the
  /// rim that reaches is set by the compartment's energy share, which the
  /// painter reads from the data rather than from the spring.
  List<double> get _arcTargets => PlateSegment.buildOrder
      .map((PlateSegment s) =>
          widget.summary.contributionFor(s).isFilled ? 1.0 : 0.0,)
      .toList(growable: false);

  PlateCanvasData _data(BuildContext context) {
    final NutritionalSummary s = widget.summary;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final List<String> labels = <String>[];
    final List<String> details = <String>[];
    final List<String> prompts = <String>[];

    for (final PlateSegment segment in PlateSegment.buildOrder) {
      final SegmentContribution c = s.contributionFor(segment);
      if (c.isFilled) {
        labels.add('${c.portionGrams.round()}${rtl ? ' غ' : ' g'}');
        details.add('${c.kilocalories.round()} kcal');
        prompts.add('');
      } else {
        labels.add(segment.label.resolve(context.appLanguage));
        details.add('');
        prompts.add(segment.invitation.resolve(context.appLanguage));
      }
    }

    return PlateCanvasData(
      filled: _filled,
      energyShares: PlateSegment.buildOrder
          .map((PlateSegment s2) => s.contributionFor(s2).energyShare)
          .toList(growable: false),
      compartmentLabels: labels,
      compartmentDetails: details,
      emptyPrompts: prompts,
      compartmentImages: PlateSegment.buildOrder
          .map((PlateSegment s2) => _resolvedImages[s2])
          .toList(growable: false),
    );
  }

  String _describe(BuildContext context) {
    if (widget.semanticLabel != null) return widget.semanticLabel!;
    final NutritionalSummary s = widget.summary;
    final List<String> parts = PlateSegment.buildOrder.map((PlateSegment seg) {
      final SegmentContribution c = s.contributionFor(seg);
      final String name = seg.label.resolve(context.appLanguage);
      return c.isFilled
          ? '$name ${c.portionGrams.round()}g'
          : '$name —';
    }).toList(growable: false);
    return '${parts.join(', ')}. ${s.displayKilocalories} kcal.';
  }

  @override
  void dispose() {
    for (final PlateSegment segment in _imageStreams.keys) {
      _imageStreams[segment]!.removeListener(_imageListeners[segment]!);
    }
    _lock.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MawzoonColors colors = context.colors;
    final MawzoonTypography type = context.type;

    return Semantics(
      label: _describe(context),
      container: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.bodyDepth),
        child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: <Widget>[
            if (widget.showAmbientWarmth) AmbientGlow(color: colors.ember),
            RepaintBoundary(
              child: CustomPaint(
                painter: PlateCeramicPainter(
                  colors: colors,
                  textDirection: Directionality.of(context),
                  geometryCache: _geometry,
                  depth: widget.bodyDepth,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: PlateCanvasPainter(
                  model: _model,
                  lock: _lock,
                  data: _data(context),
                  colors: colors,
                  textDirection: Directionality.of(context),
                  geometryCache: _geometry,
                  labelStyle: type.capsuleLabel,
                  detailStyle: type.macroUnit,
                  emptyStyle: type.tagLabel,
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
