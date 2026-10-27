import '../../../core/config/launch_switches.dart';
import '../../../core/localization/localized_text.dart';

/// What checkout opens on: delivery while it's offered, else pickup.
FulfilmentMode get defaultFulfilment =>
    LaunchSwitches.delivery ? FulfilmentMode.delivery : FulfilmentMode.pickup;

/// How the guest wants the plate handed over.
enum FulfilmentMode {
  /// Brought to an address.
  delivery(
    label: LocalizedText(ar: 'توصيل', en: 'Delivery'),
    estimate: LocalizedText(ar: '35–45 دقيقة', en: '35–45 min'),
    readyWithin: Duration(minutes: 45),
  ),

  /// Collected from the counter.
  pickup(
    label: LocalizedText(ar: 'استلام', en: 'Pickup'),
    estimate: LocalizedText(ar: '12–15 دقيقة', en: '12–15 min'),
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

/// How the guest pays — like a kiosk: at the counter, or by card now.
///
/// Two choices, not five (Hick's Law). Bit, Apple Pay and Google Pay live on
/// the card page, so they don't add buttons here.
enum PaymentMethod {
  /// At the counter, cash or card. The kitchen starts only once a staff
  /// member marks it paid, so an order nobody pays for costs no food.
  counter(
    label: LocalizedText(ar: 'ادفع عند الاستلام', en: 'Pay at the counter'),
    detail: LocalizedText(
      ar: 'في المطعم، نقدًا أو بالبطاقة. نبدأ التحضير بعد الدفع.',
      en: 'Cash or card at the restaurant. We start cooking once you pay.',
    ),
    pickupOnly: true,
  ),

  /// By card in the app, on the payment company's own page.
  card(
    label: LocalizedText(ar: 'ادفع بالبطاقة الآن', en: 'Pay by card now'),
    detail:
        LocalizedText(ar: 'فيزا، ماستركارد، Bit', en: 'Visa, Mastercard, Bit'),
    pickupOnly: false,
  );

  const PaymentMethod({
    required this.label,
    required this.detail,
    required this.pickupOnly,
  });

  /// The method's name.
  final LocalizedText label;

  /// A second line: what it is and what happens next.
  final LocalizedText detail;

  /// Whether it only works when the guest comes in. Delivery is card only.
  final bool pickupOnly;

  /// Why it's greyed out under delivery.
  static const LocalizedText pickupOnlyReason = LocalizedText(
    ar: 'للاستلام من المطعم فقط',
    en: 'Pickup only',
  );
}
