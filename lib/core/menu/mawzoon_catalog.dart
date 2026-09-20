import '../localization/localized_text.dart';
import '../nutrition/macro_profile.dart';
import 'dietary_metadata.dart';
import 'ingredient_option.dart';
import 'plate_segment.dart';

/// The Mawzoon component catalogue: six proteins, six smart carbs, three
/// vital fibres.
///
/// Every [MacroProfile] here describes the **cooked, plated, standard**
/// portion as weighed in the kitchen — not raw mass, and not a per-100 g
/// reference figure. Energy is never listed: it is derived from these masses
/// by [MacroProfile.kilocalories], so the menu and the macro capsule cannot
/// disagree with each other.
///
/// Surcharges are in minor currency units (halalas). Zero means the component
/// is included in the base plate price.
abstract final class MawzoonCatalog {
  // ---------------------------------------------------------------------
  // Compartment one — Protein
  // ---------------------------------------------------------------------

  /// Flame-seared chicken breast, the house anchor.
  static const ProteinOption flameSearedChicken = ProteinOption(
    id: 'protein.flame_seared_chicken',
    name: LocalizedText(
      ar: 'صدر دجاج مشوي على اللهب',
      en: 'Flame-Seared Chicken Breast',
    ),
    description: LocalizedText(
      ar: 'منقوع بالليمون والثوم، مشوي على لهب مباشر حتى يكتسب قشرة ذهبية.',
      en: 'Lemon and garlic marinated, seared over open flame to a gold crust.',
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

  /// Charcoal-charred beef tenderloin.
  static const ProteinOption charredTenderloin = ProteinOption(
    id: 'protein.charred_tenderloin',
    name: LocalizedText(
      ar: 'فيليه بقري مشوي على الفحم',
      en: 'Charred Beef Tenderloin',
    ),
    description: LocalizedText(
      ar: 'قطع فيليه طرية، مشوية على الفحم مع فلفل أسود مجروش وملح البحر.',
      en: 'Tender fillet over charcoal, cracked black pepper and sea salt.',
    ),
    basePortionGrams: 140,
    baseMacros: MacroProfile(
      proteinGrams: 39,
      carbohydrateGrams: 0,
      fatGrams: 11,
      dietaryFiberGrams: 0,
      sodiumMilligrams: 340,
    ),
    method: CookingMethod.flameSeared,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
    },
    surchargeMinorUnits: 500,
  );

  /// Herb-grilled salmon fillet.
  static const ProteinOption herbGrilledSalmon = ProteinOption(
    id: 'protein.herb_grilled_salmon',
    name: LocalizedText(
      ar: 'سلمون مشوي بالأعشاب',
      en: 'Herb-Grilled Salmon',
    ),
    description: LocalizedText(
      ar: 'فيليه سلمون بقشرة مقرمشة، مع الشبت والبقدونس وزيت الزيتون.',
      en: 'Crisp-skinned fillet with dill, parsley and cold-pressed olive oil.',
    ),
    basePortionGrams: 140,
    baseMacros: MacroProfile(
      proteinGrams: 35,
      carbohydrateGrams: 0,
      fatGrams: 16,
      dietaryFiberGrams: 0,
      sodiumMilligrams: 300,
    ),
    method: CookingMethod.flameSeared,
    allergens: <Allergen>{Allergen.fish},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
    },
    surchargeMinorUnits: 700,
  );

  /// Spiced lamb kofta.
  static const ProteinOption spicedLambKofta = ProteinOption(
    id: 'protein.spiced_lamb_kofta',
    name: LocalizedText(
      ar: 'كفتة لحم الغنم بالبهارات',
      en: 'Spiced Lamb Kofta',
    ),
    description: LocalizedText(
      ar: 'لحم غنم مفروم مع البقدونس والبصل وسبع بهارات، مشوي على السيخ.',
      en: 'Minced lamb with parsley, onion and seven spices, grilled on skewers.',
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
    surchargeMinorUnits: 300,
  );

  /// Za'atar shrimp.
  static const ProteinOption zaatarShrimp = ProteinOption(
    id: 'protein.zaatar_shrimp',
    name: LocalizedText(ar: 'روبيان بالزعتر', en: "Za'atar Shrimp"),
    description: LocalizedText(
      ar: 'روبيان جامبو محمّر سريعًا بالزعتر البري والليمون وزيت الزيتون.',
      en: 'Jumbo shrimp flashed hot with wild thyme, lemon and olive oil.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 33,
      carbohydrateGrams: 3,
      fatGrams: 8,
      dietaryFiberGrams: 0.5,
      sodiumMilligrams: 460,
    ),
    method: CookingMethod.blistered,
    allergens: <Allergen>{Allergen.shellfish, Allergen.sesame},
    dietaryTags: <DietaryTag>{
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.highProtein,
      DietaryTag.lowCarb,
      DietaryTag.spiced,
    },
    surchargeMinorUnits: 600,
  );

  /// Smoked harissa tofu — the plant-based anchor.
  static const ProteinOption smokedHarissaTofu = ProteinOption(
    id: 'protein.smoked_harissa_tofu',
    name: LocalizedText(
      ar: 'توفو مدخن بالهريسة',
      en: 'Smoked Harissa Tofu',
    ),
    description: LocalizedText(
      ar: 'توفو صلب مدخن، مغلّف بالهريسة المنزلية ومشوي حتى الحواف المقرمشة.',
      en: 'Firm smoked tofu lacquered in house harissa, roasted to crisp edges.',
    ),
    basePortionGrams: 160,
    baseMacros: MacroProfile(
      proteinGrams: 27,
      carbohydrateGrams: 7,
      fatGrams: 13,
      dietaryFiberGrams: 2.2,
      sodiumMilligrams: 390,
    ),
    method: CookingMethod.ovenRoasted,
    allergens: <Allergen>{Allergen.soy},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
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
  );

  /// Saffron basmati rice.
  static const CarbOption saffronBasmati = CarbOption(
    id: 'carb.saffron_basmati',
    name: LocalizedText(ar: 'أرز بسمتي بالزعفران', en: 'Saffron Basmati'),
    description: LocalizedText(
      ar: 'أرز بسمتي طويل الحبة، منقوع بالزعفران والهيل حتى تنفصل حبّاته.',
      en: 'Long-grain basmati steeped with saffron and cardamom, grain-separate.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 4,
      carbohydrateGrams: 42,
      fatGrams: 2,
      dietaryFiberGrams: 1.2,
      sodiumMilligrams: 210,
    ),
    method: CookingMethod.slowSimmered,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
    },
  );

  /// Freekeh pilaf — smoked green wheat.
  static const CarbOption freekehPilaf = CarbOption(
    id: 'carb.freekeh_pilaf',
    name: LocalizedText(ar: 'فريكة مطهوة بالخضار', en: 'Freekeh Pilaf'),
    description: LocalizedText(
      ar: 'فريكة مدخنة مطهوة على مرق الخضار مع الكرفس والجزر.',
      en: 'Smoked green wheat simmered in vegetable stock with celery and carrot.',
    ),
    basePortionGrams: 150,
    baseMacros: MacroProfile(
      proteinGrams: 7,
      carbohydrateGrams: 36,
      fatGrams: 3,
      dietaryFiberGrams: 6.5,
      sodiumMilligrams: 320,
    ),
    method: CookingMethod.slowSimmered,
    allergens: <Allergen>{Allergen.gluten},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.dairyFree,
    },
  );

  /// Sweet potato mash.
  static const CarbOption sweetPotatoMash = CarbOption(
    id: 'carb.sweet_potato_mash',
    name: LocalizedText(
      ar: 'بطاطا حلوة مهروسة',
      en: 'Sweet Potato Mash',
    ),
    description: LocalizedText(
      ar: 'بطاطا حلوة محمّصة ومهروسة مع زيت الزيتون وقليل من القرفة.',
      en: 'Roasted and whipped with olive oil and a whisper of cinnamon.',
    ),
    basePortionGrams: 160,
    baseMacros: MacroProfile(
      proteinGrams: 3,
      carbohydrateGrams: 32,
      fatGrams: 2.5,
      dietaryFiberGrams: 5,
      sodiumMilligrams: 190,
    ),
    method: CookingMethod.ovenRoasted,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
    },
  );

  /// Pearl couscous (maftoul).
  static const CarbOption pearlCouscous = CarbOption(
    id: 'carb.pearl_couscous',
    name: LocalizedText(ar: 'مفتول لؤلؤي', en: 'Pearl Couscous'),
    description: LocalizedText(
      ar: 'حبات مفتول محمّصة، مطهوة مع البصل المكرمل والكمون.',
      en: 'Toasted pearls simmered with caramelised onion and cumin.',
    ),
    basePortionGrams: 140,
    baseMacros: MacroProfile(
      proteinGrams: 6,
      carbohydrateGrams: 38,
      fatGrams: 1.5,
      dietaryFiberGrams: 3,
      sodiumMilligrams: 280,
    ),
    method: CookingMethod.slowSimmered,
    allergens: <Allergen>{Allergen.gluten},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.dairyFree,
    },
  );

  /// Herbed quinoa.
  static const CarbOption herbedQuinoa = CarbOption(
    id: 'carb.herbed_quinoa',
    name: LocalizedText(ar: 'كينوا بالأعشاب', en: 'Herbed Quinoa'),
    description: LocalizedText(
      ar: 'كينوا ثلاثية الألوان مع النعناع والبقدونس وعصير الليمون.',
      en: 'Tri-colour quinoa tossed with mint, parsley and lemon juice.',
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
  );

  // ---------------------------------------------------------------------
  // Compartment three — Vital Fiber
  // ---------------------------------------------------------------------

  /// Charred tenderstem broccolini.
  static const FiberOption charredBroccolini = FiberOption(
    id: 'fiber.charred_broccolini',
    name: LocalizedText(
      ar: 'بروكليني مشوي بالليمون',
      en: 'Charred Broccolini',
    ),
    description: LocalizedText(
      ar: 'سيقان بروكليني مشوية حتى التفحّم الخفيف، مع قشر الليمون والثوم.',
      en: 'Stems blistered to a light char with lemon zest and garlic.',
    ),
    basePortionGrams: 110,
    baseMacros: MacroProfile(
      proteinGrams: 4,
      carbohydrateGrams: 8,
      fatGrams: 3.5,
      dietaryFiberGrams: 4,
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
  );

  /// Citrus fennel and rocket salad.
  static const FiberOption citrusFennelRocket = FiberOption(
    id: 'fiber.citrus_fennel_rocket',
    name: LocalizedText(
      ar: 'سلطة الشمر والجرجير بالحمضيات',
      en: 'Citrus Fennel & Rocket',
    ),
    description: LocalizedText(
      ar: 'شرائح شمر رفيعة مع الجرجير وشرائح البرتقال وصلصة الحمضيات.',
      en: 'Shaved fennel, peppery rocket, orange segments, citrus dressing.',
    ),
    basePortionGrams: 120,
    baseMacros: MacroProfile(
      proteinGrams: 2,
      carbohydrateGrams: 9,
      fatGrams: 5,
      dietaryFiberGrams: 3.5,
      sodiumMilligrams: 140,
    ),
    method: CookingMethod.freshDressed,
    allergens: <Allergen>{},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.lowCarb,
    },
  );

  /// Blistered green beans with toasted almond.
  static const FiberOption blisteredGreenBeans = FiberOption(
    id: 'fiber.blistered_green_beans',
    name: LocalizedText(
      ar: 'فاصولياء خضراء باللوز',
      en: 'Blistered Green Beans',
    ),
    description: LocalizedText(
      ar: 'فاصولياء خضراء محمّرة على نار عالية مع رقائق اللوز المحمّص.',
      en: 'Snapped beans seared hard, finished with toasted almond flakes.',
    ),
    basePortionGrams: 110,
    baseMacros: MacroProfile(
      proteinGrams: 3.5,
      carbohydrateGrams: 9,
      fatGrams: 4.5,
      dietaryFiberGrams: 4.2,
      sodiumMilligrams: 160,
    ),
    method: CookingMethod.blistered,
    allergens: <Allergen>{Allergen.treeNuts},
    dietaryTags: <DietaryTag>{
      DietaryTag.plantBased,
      DietaryTag.glutenFree,
      DietaryTag.dairyFree,
      DietaryTag.lowCarb,
    },
  );

  // ---------------------------------------------------------------------
  // Collections and lookup
  // ---------------------------------------------------------------------

  /// All six protein options, in carousel order.
  static const List<ProteinOption> proteins = <ProteinOption>[
    flameSearedChicken,
    charredTenderloin,
    herbGrilledSalmon,
    spicedLambKofta,
    zaatarShrimp,
    smokedHarissaTofu,
  ];

  /// All six smart-carb options, in carousel order.
  static const List<CarbOption> carbs = <CarbOption>[
    airFriedSpicedPotatoes,
    saffronBasmati,
    freekehPilaf,
    sweetPotatoMash,
    pearlCouscous,
    herbedQuinoa,
  ];

  /// All three vital-fibre options, in carousel order.
  static const List<FiberOption> fibers = <FiberOption>[
    charredBroccolini,
    citrusFennelRocket,
    blisteredGreenBeans,
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
