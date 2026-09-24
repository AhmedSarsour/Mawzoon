import 'ingredient_option.dart';
import 'mawzoon_catalog.dart';
import 'plate_segment.dart';
import 'recipe_calibration.dart';

/// Supplies the factor a component's raw draw moves by when its portion has
/// been recalibrated.
///
/// An interface so the inventory ledger can take one without depending on the
/// whole book, and so a test can state a factor directly.
// ignore: one_member_abstracts
abstract interface class PortionFactors {
  /// The factor for [componentId]. One when nothing has been calibrated.
  double portionFactorFor(String componentId);
}

/// Every component publishes the same figures it always did.
final class UncalibratedPortions implements PortionFactors {
  /// Creates the identity.
  const UncalibratedPortions();

  @override
  double portionFactorFor(String componentId) => 1;
}

/// The menu as the kitchen has actually measured it.
///
/// ## The one read point
///
/// [MawzoonCatalog] is the published menu — compile-time constants, a fixed
/// reference that a test can pin and a diff can review. A [RecipeBook] is the
/// menu *as served today*, the catalogue with the back office's measurements
/// laid over it. Everything that shows a guest a number goes through the book;
/// nothing reads the catalogue directly except the book itself.
///
/// The book is immutable. Calibrating produces a new book, and a screen
/// holding the old one keeps showing a consistent menu until it is handed the
/// new one — which is how a manager can save a change mid-service without a
/// half-updated plate appearing under anybody's thumb.
final class RecipeBook implements PortionFactors {
  const RecipeBook._(this._calibrations);

  /// The menu exactly as published.
  static const RecipeBook published = RecipeBook._(
    <String, RecipeCalibration>{},
  );

  final Map<String, RecipeCalibration> _calibrations;

  /// Every calibration in force, newest measurement per component.
  Map<String, RecipeCalibration> get calibrations =>
      Map<String, RecipeCalibration>.unmodifiable(_calibrations);

  /// Whether anything at all has been calibrated.
  bool get isPublished => _calibrations.isEmpty;

  /// The calibration in force for [componentId], if any.
  RecipeCalibration? calibrationFor(String componentId) =>
      _calibrations[componentId];

  /// A new book with [calibration] applied over this one.
  RecipeBook withCalibration(RecipeCalibration calibration) => RecipeBook._(
        <String, RecipeCalibration>{
          ..._calibrations,
          calibration.componentId: calibration,
        },
      );

  /// A new book with [componentId] back to what the menu publishes.
  RecipeBook withoutCalibration(String componentId) {
    if (!_calibrations.containsKey(componentId)) return this;
    final Map<String, RecipeCalibration> next =
        Map<String, RecipeCalibration>.of(_calibrations)..remove(componentId);
    return RecipeBook._(next);
  }

  /// [option] as measured, or unchanged when nothing has been calibrated.
  ///
  /// Rebuilds the concrete subclass rather than wrapping it, so a calibrated
  /// protein is still a [ProteinOption] and the grill station still reads its
  /// doneness off it.
  IngredientOption resolve(IngredientOption option) {
    final RecipeCalibration? calibration = _calibrations[option.id];
    if (calibration == null) return option;

    return switch (option) {
      ProteinOption() => ProteinOption(
          id: option.id,
          name: option.name,
          description: option.description,
          basePortionGrams: calibration.portionGrams,
          baseMacros: calibration.macros,
          method: option.method,
          allergens: option.allergens,
          dietaryTags: option.dietaryTags,
          glycemicIndex: option.glycemicIndex,
          surchargeMinorUnits: option.surchargeMinorUnits,
          kitchenNote: option.kitchenNote,
          doneness: option.doneness,
        ),
      CarbOption() => CarbOption(
          id: option.id,
          name: option.name,
          description: option.description,
          basePortionGrams: calibration.portionGrams,
          baseMacros: calibration.macros,
          method: option.method,
          allergens: option.allergens,
          dietaryTags: option.dietaryTags,
          glycemicIndex: option.glycemicIndex,
          surchargeMinorUnits: option.surchargeMinorUnits,
          kitchenNote: option.kitchenNote,
        ),
      FiberOption() => FiberOption(
          id: option.id,
          name: option.name,
          description: option.description,
          basePortionGrams: calibration.portionGrams,
          baseMacros: calibration.macros,
          method: option.method,
          allergens: option.allergens,
          dietaryTags: option.dietaryTags,
          glycemicIndex: option.glycemicIndex,
          surchargeMinorUnits: option.surchargeMinorUnits,
          kitchenNote: option.kitchenNote,
        ),
    };
  }

  /// The component with [id], as measured.
  IngredientOption? optionById(String id) {
    final IngredientOption? published = MawzoonCatalog.optionById(id);
    return published == null ? null : resolve(published);
  }

  /// Everything that fills [segment], as measured, in carousel order.
  List<IngredientOption> optionsFor(PlateSegment segment) => <IngredientOption>[
        for (final IngredientOption option
            in MawzoonCatalog.optionsFor(segment))
          resolve(option),
      ];

  /// The whole menu, as measured.
  List<IngredientOption> get all => <IngredientOption>[
        for (final IngredientOption option in MawzoonCatalog.all)
          resolve(option),
      ];

  @override
  double portionFactorFor(String componentId) {
    final RecipeCalibration? calibration = _calibrations[componentId];
    if (calibration == null) return 1;
    final IngredientOption? published = MawzoonCatalog.optionById(componentId);
    return published == null ? 1 : calibration.portionFactorAgainst(published);
  }

  @override
  String toString() => 'RecipeBook(${_calibrations.length} calibrated)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RecipeBook) return false;
    if (other._calibrations.length != _calibrations.length) return false;
    for (final MapEntry<String, RecipeCalibration> entry
        in _calibrations.entries) {
      if (!identical(other._calibrations[entry.key], entry.value)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(_calibrations.keys);
}
