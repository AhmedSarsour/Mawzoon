import '../localization/localized_text.dart';
import '../nutrition/macro_profile.dart';
import '../nutrition/portion_scale.dart';
import 'dietary_metadata.dart';
import 'plate_segment.dart';

/// A single selectable component of a plate.
///
/// Sealed on purpose: the plate has exactly three compartments and there will
/// never be a fourth kind of component. Making the hierarchy sealed turns
/// "did you handle every compartment?" into a compile-time question.
///
/// [baseMacros] describe the **standard** cooked portion, i.e. the portion at
/// [PortionScale.standardBalance]. Larger portions are derived, never stored,
/// so a price list and a nutrition panel cannot disagree.
sealed class IngredientOption {
  /// Creates an option. Subclasses fix [segment].
  const IngredientOption({
    required this.id,
    required this.name,
    required this.description,
    required this.basePortionGrams,
    required this.baseMacros,
    required this.method,
    required this.allergens,
    required this.dietaryTags,
    this.glycemicIndex = 0,
    this.surchargeMinorUnits = 0,
    this.kitchenNote,
  })  : assert(id.length > 0, 'id must not be empty'),
        assert(basePortionGrams > 0, 'basePortionGrams must be positive'),
        assert(surchargeMinorUnits >= 0, 'surcharge must be non-negative'),
        assert(
          glycemicIndex >= 0 && glycemicIndex <= 110,
          'glycemicIndex is a 0-110 scale against pure glucose',
        );

  /// Stable identifier, used for cart lines, analytics and deep links.
  final String id;

  /// The dish name as printed on the menu.
  final LocalizedText name;

  /// A single appetising sentence. Sensory language, never nutritional guilt.
  final LocalizedText description;

  /// Cooked mass of the standard portion, in grams.
  final double basePortionGrams;

  /// Macronutrients of the standard portion.
  final MacroProfile baseMacros;

  /// How the component is cooked.
  final CookingMethod method;

  /// Declared allergens. An empty set is a positive assertion of absence.
  final Set<Allergen> allergens;

  /// Dietary properties of the component.
  final Set<DietaryTag> dietaryTags;

  /// A line for whoever is cooking this, not for the guest.
  ///
  /// Dressing, finish, holding instruction — the things a kitchen display has
  /// to show and a menu never should. It lives here because a second table of
  /// prep notes keyed by dish id is a second thing to keep in step, and it
  /// will not be kept in step.
  final LocalizedText? kitchenNote;

  /// Glycemic index on the standard 0-110 scale against pure glucose.
  ///
  /// Zero for a component with no digestible carbohydrate, where the measure
  /// is undefined rather than low — it contributes nothing to glycemic load
  /// either way, so the distinction never reaches a figure a guest sees.
  final int glycemicIndex;

  /// Optional upcharge over the base plate price, in minor currency units
  /// (halalas / fils). Zero for most components.
  final int surchargeMinorUnits;

  /// Which compartment of the platter this component occupies.
  PlateSegment get segment;

  /// Energy of the standard portion, in kilocalories.
  double get baseKilocalories => baseMacros.kilocalories;

  /// Glycemic load of the standard portion: GI weighted by the digestible
  /// carbohydrate this component actually contributes.
  double get baseGlycemicLoad =>
      glycemicIndex * baseMacros.netCarbohydrateGrams / 100;

  /// Resolves this option to a concrete portion at [scale].
  PortionedComponent atScale(PortionScale scale) {
    final double factor = scale.factorFor(segment);
    return PortionedComponent._(
      option: this,
      scale: scale,
      portionGrams: basePortionGrams * factor,
      macros: baseMacros * factor,
    );
  }

  @override
  String toString() => '${segment.name}:$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IngredientOption &&
          other.runtimeType == runtimeType &&
          other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, id);
}

/// A protein component — the anchor compartment.
final class ProteinOption extends IngredientOption {
  /// Creates a protein option.
  const ProteinOption({
    required super.id,
    required super.name,
    required super.description,
    required super.basePortionGrams,
    required super.baseMacros,
    required super.method,
    required super.allergens,
    required super.dietaryTags,
    super.glycemicIndex,
    super.surchargeMinorUnits,
    super.kitchenNote,
    this.doneness = Doneness.mediumWell,
  });

  /// How this cut is cooked by default.
  ///
  /// Typed rather than a note, because the grill station reads it every single
  /// ticket and a free-text field would eventually say "med" on one and
  /// "Medium" on the next.
  final Doneness doneness;

  @override
  PlateSegment get segment => PlateSegment.protein;
}

/// A smart-carbohydrate component — the energy compartment.
final class CarbOption extends IngredientOption {
  /// Creates a carbohydrate option.
  const CarbOption({
    required super.id,
    required super.name,
    required super.description,
    required super.basePortionGrams,
    required super.baseMacros,
    required super.method,
    required super.allergens,
    required super.dietaryTags,
    super.glycemicIndex,
    super.surchargeMinorUnits,
    super.kitchenNote,
  });

  @override
  PlateSegment get segment => PlateSegment.smartCarb;
}

/// A vital-fibre component — the greens compartment.
final class FiberOption extends IngredientOption {
  /// Creates a fibre option.
  const FiberOption({
    required super.id,
    required super.name,
    required super.description,
    required super.basePortionGrams,
    required super.baseMacros,
    required super.method,
    required super.allergens,
    required super.dietaryTags,
    super.glycemicIndex,
    super.surchargeMinorUnits,
    super.kitchenNote,
  });

  @override
  PlateSegment get segment => PlateSegment.vitalFiber;
}

/// An [IngredientOption] resolved to a concrete portion at a given
/// [PortionScale].
///
/// Constructed only through [IngredientOption.atScale] so that mass and
/// macros are always scaled by the same factor and can never diverge.
final class PortionedComponent {
  const PortionedComponent._({
    required this.option,
    required this.scale,
    required this.portionGrams,
    required this.macros,
  });

  /// The underlying menu option.
  final IngredientOption option;

  /// The scale this portion was computed at.
  final PortionScale scale;

  /// Cooked mass of this portion, in grams.
  final double portionGrams;

  /// Macronutrients of this portion.
  final MacroProfile macros;

  /// Which compartment this portion fills.
  PlateSegment get segment => option.segment;

  /// Energy of this portion, in kilocalories.
  double get kilocalories => macros.kilocalories;

  /// Glycemic load of this portion. Scales with the carbohydrate it carries,
  /// because glycemic index is a property of the food and load is a property
  /// of the serving.
  double get glycemicLoad =>
      option.glycemicIndex * macros.netCarbohydrateGrams / 100;

  @override
  String toString() =>
      'PortionedComponent(${option.id}, ${portionGrams.round()}g, '
      '${kilocalories.round()} kcal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PortionedComponent &&
          other.option == option &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(option, scale);
}
