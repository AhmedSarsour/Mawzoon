import '../../../core/localization/localized_text.dart';

/// How the guest wants the plate handed over.
enum FulfilmentMode {
  /// Brought to an address.
  delivery(
    label: LocalizedText(ar: 'توصيل', en: 'Delivery'),
    estimate: LocalizedText(ar: '٣٥–٤٥ دقيقة', en: '35–45 min'),
    readyWithin: Duration(minutes: 45),
  ),

  /// Collected from the counter.
  pickup(
    label: LocalizedText(ar: 'استلام', en: 'Pickup'),
    estimate: LocalizedText(ar: '١٢–١٥ دقيقة', en: '12–15 min'),
    readyWithin: Duration(minutes: 15),
  );

  const FulfilmentMode({
    required this.label,
    required this.estimate,
    required this.readyWithin,
  });

  /// The mode's name.
  final LocalizedText label;

  /// How long it typically takes. Shown up front, because the real question
  /// behind "delivery or pickup" is "when do I eat".
  final LocalizedText estimate;

  /// The upper end of [estimate], as a duration. Kept beside the text so the
  /// two are edited together.
  final Duration readyWithin;
}

/// A place the guest has had food sent to before.
///
/// Saved addresses carry a [label] the guest chose — "Home", "The office" —
/// because "Al Olaya, building 4429" is not how anyone recognises their own
/// address at a glance while hungry.
final class DeliveryAddress {
  /// Creates a saved address.
  const DeliveryAddress({
    required this.id,
    required this.label,
    required this.line,
    required this.district,
    this.directions,
    this.isDefault = false,
  })  : assert(id.length > 0, 'id must not be empty'),
        assert(line.length > 0, 'line must not be empty');

  /// Stable identifier.
  final String id;

  /// What the guest calls this place.
  final LocalizedText label;

  /// Street and building.
  final String line;

  /// District or neighbourhood.
  final String district;

  /// Anything the rider needs that the map will not tell them.
  final String? directions;

  /// Whether this is the address a new order starts on.
  final bool isDefault;

  /// One line for a summary row.
  String get summary => '$line، $district';

  @override
  String toString() => 'DeliveryAddress($id)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DeliveryAddress && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// How the guest pays.
///
/// Modelled as saved instruments rather than a form. Asking a hungry person to
/// type a card number is where an order is lost; every option here is one tap.
enum PaymentMethod {
  /// The platform wallet. First because it is the fastest on the devices most
  /// guests are holding.
  wallet(
    label: LocalizedText(ar: 'المحفظة', en: 'Wallet'),
    detail: LocalizedText(ar: 'دفع فوري', en: 'Instant'),
    requiresCardOnFile: false,
  ),

  /// A saved mada or credit card.
  savedCard(
    label: LocalizedText(ar: 'البطاقة المحفوظة', en: 'Saved card'),
    detail: LocalizedText(ar: 'تنتهي بـ ٤٤٠٢', en: 'Ending 4402'),
    requiresCardOnFile: true,
  ),

  /// Paid at handover.
  cash(
    label: LocalizedText(ar: 'نقدًا عند الاستلام', en: 'Cash on handover'),
    detail: LocalizedText(ar: 'جهّز المبلغ', en: 'Have it ready'),
    requiresCardOnFile: false,
  );

  const PaymentMethod({
    required this.label,
    required this.detail,
    required this.requiresCardOnFile,
  });

  /// The method's name.
  final LocalizedText label;

  /// A second line: what it is, or which card.
  final LocalizedText detail;

  /// Whether the method needs an instrument already on file.
  final bool requiresCardOnFile;
}
