import '../localization/localized_text.dart';

/// The three compartments of the Mawzoon platter.
///
/// This enum is the spine of the whole product. It orders the physical
/// compartments of the elongated serving tray, the three arcs of the macro
/// ring, the three steps of the Plate Architect, and the three rows of the
/// ingredient carousel. Presentation code maps a segment to a palette token;
/// the domain layer never names a colour.
enum PlateSegment {
  /// The anchor of the plate — flame-seared, grilled or air-fried protein.
  protein(
    ordinal: 0,
    label: LocalizedText(ar: 'البروتين', en: 'Protein'),
    invitation: LocalizedText(
      ar: 'اختر مصدر البروتين',
      en: 'Choose your protein',
    ),
  ),

  /// The slow-release energy compartment.
  smartCarb(
    ordinal: 1,
    label: LocalizedText(ar: 'الكربوهيدرات الذكية', en: 'Smart Carb'),
    invitation: LocalizedText(
      ar: 'اختر مصدر الطاقة',
      en: 'Choose your energy source',
    ),
  ),

  /// The greens compartment — volume, micronutrients and satiety.
  vitalFiber(
    ordinal: 2,
    label: LocalizedText(ar: 'الألياف الحيوية', en: 'Vital Fiber'),
    invitation: LocalizedText(
      ar: 'اختر الخضار الطازجة',
      en: 'Choose your greens',
    ),
  );

  const PlateSegment({
    required this.ordinal,
    required this.label,
    required this.invitation,
  });

  /// Stable left-to-right build order: protein, then carb, then fibre.
  ///
  /// This is a *logical* order, not a visual one. Under RTL the same ordinal
  /// renders right-to-left; the geometry layer flips, the domain does not.
  final int ordinal;

  /// The compartment's display name.
  final LocalizedText label;

  /// The prompt shown while this compartment is still empty.
  ///
  /// Phrased as an invitation rather than a warning — an unfilled compartment
  /// is an opportunity, never an error.
  final LocalizedText invitation;

  /// Segments in canonical build order.
  static const List<PlateSegment> buildOrder = <PlateSegment>[
    PlateSegment.protein,
    PlateSegment.smartCarb,
    PlateSegment.vitalFiber,
  ];
}
