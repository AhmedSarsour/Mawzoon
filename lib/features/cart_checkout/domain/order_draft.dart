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
    final Money taxable = basePlatePrice + surcharges + uplift + delivery;

    return PriceBreakdown._(
      base: basePlatePrice,
      componentSurcharges: surcharges,
      loadUplift: uplift,
      deliveryFee: delivery,
      tax: taxable.percentage(vatRate),
    );
  }

  /// The price of any plate before its components are counted.
  static const Money basePlatePrice = Money(4900);

  /// A flat uplift for the Athletic Load. The guest is buying a bigger plate,
  /// not auditing a scale ticket.
  static const Money athleticLoadUplift = Money(1500);

  /// What delivery costs when the guest chooses it.
  static const Money standardDeliveryFee = Money(1200);

  /// Saudi VAT.
  static const double vatRate = 0.15;

  /// The plate before components.
  final Money base;

  /// Upcharges for the chosen components.
  final Money componentSurcharges;

  /// The Athletic Load uplift, or zero.
  final Money loadUplift;

  /// Delivery, or zero for pickup.
  final Money deliveryFee;

  /// VAT on everything above.
  final Money tax;

  /// Everything except tax.
  Money get subtotal => base + componentSurcharges + loadUplift + deliveryFee;

  /// What the guest pays.
  Money get total => subtotal + tax;

  /// The lines a receipt shows, in order, skipping the zero ones.
  ///
  /// A row reading "Delivery 0.00" on a pickup order is noise pretending to be
  /// transparency.
  List<(LocalizedText, Money)> lines() => <(LocalizedText, Money)>[
        (const LocalizedText(ar: 'الطبق', en: 'Plate'), base),
        if (!componentSurcharges.isZero)
          (
            const LocalizedText(ar: 'إضافات المكوّنات', en: 'Component upgrades'),
            componentSurcharges
          ),
        if (!loadUplift.isZero)
          (
            const LocalizedText(ar: 'الحِمل الرياضي', en: 'Athletic Load'),
            loadUplift
          ),
        if (!deliveryFee.isZero)
          (const LocalizedText(ar: 'التوصيل', en: 'Delivery'), deliveryFee),
        (
          const LocalizedText(ar: 'ضريبة القيمة المضافة', en: 'VAT'),
          tax,
        ),
      ];

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
    if (gone.isNotEmpty) {
      return LocalizedText(
        ar: 'نفد ${gone.first.name.ar} — اختر بديلًا',
        en: '${gone.first.name.en} just sold out — pick another',
      );
    }
    if (mode == FulfilmentMode.delivery && address == null) {
      return const LocalizedText(
        ar: 'اختر عنوان التوصيل',
        en: 'Choose a delivery address',
      );
    }
    return null;
  }

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
          other.note == note;

  @override
  int get hashCode => Object.hash(selection, mode, payment, address, note);
}
