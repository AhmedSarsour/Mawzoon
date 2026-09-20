import '../localization/localized_text.dart';

/// Dietary properties a guest may filter or screen for.
///
/// Framed as capabilities a dish *has*, never as restrictions a guest suffers.
enum DietaryTag {
  /// Contains no animal products whatsoever.
  plantBased(label: LocalizedText(ar: 'نباتي بالكامل', en: 'Plant-Based')),

  /// Contains no gluten-bearing grains.
  glutenFree(label: LocalizedText(ar: 'خالٍ من الغلوتين', en: 'Gluten-Free')),

  /// Contains no dairy.
  dairyFree(label: LocalizedText(ar: 'خالٍ من الألبان', en: 'Dairy-Free')),

  /// At least 30 g of protein in the standard portion.
  highProtein(label: LocalizedText(ar: 'عالي البروتين', en: 'High Protein')),

  /// Fewer than 15 g of digestible carbohydrate in the standard portion.
  lowCarb(label: LocalizedText(ar: 'قليل الكربوهيدرات', en: 'Low Carb')),

  /// Prepared with a warming spice blend.
  spiced(label: LocalizedText(ar: 'متبّل', en: 'Spiced'));

  const DietaryTag({required this.label});

  /// The tag's display name.
  final LocalizedText label;
}

/// Allergens that must be declared for every component, without exception.
///
/// This list is a safety contract, not a marketing field. A component with an
/// empty allergen set is asserting that it contains none of these.
enum Allergen {
  /// Wheat, barley, rye and derivatives.
  gluten(label: LocalizedText(ar: 'الغلوتين', en: 'Gluten')),

  /// Milk and milk derivatives.
  dairy(label: LocalizedText(ar: 'الألبان', en: 'Dairy')),

  /// Tree nuts.
  treeNuts(label: LocalizedText(ar: 'المكسرات', en: 'Tree Nuts')),

  /// Sesame and tahini.
  sesame(label: LocalizedText(ar: 'السمسم', en: 'Sesame')),

  /// Soy and soy derivatives.
  soy(label: LocalizedText(ar: 'الصويا', en: 'Soy')),

  /// Fin fish.
  fish(label: LocalizedText(ar: 'الأسماك', en: 'Fish')),

  /// Crustaceans and shellfish.
  shellfish(label: LocalizedText(ar: 'القشريات', en: 'Shellfish')),

  /// Eggs.
  egg(label: LocalizedText(ar: 'البيض', en: 'Egg')),

  /// Mustard seed and prepared mustard.
  mustard(label: LocalizedText(ar: 'الخردل', en: 'Mustard'));

  const Allergen({required this.label});

  /// The allergen's display name.
  final LocalizedText label;
}

/// How a component is cooked.
///
/// Surfaced in the UI because the method *is* the proposition: air-frying and
/// flame-searing are why a balanced plate tastes like indulgence.
enum CookingMethod {
  /// Seared over open flame.
  flameSeared(label: LocalizedText(ar: 'مشوي على اللهب', en: 'Flame-Seared')),

  /// Crisped in circulating hot air, no deep frying.
  airFried(label: LocalizedText(ar: 'مقلي بالهواء الساخن', en: 'Air-Fried')),

  /// Roasted in a dry oven.
  ovenRoasted(label: LocalizedText(ar: 'محمّص بالفرن', en: 'Oven-Roasted')),

  /// Blistered fast in a very hot pan.
  blistered(label: LocalizedText(ar: 'محمّر سريعًا', en: 'Blistered')),

  /// Steamed.
  steamed(label: LocalizedText(ar: 'مطهو بالبخار', en: 'Steamed')),

  /// Simmered or pilaf-style absorption cooking.
  slowSimmered(label: LocalizedText(ar: 'مطهو على نار هادئة', en: 'Slow-Simmered')),

  /// Served raw and dressed.
  freshDressed(label: LocalizedText(ar: 'طازج بالصلصة', en: 'Fresh-Dressed'));

  const CookingMethod({required this.label});

  /// The method's display name.
  final LocalizedText label;
}
