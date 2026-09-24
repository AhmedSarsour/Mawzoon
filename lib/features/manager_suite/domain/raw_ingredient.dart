import '../../../core/localization/localized_text.dart';
import '../../../core/measure/quantity.dart';

/// Where in the kitchen an ingredient is kept.
///
/// A manager counting stock walks the room, not the alphabet. Grouping by
/// storage is the difference between one circuit of the kitchen and four.
enum StorageArea {
  /// Walk-in chiller: proteins and cut produce.
  chiller(label: LocalizedText(ar: 'المبرّد', en: 'Chiller')),

  /// Dry store: grains, pulses, spices, oils.
  dryStore(label: LocalizedText(ar: 'المخزن الجاف', en: 'Dry store')),

  /// Produce racks: whole vegetables held at room temperature.
  produce(label: LocalizedText(ar: 'الخضار', en: 'Produce'));

  const StorageArea({required this.label});

  /// The area's name on a stock sheet.
  final LocalizedText label;
}

/// Something the kitchen buys, holds and draws down.
///
/// Deliberately *not* a menu item. "Air-Fried Spiced Potatoes" is a dish; the
/// potato, the oil and the spice blend it draws on are three separate things
/// with three separate suppliers, three delivery schedules and three ways of
/// running out. Collapsing them into the dish is what makes a stock system
/// unable to answer "why can I not sell this".
final class RawIngredient {
  /// Creates an ingredient.
  const RawIngredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.area,
    this.shelfLifeDays,
  }) : assert(id.length > 0, 'an ingredient needs an id');

  /// Stable identifier, used by recipe lines and delivery notes.
  final String id;

  /// What it is called on the stock sheet.
  final LocalizedText name;

  /// How it is counted. Every quantity of this ingredient carries this unit,
  /// and a recipe line that states another one will not construct.
  final MeasureUnit unit;

  /// Where it lives.
  final StorageArea area;

  /// How long it keeps once delivered, where that is short enough to matter.
  ///
  /// Null for a dry good that outlives any reasonable stock rotation. It is
  /// not a use-by date — that belongs to a specific delivery, not to the
  /// ingredient — but it is what tells a manager that ordering three days of
  /// cucumber is ordering two days of cucumber and a day of waste.
  final int? shelfLifeDays;

  /// A zero amount in this ingredient's own unit.
  Quantity get none => Quantity.zeroIn(unit);

  /// Builds a quantity of this ingredient from a bare number.
  ///
  /// The single place a raw number becomes a measured amount, so an ingredient
  /// counted in millilitres can never acquire a quantity in grams.
  Quantity of(num amount) => switch (unit) {
        MeasureUnit.gram => Quantity.grams(amount),
        MeasureUnit.millilitre => Quantity.millilitres(amount),
        MeasureUnit.piece => Quantity.pieces(amount),
      };

  @override
  String toString() => 'RawIngredient($id)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RawIngredient && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Everything Mawzoon buys.
///
/// Flat and explicit, like the menu catalogue it feeds. A store list generated
/// from the recipes would be shorter to write and impossible to audit: the
/// supplier, the unit and the storage area are facts about the purchase, not
/// about any dish that happens to use it.
abstract final class RawStore {
  // -- Proteins -----------------------------------------------------------

  /// Whole ribeye, trimmed by the butcher.
  static const RawIngredient ribeye = RawIngredient(
    id: 'raw.beef_ribeye',
    name: LocalizedText(ar: 'انتركوت بقري', en: 'Beef ribeye'),
    unit: MeasureUnit.gram,
    area: StorageArea.chiller,
    shelfLifeDays: 4,
  );

  /// Lean mince, 10% fat, for the plancha patties.
  static const RawIngredient leanBeefMince = RawIngredient(
    id: 'raw.lean_beef_mince',
    name: LocalizedText(ar: 'لحم بقري مفروم قليل الدهن', en: 'Lean beef mince'),
    unit: MeasureUnit.gram,
    area: StorageArea.chiller,
    shelfLifeDays: 2,
  );

  /// Seasoned mince for kofta — a different fat ratio and a different order.
  static const RawIngredient koftaMince = RawIngredient(
    id: 'raw.kofta_mince',
    name: LocalizedText(ar: 'مفروم الكفتة', en: 'Kofta mince'),
    unit: MeasureUnit.gram,
    area: StorageArea.chiller,
    shelfLifeDays: 2,
  );

  /// Chuck for the slow cooker.
  static const RawIngredient beefChuck = RawIngredient(
    id: 'raw.beef_chuck',
    name: LocalizedText(ar: 'رقبة بقري', en: 'Beef chuck'),
    unit: MeasureUnit.gram,
    area: StorageArea.chiller,
    shelfLifeDays: 4,
  );

  /// Skinless breast.
  static const RawIngredient chickenBreast = RawIngredient(
    id: 'raw.chicken_breast',
    name: LocalizedText(ar: 'صدور دجاج', en: 'Chicken breast'),
    unit: MeasureUnit.gram,
    area: StorageArea.chiller,
    shelfLifeDays: 3,
  );

  /// Boneless thigh.
  static const RawIngredient chickenThigh = RawIngredient(
    id: 'raw.chicken_thigh',
    name: LocalizedText(ar: 'أفخاذ دجاج', en: 'Chicken thigh'),
    unit: MeasureUnit.gram,
    area: StorageArea.chiller,
    shelfLifeDays: 3,
  );

  // -- Carbohydrates ------------------------------------------------------

  /// Waxy potatoes, delivered unwashed.
  static const RawIngredient potato = RawIngredient(
    id: 'raw.potato',
    name: LocalizedText(ar: 'بطاطس', en: 'Potato'),
    unit: MeasureUnit.gram,
    area: StorageArea.produce,
    shelfLifeDays: 14,
  );

  /// Sweet potato.
  static const RawIngredient sweetPotato = RawIngredient(
    id: 'raw.sweet_potato',
    name: LocalizedText(ar: 'بطاطا حلوة', en: 'Sweet potato'),
    unit: MeasureUnit.gram,
    area: StorageArea.produce,
    shelfLifeDays: 12,
  );

  /// Aged basmati, dry weight.
  static const RawIngredient basmatiRice = RawIngredient(
    id: 'raw.basmati_rice',
    name: LocalizedText(ar: 'أرز بسمتي', en: 'Basmati rice'),
    unit: MeasureUnit.gram,
    area: StorageArea.dryStore,
  );

  /// Coarse whole bulgur, dry weight.
  static const RawIngredient bulgur = RawIngredient(
    id: 'raw.bulgur',
    name: LocalizedText(ar: 'برغل أسمر', en: 'Whole bulgur'),
    unit: MeasureUnit.gram,
    area: StorageArea.dryStore,
  );

  /// Quinoa, dry weight.
  static const RawIngredient quinoa = RawIngredient(
    id: 'raw.quinoa',
    name: LocalizedText(ar: 'كينوا', en: 'Quinoa'),
    unit: MeasureUnit.gram,
    area: StorageArea.dryStore,
  );

  /// Whole-wheat pasta, dry weight.
  static const RawIngredient wholeWheatPasta = RawIngredient(
    id: 'raw.whole_wheat_pasta',
    name: LocalizedText(ar: 'معكرونة قمح كامل', en: 'Whole-wheat pasta'),
    unit: MeasureUnit.gram,
    area: StorageArea.dryStore,
  );

  // -- Produce and finishing ---------------------------------------------

  /// The mixed vegetable pack for the grill: courgette, pepper, onion.
  static const RawIngredient gardenVegetables = RawIngredient(
    id: 'raw.garden_vegetables',
    name: LocalizedText(ar: 'خضار مشكّلة', en: 'Garden vegetables'),
    unit: MeasureUnit.gram,
    area: StorageArea.produce,
    shelfLifeDays: 5,
  );

  /// Cucumber.
  static const RawIngredient cucumber = RawIngredient(
    id: 'raw.cucumber',
    name: LocalizedText(ar: 'خيار', en: 'Cucumber'),
    unit: MeasureUnit.gram,
    area: StorageArea.produce,
    shelfLifeDays: 5,
  );

  /// Tomato.
  static const RawIngredient tomato = RawIngredient(
    id: 'raw.tomato',
    name: LocalizedText(ar: 'طماطم', en: 'Tomato'),
    unit: MeasureUnit.gram,
    area: StorageArea.produce,
    shelfLifeDays: 6,
  );

  /// Flat-leaf parsley.
  static const RawIngredient parsley = RawIngredient(
    id: 'raw.parsley',
    name: LocalizedText(ar: 'بقدونس', en: 'Parsley'),
    unit: MeasureUnit.gram,
    area: StorageArea.produce,
    shelfLifeDays: 3,
  );

  /// Red onion.
  static const RawIngredient redOnion = RawIngredient(
    id: 'raw.red_onion',
    name: LocalizedText(ar: 'بصل أحمر', en: 'Red onion'),
    unit: MeasureUnit.gram,
    area: StorageArea.produce,
    shelfLifeDays: 20,
  );

  /// Lemons, counted rather than weighed — nobody weighs a lemon.
  static const RawIngredient lemon = RawIngredient(
    id: 'raw.lemon',
    name: LocalizedText(ar: 'ليمون', en: 'Lemon'),
    unit: MeasureUnit.piece,
    area: StorageArea.produce,
    shelfLifeDays: 10,
  );

  /// Extra-virgin olive oil.
  static const RawIngredient oliveOil = RawIngredient(
    id: 'raw.olive_oil',
    name: LocalizedText(ar: 'زيت زيتون', en: 'Olive oil'),
    unit: MeasureUnit.millilitre,
    area: StorageArea.dryStore,
  );

  /// The house spice blend.
  static const RawIngredient houseSpiceBlend = RawIngredient(
    id: 'raw.house_spice_blend',
    name: LocalizedText(ar: 'خلطة البهارات', en: 'House spice blend'),
    unit: MeasureUnit.gram,
    area: StorageArea.dryStore,
  );

  /// Ground sumac.
  static const RawIngredient sumac = RawIngredient(
    id: 'raw.sumac',
    name: LocalizedText(ar: 'سماق', en: 'Sumac'),
    unit: MeasureUnit.gram,
    area: StorageArea.dryStore,
  );

  /// Everything the kitchen buys, in stock-sheet order.
  static const List<RawIngredient> all = <RawIngredient>[
    ribeye,
    leanBeefMince,
    koftaMince,
    beefChuck,
    chickenBreast,
    chickenThigh,
    potato,
    sweetPotato,
    basmatiRice,
    bulgur,
    quinoa,
    wholeWheatPasta,
    gardenVegetables,
    cucumber,
    tomato,
    parsley,
    redOnion,
    lemon,
    oliveOil,
    houseSpiceBlend,
    sumac,
  ];

  /// The ingredients kept in [area], in stock-sheet order.
  static List<RawIngredient> inArea(StorageArea area) => all
      .where((RawIngredient ingredient) => ingredient.area == area)
      .toList(growable: false);

  /// The ingredient with [id], or `null`.
  static RawIngredient? byId(String id) {
    for (final RawIngredient ingredient in all) {
      if (ingredient.id == id) return ingredient;
    }
    return null;
  }
}
