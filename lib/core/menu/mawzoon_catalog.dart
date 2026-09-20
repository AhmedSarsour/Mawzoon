import '../localization/localized_text.dart';
import '../nutrition/macro_profile.dart';
import 'dietary_metadata.dart';
import 'ingredient_option.dart';
import 'plate_segment.dart';

/// The Mawzoon component catalogue: six proteins, six smart carbs, two vital
/// fibres.
///
/// Every [MacroProfile] here describes the **cooked, plated, standard**
/// portion as weighed in the kitchen — not raw mass, and not a per-100 g
/// reference figure. Energy is never listed: it is derived from these masses
/// by [MacroProfile.kilocalories], so the menu and the macro capsule cannot
/// disagree with each other.
///
/// Glycemic indices are the published values for the cooking method actually
/// used — roasted sweet potato is not boiled sweet potato, and basmati is a
/// genuinely low-GI rice where short-grain white is not.
///
/// Surcharges are in minor currency units (halalas). Zero means the component
/// is included in the base plate price.
abstract final class MawzoonCatalog {
  // ---------------------------------------------------------------------
  // Compartment one — Protein
  // ---------------------------------------------------------------------

  /// Smoked entrecôte — the richest cut on the menu.
  static const ProteinOption smokedEntrecote = ProteinOption(
    id: 'protein.smoked_entrecote',
    name: LocalizedText(ar: 'انتركوت مدخّن', en: 'Smoked Entrecôte'),
    description: LocalizedText(
      ar: 'شريحة انتركوت مدخّنة على الحطب، براحة عشر دقائق قبل التقطيع.',
      en: 'Wood-smoked ribeye, rested ten minutes before it meets the knife.',
    ),
    basePortionGrams: 140,
    baseMacros: MacroProfile(
      proteinGrams: 36,
      carbohydrateGrams: 0,
      fatGrams: 18,
      dietaryFiberGrams: 0,
      sodiumMilligrams: 360,
    ),
    method: CookingMethod.flameSeared,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
    },
    surchargeMinorUnits: 800,
  );

  /// Smashed lean beef — thin patties pressed hard onto the plancha.
  static const ProteinOption smashedLeanBeef = ProteinOption(
    id: 'protein.smashed_lean_beef',
    name: LocalizedText(ar: 'لحم بقري مسحوق قليل الدهن', en: 'Smashed Lean Beef'),
    description: LocalizedText(
      ar: 'أقراص رفيعة مضغوطة على الصاج حتى تتكوّن قشرة مقرمشة على الحافة.',
      en: 'Pressed thin on the plancha until the edges go lacy and crisp.',
    ),
    basePortionGrams: 140,
    baseMacros: MacroProfile(
      proteinGrams: 38,
      carbohydrateGrams: 1,
      fatGrams: 10,
      dietaryFiberGrams: 0,
      sodiumMilligrams: 390,
    ),
    method: CookingMethod.flameSeared,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
    },
  );

  /// Herb-grilled chicken breast — the leanest anchor on the menu.
  static const ProteinOption herbGrilledBreast = ProteinOption(
    id: 'protein.herb_grilled_breast',
    name: LocalizedText(
      ar: 'صدر دجاج مشوي بالأعشاب',
      en: 'Herb Grilled Breast',
    ),
    description: LocalizedText(
      ar: 'صدر دجاج منقوع بالليمون والزعتر والثوم، مشوي حتى يبقى طريًا.',
      en: 'Lemon, thyme and garlic marinade, grilled just short of firm.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 46.5,
      carbohydrateGrams: 0.5,
      fatGrams: 5.4,
      dietaryFiberGrams: 0,
      sodiumMilligrams: 380,
    ),
    method: CookingMethod.flameSeared,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
      DietaryTag.spiced,
    },
  );

  /// Pulled slow-cooked beef — eight hours, then shredded.
  static const ProteinOption pulledSlowCookedBeef = ProteinOption(
    id: 'protein.pulled_slow_cooked_beef',
    name: LocalizedText(
      ar: 'لحم بقري مسحوب مطهو ببطء',
      en: 'Pulled Slow-Cooked Beef',
    ),
    description: LocalizedText(
      ar: 'كتف بقري مطهو ثماني ساعات على حرارة منخفضة حتى يتفكّك بالشوكة.',
      en: 'Eight hours at low heat until the shoulder gives way to a fork.',
    ),
    basePortionGrams: 140,
    baseMacros: MacroProfile(
      proteinGrams: 37,
      carbohydrateGrams: 2,
      fatGrams: 12,
      dietaryFiberGrams: 0.3,
      sodiumMilligrams: 430,
    ),
    method: CookingMethod.slowSimmered,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
    },
    surchargeMinorUnits: 300,
  );

  /// Kofta spiced mince — seven spices, onion and parsley.
  static const ProteinOption koftaSpicedMince = ProteinOption(
    id: 'protein.kofta_spiced_mince',
    name: LocalizedText(ar: 'كفتة مفرومة بالبهارات', en: 'Kofta Spiced Mince'),
    description: LocalizedText(
      ar: 'لحم مفروم مع البقدونس والبصل وسبع بهارات، مشوي على السيخ.',
      en: 'Minced with parsley, onion and seven spices, grilled on skewers.',
    ),
    basePortionGrams: 140,
    baseMacros: MacroProfile(
      proteinGrams: 33,
      carbohydrateGrams: 3,
      fatGrams: 14,
      dietaryFiberGrams: 0.8,
      sodiumMilligrams: 420,
    ),
    method: CookingMethod.flameSeared,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
      DietaryTag.spiced,
    },
  );

  /// Marinated chicken thighs — the most forgiving cut, and the juiciest.
  static const ProteinOption marinatedThighs = ProteinOption(
    id: 'protein.marinated_thighs',
    name: LocalizedText(ar: 'أفخاذ دجاج متبّلة', en: 'Marinated Thighs'),
    description: LocalizedText(
      ar: 'أفخاذ منزوعة العظم منقوعة ليلة كاملة بالسماق والثوم والليمون.',
      en: 'Boned thighs left overnight in sumac, garlic and lemon.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 36,
      carbohydrateGrams: 1.5,
      fatGrams: 12,
      dietaryFiberGrams: 0,
      sodiumMilligrams: 410,
    ),
    method: CookingMethod.flameSeared,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
      DietaryTag.spiced,
    },
  );

  // ---------------------------------------------------------------------
  // Compartment two — Smart Carb
  // ---------------------------------------------------------------------

  /// Air-fried spiced potatoes — comfort food, without the fryer.
  static const CarbOption airFriedSpicedPotatoes = CarbOption(
    id: 'carb.air_fried_spiced_potatoes',
    name: LocalizedText(
      ar: 'بطاطس متبّلة مقلية بالهواء',
      en: 'Air-Fried Spiced Potatoes',
    ),
    description: LocalizedText(
      ar: 'مكعبات بطاطس بالبابريكا المدخنة، مقرمشة من الخارج وطرية من الداخل.',
      en: 'Smoked paprika cubes, shatteringly crisp outside and soft within.',
    ),
    basePortionGrams: 160,
    baseMacros: MacroProfile(
      proteinGrams: 3.5,
      carbohydrateGrams: 33,
      fatGrams: 4,
      dietaryFiberGrams: 3.5,
      sodiumMilligrams: 290,
    ),
    method: CookingMethod.airFried,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.spiced,
    },
    glycemicIndex: 75,
  );

  /// Steamed basmati — genuinely low-GI, unlike short-grain white rice.
  static const CarbOption steamedBasmati = CarbOption(
    id: 'carb.steamed_basmati',
    name: LocalizedText(ar: 'أرز بسمتي مطهو بالبخار', en: 'Steamed Basmati'),
    description: LocalizedText(
      ar: 'أرز بسمتي طويل الحبة مطهو بالبخار حتى تنفصل حبّاته.',
      en: 'Long-grain basmati steamed until every grain stands apart.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 4,
      carbohydrateGrams: 42,
      fatGrams: 0.6,
      dietaryFiberGrams: 1.2,
      sodiumMilligrams: 190,
    ),
    method: CookingMethod.steamed,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
    },
    glycemicIndex: 52,
  );

  /// Sweet potato wedges, oven-roasted.
  static const CarbOption sweetPotatoWedges = CarbOption(
    id: 'carb.sweet_potato_wedges',
    name: LocalizedText(
      ar: 'أصابع البطاطا الحلوة',
      en: 'Sweet Potato Wedges',
    ),
    description: LocalizedText(
      ar: 'أصابع بطاطا حلوة محمّصة بالفرن حتى تتكرمل حوافها.',
      en: 'Oven-roasted until the edges caramelise and catch.',
    ),
    basePortionGrams: 170,
    baseMacros: MacroProfile(
      proteinGrams: 3.2,
      carbohydrateGrams: 34,
      fatGrams: 3.5,
      dietaryFiberGrams: 5.3,
      sodiumMilligrams: 200,
    ),
    method: CookingMethod.ovenRoasted,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
    },
    glycemicIndex: 63,
  );

  /// Whole bulgur — the highest-fibre carb on the menu.
  static const CarbOption wholeBulgur = CarbOption(
    id: 'carb.whole_bulgur',
    name: LocalizedText(ar: 'برغل أسمر', en: 'Whole Bulgur'),
    description: LocalizedText(
      ar: 'برغل خشن مطهو على مرق الخضار مع البصل المكرمل.',
      en: 'Coarse bulgur simmered in vegetable stock with caramelised onion.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 6,
      carbohydrateGrams: 34,
      fatGrams: 1.5,
      dietaryFiberGrams: 7,
      sodiumMilligrams: 280,
    ),
    method: CookingMethod.slowSimmered,
    allergens: <Allergen>{Allergen.gluten},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.dairyFree,
    },
    glycemicIndex: 48,
  );

  /// Toasted quinoa — toasted dry before it ever sees liquid.
  static const CarbOption toastedQuinoa = CarbOption(
    id: 'carb.toasted_quinoa',
    name: LocalizedText(ar: 'كينوا محمّصة', en: 'Toasted Quinoa'),
    description: LocalizedText(
      ar: 'كينوا محمّصة على نار جافة قبل الطهي، مع النعناع والليمون.',
      en: 'Dry-toasted before cooking, finished with mint and lemon.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 8,
      carbohydrateGrams: 32,
      fatGrams: 4.5,
      dietaryFiberGrams: 4.5,
      sodiumMilligrams: 230,
    ),
    method: CookingMethod.slowSimmered,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
    },
    glycemicIndex: 53,
  );

  /// Whole wheat pasta — the lowest-GI carb on the menu.
  static const CarbOption wholeWheatPasta = CarbOption(
    id: 'carb.whole_wheat_pasta',
    name: LocalizedText(ar: 'معكرونة القمح الكامل', en: 'Whole Wheat Pasta'),
    description: LocalizedText(
      ar: 'معكرونة قمح كامل مسلوقة حتى الطراوة المتماسكة، بزيت زيتون وثوم.',
      en: 'Whole wheat, held at al dente, dressed in olive oil and garlic.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 8,
      carbohydrateGrams: 38,
      fatGrams: 1.6,
      dietaryFiberGrams: 5.5,
      sodiumMilligrams: 210,
    ),
    method: CookingMethod.slowSimmered,
    allergens: <Allergen>{Allergen.gluten},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.dairyFree,
    },
    glycemicIndex: 42,
  );

  // ---------------------------------------------------------------------
  // Compartment three — Vital Fiber
  // ---------------------------------------------------------------------

  /// Charred garden vegetables.
  static const FiberOption charredGardenVeggies = FiberOption(
    id: 'fiber.charred_garden_veggies',
    name: LocalizedText(
      ar: 'خضار الحديقة المشوية',
      en: 'Charred Garden Veggies',
    ),
    description: LocalizedText(
      ar: 'كوسا وفلفل وباذنجان وبصل أحمر، مشوية حتى التفحّم الخفيف.',
      en: 'Courgette, pepper, aubergine and red onion, grilled to a light char.',
    ),
    basePortionGrams: 130,
    baseMacros: MacroProfile(
      proteinGrams: 3.5,
      carbohydrateGrams: 11,
      fatGrams: 4.5,
      dietaryFiberGrams: 4.5,
      sodiumMilligrams: 150,
    ),
    method: CookingMethod.blistered,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.lowCarb,
    },
    glycemicIndex: 15,
  );

  /// Mediterranean sumac salad.
  static const FiberOption mediterraneanSumacSalad = FiberOption(
    id: 'fiber.mediterranean_sumac_salad',
    name: LocalizedText(
      ar: 'سلطة السماق المتوسطية',
      en: 'Mediterranean Sumac Salad',
    ),
    description: LocalizedText(
      ar: 'خيار وطماطم وبصل وبقدونس مع السماق وعصير الليمون وزيت الزيتون.',
      en: 'Cucumber, tomato, onion and parsley with sumac, lemon and olive oil.',
    ),
    basePortionGrams: 130,
    baseMacros: MacroProfile(
      proteinGrams: 2.5,
      carbohydrateGrams: 9,
      fatGrams: 5.5,
      dietaryFiberGrams: 3.2,
      sodiumMilligrams: 170,
    ),
    method: CookingMethod.freshDressed,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.lowCarb,
      DietaryTag.spiced,
    },
    glycemicIndex: 15,
  );

  // ---------------------------------------------------------------------
  // Collections and lookup
  // ---------------------------------------------------------------------

  /// All six protein options, in carousel order.
  static const List<ProteinOption> proteins = <ProteinOption>[
    smokedEntrecote,
    smashedLeanBeef,
    herbGrilledBreast,
    pulledSlowCookedBeef,
    koftaSpicedMince,
    marinatedThighs,
  ];

  /// All six smart-carb options, in carousel order.
  static const List<CarbOption> carbs = <CarbOption>[
    airFriedSpicedPotatoes,
    steamedBasmati,
    sweetPotatoWedges,
    wholeBulgur,
    toastedQuinoa,
    wholeWheatPasta,
  ];

  /// Both vital-fibre options, in carousel order.
  static const List<FiberOption> fibers = <FiberOption>[
    charredGardenVeggies,
    mediterraneanSumacSalad,
  ];

  /// Every component across all three compartments.
  static List<IngredientOption> get all => <IngredientOption>[
        ...proteins,
        ...carbs,
        ...fibers,
      ];

  /// The options available in [segment], typed as the shared supertype.
  static List<IngredientOption> optionsFor(PlateSegment segment) =>
      switch (segment) {
        PlateSegment.protein => proteins,
        PlateSegment.smartCarb => carbs,
        PlateSegment.vitalFiber => fibers,
      };

  /// Looks up any component by [id], or returns `null` if unknown.
  ///
  /// Used when rehydrating a cart, a re-order, or a deep link — never trust an
  /// identifier that arrived from outside the app.
  static IngredientOption? optionById(String id) {
    for (final IngredientOption option in all) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// Looks up a protein by [id], or returns `null`.
  static ProteinOption? proteinById(String id) =>
      _firstWhereOrNull<ProteinOption>(proteins, id);

  /// Looks up a smart carb by [id], or returns `null`.
  static CarbOption? carbById(String id) =>
      _firstWhereOrNull<CarbOption>(carbs, id);

  /// Looks up a vital fibre by [id], or returns `null`.
  static FiberOption? fiberById(String id) =>
      _firstWhereOrNull<FiberOption>(fibers, id);

  static T? _firstWhereOrNull<T extends IngredientOption>(
    List<T> options,
    String id,
  ) {
    for (final T option in options) {
      if (option.id == id) return option;
    }
    return null;
  }
}
