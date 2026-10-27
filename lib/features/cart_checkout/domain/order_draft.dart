import '../../../core/localization/localized_text.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/stock_status.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../../core/pricing/money.dart';
import '../../plate_builder/domain/plate_selection.dart';
import 'delivery_address.dart';

/// What one plate costs, itemised.
///
/// Itemised rather than reduced to a total, because a guest who sees a figure
/// they did not expect should be able to find out why without contacting
/// anyone. Every line here is derived; nothing is stored.
///
/// Prices include VAT (Israeli consumer law: the price shown is the price
/// paid), so the VAT is extracted from the total, not added on top.
final class PriceBreakdown {
  const PriceBreakdown._({
    required this.base,
    required this.componentSurcharges,
    required this.loadUplift,
    required this.deliveryFee,
    required this.tax,
  });

  /// Prices [selection] for [mode].
  factory PriceBreakdown.forPlate({
    required PlateSelection selection,
    required FulfilmentMode mode,
  }) {
    final Money surcharges = Money(selection.surchargeMinorUnits);
    final Money uplift = switch (selection.scale) {
      PortionScale.standardBalance => Money.zero,
      PortionScale.athleticLoad => athleticLoadUplift,
    };
    final Money delivery =
        mode == FulfilmentMode.delivery ? standardDeliveryFee : Money.zero;
    final Money total = basePlatePrice + surcharges + uplift + delivery;

    return PriceBreakdown._(
      base: basePlatePrice,
      componentSurcharges: surcharges,
      loadUplift: uplift,
      deliveryFee: delivery,
      tax: total.includedTax(vatBasisPoints),
    );
  }

  /// The price of any plate before its components are counted.
  static const Money basePlatePrice = Money(4900);

  /// A flat uplift for the Athletic Load. The guest is buying a bigger plate,
  /// not auditing a scale ticket.
  static const Money athleticLoadUplift = Money(1500);

  /// What delivery costs when the guest chooses it.
  static const Money standardDeliveryFee = Money(1200);

  /// Israeli VAT, in basis points (1800 = 18%). 0 for an exempt dealer
  /// (עוסק פטור). Mirrored in `public.pricing.vat_basis_points`.
  static const int vatBasisPoints = 1800;

  /// The plate before components.
  final Money base;

  /// Upcharges for the chosen components.
  final Money componentSurcharges;

  /// The Athletic Load uplift, or zero.
  final Money loadUplift;

  /// Delivery, or zero for pickup.
  final Money deliveryFee;

  /// The VAT already inside [total].
  final Money tax;

  /// What the guest pays, VAT included.
  Money get total => base + componentSurcharges + loadUplift + deliveryFee;

  /// The charges a receipt shows, in order, skipping the zero ones. They add
  /// up to [total]; VAT is inside them, not another line ([includedTaxNote]).
  ///
  /// A row reading "Delivery 0.00" on a pickup order is noise pretending to be
  /// transparency.
  List<(LocalizedText, Money)> lines() => <(LocalizedText, Money)>[
        (const LocalizedText(ar: 'الطبق', en: 'Plate'), base),
        if (!componentSurcharges.isZero)
          (
            const LocalizedText(
              ar: 'إضافات المكوّنات',
              en: 'Component upgrades',
            ),
            componentSurcharges
          ),
        if (!loadUplift.isZero)
          (
            const LocalizedText(ar: 'الحِمل الرياضي', en: 'Athletic Load'),
            loadUplift
          ),
        if (!deliveryFee.isZero)
          (const LocalizedText(ar: 'التوصيل', en: 'Delivery'), deliveryFee),
      ];

  /// "Includes 18% VAT: 7.47 ₪" — or null with no VAT (exempt dealer).
  (LocalizedText, Money)? get includedTaxNote {
    if (vatBasisPoints == 0) return null;
    final String rate = vatBasisPoints % 100 == 0
        ? '${vatBasisPoints ~/ 100}'
        : (vatBasisPoints / 100).toString();
    return (
      LocalizedText(ar: 'يشمل ضريبة $rate%', en: 'Includes $rate% VAT'),
      tax,
    );
  }

  @override
  String toString() => 'PriceBreakdown(total: $total)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PriceBreakdown &&
          other.base == base &&
          other.componentSurcharges == componentSurcharges &&
          other.loadUplift == loadUplift &&
          other.deliveryFee == deliveryFee &&
          other.tax == tax;

  @override
  int get hashCode =>
      Object.hash(base, componentSurcharges, loadUplift, deliveryFee, tax);
}

/// An order the guest has not placed yet.
///
/// Immutable, like everything else in the domain: each change to the sheet
/// produces a new draft, so the sheet can never show a total computed from a
/// selection that has since changed underneath it.
final class OrderDraft {
  /// Creates a draft.
  const OrderDraft({
    required this.selection,
    required this.mode,
    required this.payment,
    this.address,
    this.note,
    this.phone,
  });

  /// The plate being ordered.
  final PlateSelection selection;

  /// Delivery or pickup.
  final FulfilmentMode mode;

  /// How the guest is paying.
  final PaymentMethod payment;

  /// Where it goes. Required for delivery, meaningless for pickup.
  final DeliveryAddress? address;

  /// A note for the kitchen.
  final String? note;

  /// The guest's mobile, normalised (`+9725XXXXXXXX`; see `israeliMobile`).
  /// Required for delivery, so the driver can call; optional for pickup.
  final String? phone;

  /// The plate's nutrition, so the confirmation can restate what was ordered.
  NutritionalSummary get summary => selection.summary;

  /// The itemised price.
  PriceBreakdown get price =>
      PriceBreakdown.forPlate(selection: selection, mode: mode);

  /// The components on the plate, in build order.
  List<IngredientOption> get components => <IngredientOption>[
        if (selection.protein != null) selection.protein!,
        if (selection.carb != null) selection.carb!,
        if (selection.fiber != null) selection.fiber!,
      ];

  /// Whether this draft can be placed.
  ///
  /// Three conditions, and the sheet never has to guess which one is missing:
  /// a complete plate, and for delivery, somewhere to deliver it.
  bool get isPlaceable => isPlaceableIn(MenuAvailability.everything);

  /// Whether this draft can be placed against [availability].
  bool isPlaceableIn(MenuAvailability availability) =>
      blockerIn(availability) == null;

  /// Components on this plate the kitchen can no longer make.
  ///
  /// The plate itself is never edited to remove them. A guest who assembled
  /// something while the last tray of it was being sold has not made a
  /// mistake, and silently deleting their choice at the payment step is how an
  /// app gets accused of changing an order. They are told which one, by name,
  /// and they change it.
  List<IngredientOption> unavailableIn(MenuAvailability availability) =>
      <IngredientOption>[
        for (final IngredientOption component in components)
          if (!availability.canOrder(component.id)) component,
      ];

  /// Why the order cannot be placed, or `null` when it can.
  LocalizedText? get blocker => blockerIn(MenuAvailability.everything);

  /// Why the order cannot be placed against [availability], or `null`.
  ///
  /// Order matters. An incomplete plate is the guest's next step whatever the
  /// store says, so it is reported first; being told a component is off while
  /// two compartments are still empty is an answer to a question nobody asked.
  LocalizedText? blockerIn(MenuAvailability availability) {
    if (!selection.isComplete) {
      return const LocalizedText(
        ar: 'أكمل أقسام الطبق الثلاثة',
        en: 'Finish all three compartments',
      );
    }
    final List<IngredientOption> gone = unavailableIn(availability);
    if (gone.isNotEmpty) return soldOutBlocker(gone.first);
    if (mode == FulfilmentMode.delivery && address == null) {
      return needsAddressBlocker;
    }
    if (mode == FulfilmentMode.delivery && phone == null) {
      return needsPhoneBlocker;
    }
    if (mode == FulfilmentMode.delivery && payment.pickupOnly) {
      return PaymentMethod.pickupOnlyReason;
    }
    return null;
  }

  /// What the guest reads when a delivery has no number to call.
  static const LocalizedText needsPhoneBlocker = LocalizedText(
    ar: 'أضف رقم جوالك للتوصيل',
    en: 'Add your phone number for delivery',
  );

  /// What the guest reads when [component] can't be made any more — locally
  /// or because the kitchen's server said so at the last moment.
  static LocalizedText soldOutBlocker(IngredientOption component) =>
      LocalizedText(
        ar: 'نفد ${component.name.ar} — اختر بديلًا',
        en: '${component.name.en} just sold out — pick another',
      );

  /// What the guest reads when a delivery has nowhere to go.
  static const LocalizedText needsAddressBlocker = LocalizedText(
    ar: 'اختر عنوان التوصيل',
    en: 'Choose a delivery address',
  );

  /// A copy for [next] mode. Moving to delivery swaps a pickup-only payment
  /// for card, so the guest isn't left holding a choice that can't work.
  OrderDraft withMode(FulfilmentMode next) => copyWith(
        mode: next,
        payment: next == FulfilmentMode.delivery && payment.pickupOnly
            ? PaymentMethod.card
            : null,
      );

  /// Returns a copy with the given fields replaced.
  ///
  /// [address] is kept when omitted; switching to pickup does not discard it,
  /// so a guest who changes their mind twice does not have to pick it again.
  OrderDraft copyWith({
    PlateSelection? selection,
    FulfilmentMode? mode,
    PaymentMethod? payment,
    DeliveryAddress? address,
    String? note,
  }) =>
      OrderDraft(
        selection: selection ?? this.selection,
        mode: mode ?? this.mode,
        payment: payment ?? this.payment,
        address: address ?? this.address,
        note: note ?? this.note,
        phone: phone,
      );

  @override
  String toString() => 'OrderDraft(${mode.name}, ${payment.name}, '
      '${price.total})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderDraft &&
          other.selection == selection &&
          other.mode == mode &&
          other.payment == payment &&
          other.address == address &&
          other.note == note &&
          other.phone == phone;

  /// A copy with [phone] replaced — including by null, which [copyWith]
  /// can't express.
  OrderDraft withPhone(String? phone) => OrderDraft(
        selection: selection,
        mode: mode,
        payment: payment,
        address: address,
        note: note,
        phone: phone,
      );

  @override
  int get hashCode =>
      Object.hash(selection, mode, payment, address, note, phone);
}
