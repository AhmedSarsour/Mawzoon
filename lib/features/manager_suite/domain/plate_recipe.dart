import '../../../core/localization/localized_text.dart';
import '../../../core/measure/quantity.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/mawzoon_catalog.dart';
import '../../../core/menu/plate_segment.dart';
import '../../../core/nutrition/portion_scale.dart';
import 'raw_ingredient.dart';

/// One draw on the store, per standard portion of one menu component.
///
/// The amount is **raw**, the portion it serves is **cooked**. That gap is the
/// yield, and it is the single most common way a stock system ends up lying:
/// 220g of potato becomes a 160g portion of chips, and a system that deducts
/// 160g of potato runs out of potato two days early and cannot say why.
final class RecipeLine {
  /// Creates a line.
  ///
  /// [amount] must be stated in [ingredient]'s own unit — the constructor
  /// refuses anything else rather than silently converting, because there is
  /// no honest conversion between 5ml of oil and 5g of it.
  RecipeLine({required this.ingredient, required this.amount, this.note})
      : assert(
          amount.unit == ingredient.unit,
          'a recipe line must be stated in the ingredient\'s own unit',
        ),
        assert(
          amount.minorUnits > 0,
          'a line that draws nothing is not a line',
        );

  /// What is drawn.
  final RawIngredient ingredient;

  /// How much, raw, for one standard portion.
  final Quantity amount;

  /// Why the number is what it is, where it is not obvious.
  final LocalizedText? note;

  /// The draw for one portion of a component in [segment] at [scale].
  ///
  /// Scales by the same factor the plate's own portion does, so a recipe and
  /// the nutrition panel beside it can never describe different plates.
  ///
  /// [portionFactor] carries a recalibration through: a manager who measures
  /// the portion 10% heavier has changed what the kitchen draws, and a store
  /// that does not follow the recipe is wrong from the moment the recipe
  /// changes.
  Quantity atScale(
    PortionScale scale, {
    required PlateSegment segment,
    double portionFactor = 1.0,
  }) =>
      amount * (scale.factorFor(segment) * portionFactor);

  @override
  String toString() => 'RecipeLine(${ingredient.id}, $amount)';
}

/// What one menu component costs the store.
///
/// Keyed by the component's id rather than holding the component, so a recipe
/// survives a recalibration of the dish it belongs to: the manager who changes
/// the measured protein in a chicken breast is not changing which chicken the
/// kitchen draws.
final class PlateRecipe {
  /// Creates a recipe.
  PlateRecipe({required this.componentId, required this.lines})
      : assert(lines.isNotEmpty, 'a component draws on something');

  /// The [IngredientOption.id] this makes.
  final String componentId;

  /// Everything it draws, in the order the cook uses them.
  final List<RecipeLine> lines;

  /// The whole draw for one portion of a component in [segment] at [scale].
  Map<RawIngredient, Quantity> drawAt(
    PortionScale scale, {
    required PlateSegment segment,
    double portionFactor = 1.0,
  }) {
    final Map<RawIngredient, Quantity> draw = <RawIngredient, Quantity>{};
    for (final RecipeLine line in lines) {
      final Quantity amount = line.atScale(
        scale,
        segment: segment,
        portionFactor: portionFactor,
      );
      final Quantity? existing = draw[line.ingredient];
      draw[line.ingredient] = existing == null ? amount : existing + amount;
    }
    return draw;
  }

  /// The yield of the headline ingredient: cooked grams out per raw gram in.
  ///
  /// Only meaningful where the first line is the component's main mass and is
  /// weighed. It is shown to a manager as a sanity check — a chicken breast
  /// yielding 95% has been mis-entered, and a system that will not say so is
  /// one that will happily order a week of the wrong thing.
  double? yieldAgainst(IngredientOption option) {
    final RecipeLine head = lines.first;
    if (head.ingredient.unit != MeasureUnit.gram) return null;
    return option.basePortionGrams / head.amount.amount;
  }

  @override
  String toString() => 'PlateRecipe($componentId, ${lines.length} lines)';
}

/// Every menu component's draw on the store.
///
/// The numbers are cooking yields, not guesses: grilled poultry and beef lose
/// roughly a quarter to a third of their raw weight to water and rendered fat;
/// a dry grain gains two to three times its weight from the water it absorbs,
/// so a 150g cooked portion of basmati is about 55g of dry rice.
abstract final class MawzoonRecipes {
  /// Recipes by component id.
  static final Map<String, PlateRecipe> _byComponent = <String, PlateRecipe>{
    for (final PlateRecipe recipe in all) recipe.componentId: recipe,
  };

  /// Every recipe, in menu order.
  static final List<PlateRecipe> all = <PlateRecipe>[
    // -- Proteins ---------------------------------------------------------
    PlateRecipe(
      componentId: MawzoonCatalog.smokedEntrecote.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.ribeye,
          amount: Quantity.grams(205),
          note: const LocalizedText(
            ar: 'فقد ٣٠٪ في التدخين والراحة',
            en: '30% loss to the smoke and the rest',
          ),
        ),
        RecipeLine(
          ingredient: RawStore.houseSpiceBlend,
          amount: Quantity.grams(4),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.smashedLeanBeef.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.leanBeefMince,
          amount: Quantity.grams(190),
        ),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(4),
          note: const LocalizedText(
            ar: 'للصاج، لا على اللحم',
            en: 'For the plancha, not the patty',
          ),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.herbGrilledBreast.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.chickenBreast,
          amount: Quantity.grams(210),
        ),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(6),
        ),
        RecipeLine(
          ingredient: RawStore.houseSpiceBlend,
          amount: Quantity.grams(3),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.pulledSlowCookedBeef.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.beefChuck,
          amount: Quantity.grams(240),
          note: const LocalizedText(
            ar: 'الطهي البطيء يفقد ٤٠٪',
            en: 'A long braise gives up 40%',
          ),
        ),
        RecipeLine(
          ingredient: RawStore.redOnion,
          amount: Quantity.grams(25),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.koftaSpicedMince.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.koftaMince,
          amount: Quantity.grams(185),
        ),
        RecipeLine(ingredient: RawStore.parsley, amount: Quantity.grams(8)),
        RecipeLine(
          ingredient: RawStore.houseSpiceBlend,
          amount: Quantity.grams(5),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.marinatedThighs.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.chickenThigh,
          amount: Quantity.grams(200),
        ),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(5),
        ),
        RecipeLine(ingredient: RawStore.lemon, amount: Quantity.pieces(0.25)),
      ],
    ),

    // -- Carbohydrates ----------------------------------------------------
    PlateRecipe(
      componentId: MawzoonCatalog.airFriedSpicedPotatoes.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.potato,
          amount: Quantity.grams(220),
          note: const LocalizedText(
            ar: 'مغسولة بقشرها، الفقد في التقشير والطهي',
            en: 'Scrubbed, skin on — loss is trim and cook',
          ),
        ),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(5),
        ),
        RecipeLine(
          ingredient: RawStore.houseSpiceBlend,
          amount: Quantity.grams(3),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.steamedBasmati.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.basmatiRice,
          amount: Quantity.grams(55),
          note: const LocalizedText(
            ar: 'وزن جاف — يمتص نحو ثلاثة أضعافه',
            en: 'Dry weight — it takes on about three times this',
          ),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.sweetPotatoWedges.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.sweetPotato,
          amount: Quantity.grams(230),
        ),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(7),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.wholeBulgur.id,
      lines: <RecipeLine>[
        RecipeLine(ingredient: RawStore.bulgur, amount: Quantity.grams(60)),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(4),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.toastedQuinoa.id,
      lines: <RecipeLine>[
        RecipeLine(ingredient: RawStore.quinoa, amount: Quantity.grams(52)),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(4),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.wholeWheatPasta.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.wholeWheatPasta,
          amount: Quantity.grams(65),
        ),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(5),
        ),
      ],
    ),

    // -- Vital fibre ------------------------------------------------------
    PlateRecipe(
      componentId: MawzoonCatalog.charredGardenVeggies.id,
      lines: <RecipeLine>[
        RecipeLine(
          ingredient: RawStore.gardenVegetables,
          amount: Quantity.grams(175),
        ),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(6),
        ),
      ],
    ),
    PlateRecipe(
      componentId: MawzoonCatalog.mediterraneanSumacSalad.id,
      lines: <RecipeLine>[
        RecipeLine(ingredient: RawStore.cucumber, amount: Quantity.grams(55)),
        RecipeLine(ingredient: RawStore.tomato, amount: Quantity.grams(50)),
        RecipeLine(ingredient: RawStore.redOnion, amount: Quantity.grams(15)),
        RecipeLine(ingredient: RawStore.parsley, amount: Quantity.grams(10)),
        RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.millilitres(8),
        ),
        RecipeLine(ingredient: RawStore.lemon, amount: Quantity.pieces(0.2)),
        RecipeLine(ingredient: RawStore.sumac, amount: Quantity.grams(2)),
      ],
    ),
  ];

  /// The recipe for [componentId], or `null` if the component has none.
  static PlateRecipe? forComponent(String componentId) =>
      _byComponent[componentId];

  /// The recipe for [option].
  static PlateRecipe? forOption(IngredientOption option) =>
      _byComponent[option.id];

  /// Every component that draws on [ingredient].
  static List<String> componentsUsing(RawIngredient ingredient) => <String>[
        for (final PlateRecipe recipe in all)
          if (recipe.lines.any((RecipeLine l) => l.ingredient == ingredient))
            recipe.componentId,
      ];
}
