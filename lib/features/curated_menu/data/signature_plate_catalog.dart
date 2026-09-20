import '../../../core/localization/localized_text.dart';
import '../../../core/menu/mawzoon_catalog.dart';
import '../domain/signature_plate.dart';

/// The Curated Track: six chef-balanced plates, each one tap from the cart.
///
/// Every plate here is validated by test against the house energy bands at
/// both portion scales — a signature plate that drifts outside its band fails
/// the build rather than reaching a guest. That is the whole point of the
/// curated track: the guest delegates the arithmetic and it is still right.
///
/// Between them the six use every protein, every carb and both fibres once,
/// so the curated row is a complete tour of the menu rather than six
/// variations on the same three components.
abstract final class SignaturePlateCatalog {
  static const int _basePriceMinorUnits = 4900;

  /// Chicken breast, air-fried potatoes, charred veg. The house default.
  static const SignaturePlate emberStandard = SignaturePlate(
    id: 'signature.ember_standard',
    name: LocalizedText(ar: 'جمرة التوازن', en: 'The Ember Standard'),
    tagline: LocalizedText(
      ar: 'صدر مشوي، بطاطس مقرمشة، خضار',
      en: 'Grilled breast, crisp potato, charred veg',
    ),
    chefNote: LocalizedText(
      ar: 'الطبق الذي بنينا عليه المطعم: قشرة مقرمشة، لحم طري، ولا شيء مقلي.',
      en: 'The plate we built the restaurant on: crisp crust, tender meat, '
          'nothing deep-fried.',
    ),
    protein: MawzoonCatalog.herbGrilledBreast,
    carb: MawzoonCatalog.airFriedSpicedPotatoes,
    fiber: MawzoonCatalog.charredGardenVeggies,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Smoked entrecôte, whole bulgur, sumac salad.
  static const SignaturePlate smokehouseBulgur = SignaturePlate(
    id: 'signature.smokehouse_bulgur',
    name: LocalizedText(ar: 'دخان وبرغل', en: 'Smokehouse & Bulgur'),
    tagline: LocalizedText(
      ar: 'انتركوت مدخّن، برغل أسمر، سماق',
      en: 'Smoked entrecôte, whole bulgur, sumac',
    ),
    chefNote: LocalizedText(
      ar: 'أغنى قطعة على القائمة، يوازنها البرغل وحموضة السماق.',
      en: 'The richest cut on the menu, held in check by bulgur and the '
          'sourness of sumac.',
    ),
    protein: MawzoonCatalog.smokedEntrecote,
    carb: MawzoonCatalog.wholeBulgur,
    fiber: MawzoonCatalog.mediterraneanSumacSalad,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Smashed lean beef, steamed basmati, charred veg.
  static const SignaturePlate smashAndSteam = SignaturePlate(
    id: 'signature.smash_and_steam',
    name: LocalizedText(ar: 'مسحوق وبخار', en: 'Smash & Steam'),
    tagline: LocalizedText(
      ar: 'لحم مسحوق، بسمتي، خضار مشوية',
      en: 'Smashed beef, basmati, charred veg',
    ),
    chefNote: LocalizedText(
      ar: 'حواف مقرمشة من الصاج مع أرز خفيف — أبسط طبق وأكثره طلبًا ظهرًا.',
      en: 'Lacy plancha edges against light rice — the simplest plate here, '
          'and the one that sells out at lunch.',
    ),
    protein: MawzoonCatalog.smashedLeanBeef,
    carb: MawzoonCatalog.steamedBasmati,
    fiber: MawzoonCatalog.charredGardenVeggies,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Pulled slow-cooked beef, sweet potato wedges, sumac salad.
  static const SignaturePlate slowAndSweet = SignaturePlate(
    id: 'signature.slow_and_sweet',
    name: LocalizedText(ar: 'بطء وحلاوة', en: 'Slow & Sweet'),
    tagline: LocalizedText(
      ar: 'لحم مسحوب، بطاطا حلوة، سماق',
      en: 'Pulled beef, sweet potato, sumac',
    ),
    chefNote: LocalizedText(
      ar: 'ثماني ساعات من الطهي مقابل حلاوة البطاطا المكرملة.',
      en: 'Eight hours of slow heat set against caramelised sweetness.',
    ),
    protein: MawzoonCatalog.pulledSlowCookedBeef,
    carb: MawzoonCatalog.sweetPotatoWedges,
    fiber: MawzoonCatalog.mediterraneanSumacSalad,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Kofta, whole wheat pasta, sumac salad.
  static const SignaturePlate koftaAlDente = SignaturePlate(
    id: 'signature.kofta_al_dente',
    name: LocalizedText(ar: 'كفتة ومعكرونة', en: 'Kofta al Dente'),
    tagline: LocalizedText(
      ar: 'كفتة بالبهارات، قمح كامل، سماق',
      en: 'Spiced kofta, whole wheat, sumac',
    ),
    chefNote: LocalizedText(
      ar: 'السبع بهارات مع معكرونة القمح الكامل — أبطأ طبق في إطلاق الطاقة.',
      en: 'Seven spices over whole wheat — the slowest-releasing plate we '
          'make.',
    ),
    protein: MawzoonCatalog.koftaSpicedMince,
    carb: MawzoonCatalog.wholeWheatPasta,
    fiber: MawzoonCatalog.mediterraneanSumacSalad,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Marinated thighs, toasted quinoa, charred veg.
  static const SignaturePlate sumacAndQuinoa = SignaturePlate(
    id: 'signature.sumac_and_quinoa',
    name: LocalizedText(ar: 'سماق وكينوا', en: 'Sumac & Quinoa'),
    tagline: LocalizedText(
      ar: 'أفخاذ متبّلة، كينوا محمّصة، خضار',
      en: 'Marinated thighs, toasted quinoa, charred veg',
    ),
    chefNote: LocalizedText(
      ar: 'نقع ليلة كاملة بالسماق، مع كينوا محمّصة على نار جافة قبل الطهي.',
      en: 'An overnight sumac marinade, with quinoa dry-toasted before it ever '
          'sees water.',
    ),
    protein: MawzoonCatalog.marinatedThighs,
    carb: MawzoonCatalog.toastedQuinoa,
    fiber: MawzoonCatalog.charredGardenVeggies,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// All signature plates, in menu order.
  static const List<SignaturePlate> all = <SignaturePlate>[
    emberStandard,
    smokehouseBulgur,
    smashAndSteam,
    slowAndSweet,
    koftaAlDente,
    sumacAndQuinoa,
  ];

  /// Looks up a signature plate by [id], or returns `null`.
  static SignaturePlate? byId(String id) {
    for (final SignaturePlate plate in all) {
      if (plate.id == id) return plate;
    }
    return null;
  }
}
