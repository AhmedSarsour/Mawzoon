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

  @override
  State<TriPartitionPlate> createState() => _TriPartitionPlateState();
}

class _TriPartitionPlateState extends State<TriPartitionPlate>
    with TickerProviderStateMixin {
  late final PlateAnimationModel _model;
  late final BalanceLockChoreography _lock;
  final PlateGeometryCache _geometry = PlateGeometryCache();

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
  }

  @override
  void didUpdateWidget(TriPartitionPlate oldWidget) {
    super.didUpdateWidget(oldWidget);
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

    for (final PlateSegment segment in PlateSegment.buildOrder) {
      final SegmentContribution c = s.contributionFor(segment);
      if (c.isFilled) {
        labels.add('${c.portionGrams.round()}${rtl ? ' غ' : ' g'}');
        details.add('${c.kilocalories.round()} kcal');
      } else {
        labels.add(segment.label.resolve(context.appLanguage));
        details.add('');
      }
    }

    return PlateCanvasData(
      filled: _filled,
      energyShares: PlateSegment.buildOrder
          .map((PlateSegment s2) => s.contributionFor(s2).energyShare)
          .toList(growable: false),
      compartmentLabels: labels,
      compartmentDetails: details,
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
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (widget.showAmbientWarmth) AmbientGlow(color: colors.ember),
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
    );
  }
}
