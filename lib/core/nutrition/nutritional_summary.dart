import '../menu/dietary_metadata.dart';
import '../menu/ingredient_option.dart';
import '../menu/plate_segment.dart';
import 'balance_band.dart';
import 'macro_profile.dart';
import 'portion_scale.dart';

/// One compartment's contribution to the plate.
///
/// The [energyShare] is what drives the length of a single arc on the
/// tri-partition canvas, so it is computed once here and read by the painter
/// rather than recomputed per frame.
final class SegmentContribution {
  /// Creates a contribution record.
  const SegmentContribution({
    required this.segment,
    required this.macros,
    required this.portionGrams,
    required this.energyShare,
  });

  /// An unfilled compartment: no mass, no energy, zero arc sweep.
  factory SegmentContribution.empty(PlateSegment segment) =>
      SegmentContribution(
        segment: segment,
        macros: MacroProfile.zero,
        portionGrams: 0,
        energyShare: 0,
      );

  /// The compartment described.
  final PlateSegment segment;

  /// Macronutrients contributed by this compartment.
  final MacroProfile macros;

  /// Cooked mass in this compartment, in grams.
  final double portionGrams;

  /// Fraction of the plate's total energy contributed here, in `0.0..1.0`.
  ///
  /// Zero when the plate carries no energy at all, which keeps the painter
  /// free of division-by-zero guards.
  final double energyShare;

  /// Energy contributed by this compartment, in kilocalories.
  double get kilocalories => macros.kilocalories;

  /// Whether this compartment has been filled.
  bool get isFilled => portionGrams > 0;

  @override
  String toString() => 'SegmentContribution(${segment.name}, '
      '${kilocalories.round()} kcal, '
      '${(energyShare * 100).toStringAsFixed(1)}%)';
}

/// The complete, derived nutritional picture of a plate at a given scale.
///
/// Every field is computed from the selected components — nothing here is
/// stored data that could go stale. Build it with
/// [NutritionalSummary.fromComponents]; a partially built plate is perfectly
/// valid input and yields a summary with empty contributions for the
/// compartments not yet chosen.
final class NutritionalSummary {
  const NutritionalSummary._({
    required this.scale,
    required this.contributions,
    required this.totalMacros,
    required this.totalPortionGrams,
    required this.filledSegments,
    required this.allergens,
    required this.dietaryTags,
  });

  /// Computes a summary from whichever compartments are filled.
  ///
  /// [components] may contain zero to three entries, at most one per segment;
  /// a duplicate segment is a programming error and trips an assertion in
  /// debug builds. All components must share [scale].
  factory NutritionalSummary.fromComponents({
    required PortionScale scale,
    required Iterable<PortionedComponent> components,
  }) {
    final Map<PlateSegment, PortionedComponent> bySegment =
        <PlateSegment, PortionedComponent>{};
    for (final PortionedComponent component in components) {
      assert(
        component.scale == scale,
        'Component ${component.option.id} was portioned at '
        '${component.scale.name} but the summary is for ${scale.name}',
      );
      assert(
        !bySegment.containsKey(component.segment),
        'Two components supplied for ${component.segment.name}',
      );
      bySegment[component.segment] = component;
    }

    final MacroProfile total = MacroProfile.sum(
      bySegment.values.map((PortionedComponent c) => c.macros),
    );
    final double totalKilocalories = total.kilocalories;

    final Map<PlateSegment, SegmentContribution> contributions =
        <PlateSegment, SegmentContribution>{};
    double totalGrams = 0;
    final Set<Allergen> allergens = <Allergen>{};

    for (final PlateSegment segment in PlateSegment.buildOrder) {
      final PortionedComponent? component = bySegment[segment];
      if (component == null) {
        contributions[segment] = SegmentContribution.empty(segment);
        continue;
      }
      totalGrams += component.portionGrams;
      allergens.addAll(component.option.allergens);
      contributions[segment] = SegmentContribution(
        segment: segment,
        macros: component.macros,
        portionGrams: component.portionGrams,
        energyShare: totalKilocalories <= 0
            ? 0
            : component.macros.kilocalories / totalKilocalories,
      );
    }

    // A tag describes the plate only if every filled compartment carries it:
    // a plant-based carb beside a lamb kofta does not make the plate vegan.
    final List<Set<DietaryTag>> tagSets = bySegment.values
        .map((PortionedComponent c) => c.option.dietaryTags)
        .toList(growable: false);
    final Set<DietaryTag> sharedTags = tagSets.isEmpty
        ? <DietaryTag>{}
        : tagSets.reduce((Set<DietaryTag> a, Set<DietaryTag> b) =>
            a.intersection(b),);

    return NutritionalSummary._(
      scale: scale,
      contributions: Map<PlateSegment, SegmentContribution>.unmodifiable(
        contributions,
      ),
      totalMacros: total,
      totalPortionGrams: totalGrams,
      filledSegments: Set<PlateSegment>.unmodifiable(bySegment.keys.toSet()),
      allergens: Set<Allergen>.unmodifiable(allergens),
      dietaryTags: Set<DietaryTag>.unmodifiable(sharedTags),
    );
  }

  /// An empty plate at [scale] — every compartment unfilled.
  factory NutritionalSummary.empty(PortionScale scale) =>
      NutritionalSummary.fromComponents(
        scale: scale,
        components: const <PortionedComponent>[],
      );

  /// The scale every component was portioned at.
  final PortionScale scale;

  /// Per-compartment breakdown, always containing all three segments.
  final Map<PlateSegment, SegmentContribution> contributions;

  /// Macronutrients across the whole plate.
  final MacroProfile totalMacros;

  /// Total cooked mass on the plate, in grams.
  final double totalPortionGrams;

  /// Which compartments carry a selection.
  final Set<PlateSegment> filledSegments;

  /// Union of the allergens declared by every filled compartment.
  final Set<Allergen> allergens;

  /// Tags shared by *every* filled compartment.
  final Set<DietaryTag> dietaryTags;

  /// Total energy on the plate, in kilocalories.
  double get totalKilocalories => totalMacros.kilocalories;

  /// Total energy rounded for display. The capsule never shows decimals.
  int get displayKilocalories => totalKilocalories.round();

  /// Grams of protein, rounded for display.
  int get displayProteinGrams => totalMacros.proteinGrams.round();

  /// Whether all three compartments are filled — the balance-lock condition.
  bool get isComplete => filledSegments.length == PlateSegment.values.length;

  /// Whether nothing has been chosen yet.
  bool get isEmpty => filledSegments.isEmpty;

  /// How many compartments remain unchosen, in `0..3`.
  int get remainingSegmentCount =>
      PlateSegment.values.length - filledSegments.length;

  /// The next compartment to fill in canonical order, or `null` when complete.
  PlateSegment? get nextSegment {
    for (final PlateSegment segment in PlateSegment.buildOrder) {
      if (!filledSegments.contains(segment)) return segment;
    }
    return null;
  }

  /// The contribution record for [segment]; never null.
  SegmentContribution contributionFor(PlateSegment segment) =>
      contributions[segment] ?? SegmentContribution.empty(segment);

  /// The house energy band for this plate's scale.
  BalanceBand get band => BalanceBand.forScale(scale);

  /// How this plate reads relative to its band.
  PlateEnergyFraming get framing => band.classify(totalKilocalories);

  /// Share of total energy coming from protein, in `0.0..1.0`.
  double get proteinEnergyShare => totalKilocalories <= 0
      ? 0
      : totalMacros.proteinKilocalories / totalKilocalories;

  /// Share of total energy coming from carbohydrate, in `0.0..1.0`.
  double get carbohydrateEnergyShare => totalKilocalories <= 0
      ? 0
      : totalMacros.carbohydrateKilocalories / totalKilocalories;

  /// Share of total energy coming from fat, in `0.0..1.0`.
  double get fatEnergyShare =>
      totalKilocalories <= 0 ? 0 : totalMacros.fatKilocalories / totalKilocalories;

  /// Progress toward the band's nominal energy, clamped to `0.0..1.0`.
  ///
  /// Clamped so that an over-nominal plate renders a full ring rather than an
  /// arc that overshoots and reads as a penalty.
  double get nominalProgress =>
      (totalKilocalories / band.nominalKilocalories).clamp(0.0, 1.0);

  @override
  String toString() => 'NutritionalSummary(${scale.name}, '
      '$displayKilocalories kcal, '
      'P${displayProteinGrams}g, '
      '${filledSegments.length}/3 filled)';
}
