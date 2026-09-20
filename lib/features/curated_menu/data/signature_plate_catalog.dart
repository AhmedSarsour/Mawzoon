import '../../../core/localization/localized_text.dart';
import '../../../core/menu/mawzoon_catalog.dart';
import '../domain/signature_plate.dart';

/// The Curated Track: six chef-balanced plates, each one tap from the cart.
///
/// Every plate here is validated by test against the house energy bands at
/// both portion scales — a signature plate that drifts outside its band fails
/// the build rather than reaching a guest. That is the whole point of the
/// curated track: the guest delegates the arithmetic and it is still right.
abstract final class SignaturePlateCatalog {
  static const int _basePriceMinorUnits = 4900;

  /// Chicken, air-fried potatoes, charred broccolini. The house default.
  static const SignaturePlate emberStandard = SignaturePlate(
    id: 'signature.ember_standard',
    name: LocalizedText(ar: 'جمرة التوازن', en: 'The Ember Standard'),
    tagline: LocalizedText(
      ar: 'دجاج اللهب، بطاطس مقرمشة، بروكليني',
      en: 'Flame chicken, crisp potato, broccolini',
    ),
    chefNote: LocalizedText(
      ar: 'الطبق الذي بنينا عليه المطعم: قشرة مقرمشة، لحم طري، ولا شيء مقلي.',
      en: 'The plate we built the restaurant on: crisp crust, tender meat, '
          'nothing deep-fried.',
    ),
    protein: MawzoonCatalog.flameSearedChicken,
    carb: MawzoonCatalog.airFriedSpicedPotatoes,
    fiber: MawzoonCatalog.charredBroccolini,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Salmon, saffron basmati, broccolini.
  static const SignaturePlate coastalSaffron = SignaturePlate(
    id: 'signature.coastal_saffron',
    name: LocalizedText(ar: 'زعفران الساحل', en: 'Coastal Saffron'),
    tagline: LocalizedText(
      ar: 'سلمون بالأعشاب، بسمتي بالزعفران',
      en: 'Herbed salmon, saffron basmati',
    ),
    chefNote: LocalizedText(
      ar: 'دهون السلمون الصحية مع أرز عطري — الطبق الأكثر طلبًا في المساء.',
      en: "Salmon's good fats against aromatic rice — our most ordered plate "
          'after sunset.',
    ),
    protein: MawzoonCatalog.herbGrilledSalmon,
    carb: MawzoonCatalog.saffronBasmati,
    fiber: MawzoonCatalog.charredBroccolini,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Beef tenderloin, freekeh, green beans.
  static const SignaturePlate charcoalFreekeh = SignaturePlate(
    id: 'signature.charcoal_freekeh',
    name: LocalizedText(ar: 'فحم وفريكة', en: 'Charcoal & Freekeh'),
    tagline: LocalizedText(
      ar: 'فيليه على الفحم، فريكة مدخنة',
      en: 'Charcoal fillet, smoked freekeh',
    ),
    chefNote: LocalizedText(
      ar: 'دخان على دخان: الفحم تحت اللحم، والفريكة المحروقة تحت كل شيء.',
      en: 'Smoke on smoke: charcoal under the beef, scorched green wheat '
          'under all of it.',
    ),
    protein: MawzoonCatalog.charredTenderloin,
    carb: MawzoonCatalog.freekehPilaf,
    fiber: MawzoonCatalog.blisteredGreenBeans,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Lamb kofta, pearl couscous, citrus fennel.
  static const SignaturePlate levantineKofta = SignaturePlate(
    id: 'signature.levantine_kofta',
    name: LocalizedText(ar: 'كفتة شامية', en: 'Levantine Kofta'),
    tagline: LocalizedText(
      ar: 'كفتة بالبهارات، مفتول، شمر بالحمضيات',
      en: 'Spiced kofta, maftoul, citrus fennel',
    ),
    chefNote: LocalizedText(
      ar: 'السبع بهارات مع حموضة البرتقال — التوازن هنا في الطعم قبل الأرقام.',
      en: 'Seven spices cut by orange acidity — here the balance is on the '
          'palate before it is in the numbers.',
    ),
    protein: MawzoonCatalog.spicedLambKofta,
    carb: MawzoonCatalog.pearlCouscous,
    fiber: MawzoonCatalog.citrusFennelRocket,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Harissa tofu, sweet potato, green beans. Fully plant-based.
  static const SignaturePlate gardenEmber = SignaturePlate(
    id: 'signature.garden_ember',
    name: LocalizedText(ar: 'جمرة الحديقة', en: 'Garden Ember'),
    tagline: LocalizedText(
      ar: 'توفو بالهريسة، بطاطا حلوة، فاصولياء',
      en: 'Harissa tofu, sweet potato, green beans',
    ),
    chefNote: LocalizedText(
      ar: 'نباتي بالكامل ولا يعتذر عن ذلك: الهريسة المنزلية تفعل كل شيء.',
      en: 'Entirely plant-based and unapologetic about it — the house harissa '
          'does all the work.',
    ),
    protein: MawzoonCatalog.smokedHarissaTofu,
    carb: MawzoonCatalog.sweetPotatoMash,
    fiber: MawzoonCatalog.blisteredGreenBeans,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// Za'atar shrimp, herbed quinoa, citrus fennel.
  static const SignaturePlate zaatarShore = SignaturePlate(
    id: 'signature.zaatar_shore',
    name: LocalizedText(ar: 'شاطئ الزعتر', en: "Za'atar Shore"),
    tagline: LocalizedText(
      ar: 'روبيان بالزعتر، كينوا، شمر بالحمضيات',
      en: "Za'atar shrimp, quinoa, citrus fennel",
    ),
    chefNote: LocalizedText(
      ar: 'أخف أطباقنا وأكثرها انتعاشًا — زعتر بري وليمون وبحر.',
      en: 'Our lightest, brightest plate — wild thyme, lemon and sea.',
    ),
    protein: MawzoonCatalog.zaatarShrimp,
    carb: MawzoonCatalog.herbedQuinoa,
    fiber: MawzoonCatalog.citrusFennelRocket,
    basePriceMinorUnits: _basePriceMinorUnits,
  );

  /// All signature plates, in menu order.
  static const List<SignaturePlate> all = <SignaturePlate>[
    emberStandard,
    coastalSaffron,
    charcoalFreekeh,
    levantineKofta,
    gardenEmber,
    zaatarShore,
  ];

  /// Looks up a signature plate by [id], or returns `null`.
  static SignaturePlate? byId(String id) {
    for (final SignaturePlate plate in all) {
      if (plate.id == id) return plate;
    }
    return null;
  }
}
