import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/launch_switches.dart';
import '../../../core/localization/localized_text.dart';
import '../../../ui_primitives/menu/menu_scope.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/pricing/money.dart';
import '../../../ui_primitives/controls/macro_capsule.dart';
import '../../../ui_primitives/controls/mawzoon_input_decoration.dart';
import '../../../ui_primitives/interaction/haptics.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../services/idempotency_key.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../../plate_builder/domain/plate_selection.dart';
import '../domain/delivery_address.dart';
import '../domain/guest_phone.dart';
import '../domain/order_draft.dart';
import '../domain/order_placement.dart';
import '../domain/saved_places.dart';
import 'order_gateway_scope.dart';

/// What the checkout ended with.
final class CheckoutResult {
  /// Creates a result.
  const CheckoutResult({required this.draft, this.placed, this.openOrderId});

  /// The order as the guest confirmed it.
  final OrderDraft draft;

  /// The kitchen's answer, or null when no [OrderGatewayScope] was present
  /// (a test or preview confirming locally).
  final OrderPlaced? placed;

  /// Set when the server refused because this guest already has an unpaid
  /// order: the home screen opens that one instead.
  final String? openOrderId;
}

/// Opens the checkout sheet for [selection] and returns the placed order.
///
/// Returns `null` if the guest dismissed it. With an [OrderGatewayScope] above
/// it, the sheet only closes once the kitchen has the order.
///
/// [phone] is the guest's remembered mobile, if any: delivery then needs no
/// typing at all.
Future<CheckoutResult?> showCheckoutSheet(
  BuildContext context, {
  required PlateSelection selection,
  String? phone,
  bool offerDelivery = LaunchSwitches.delivery,
  bool offerCard = LaunchSwitches.cardPayment,
}) {
  return showModalBottomSheet<CheckoutResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Lifts the sheet above the keyboard while the phone field is in use.
    builder: (BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: CheckoutSheet(
        selection: selection,
        phone: phone,
        offerDelivery: offerDelivery,
        offerCard: offerCard,
      ),
    ),
  );
}

/// The checkout sheet.
///
/// ## Two taps
///
/// The sheet opens already answerable: the default address is selected, the
/// fastest payment method is selected, and the total is already computed. The
/// guest's second tap places the order. Everything else on the sheet is there
/// to be *changed*, not to be filled in — which is the difference between a
/// checkout and a form.
///
/// Nothing here asks for a card number. A hungry person typing sixteen digits
/// is a hungry person abandoning an order.
class CheckoutSheet extends StatefulWidget {
  /// Creates the sheet.
  const CheckoutSheet({
    required this.selection,
    this.phone,
    this.offerDelivery = LaunchSwitches.delivery,
    this.offerCard = LaunchSwitches.cardPayment,
    super.key,
  });

  /// The plate being ordered.
  final PlateSelection selection;

  /// The guest's remembered mobile (normalised), or null the first time.
  final String? phone;

  /// Whether delivery is offered. Off: pickup only, no mode switch shown.
  final bool offerDelivery;

  /// Whether paying by card in the app is offered.
  final bool offerCard;

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  late OrderDraft _draft = OrderDraft(
    selection: widget.selection,
    mode:
        widget.offerDelivery ? FulfilmentMode.delivery : FulfilmentMode.pickup,
    // Preselected. A checkout that opens with nothing chosen has quietly made
    // the guest do the work twice.
    payment: widget.offerDelivery && widget.offerCard
        ? PaymentMethod.card
        : PaymentMethod.counter,
    address: SavedPlaces.defaultAddress,
    phone: widget.phone,
  );

  bool _placing = false;

  /// A remembered phone reads as one line until the guest asks to change it.
  late bool _editingPhone = widget.phone == null;
  late final TextEditingController _phoneText =
      TextEditingController(text: localPart(widget.phone));

  /// One key per order attempt. Kept while an attempt's outcome is unknown,
  /// so a retry after a lost answer finds the first order instead of making a
  /// second one.
  String _idempotencyKey = newIdempotencyKey();
  bool _outcomeUnknown = false;

  /// The kitchen's refusal, shown on the button until the guest changes
  /// something.
  LocalizedText? _refusal;

  /// Shown on a still-live button: try again.
  LocalizedText? _retryNotice;

  @override
  void dispose() {
    _phoneText.dispose();
    super.dispose();
  }

  /// Typing is not a choice: no haptic per keystroke.
  void _typePhone(String text) => _update(
        _draft.withPhone(israeliMobile(text)),
        haptic: false,
      );

  void _update(OrderDraft next, {bool haptic = true}) {
    if (next == _draft) return;
    if (haptic) MawzoonHaptics.selection();
    setState(() {
      _draft = next;
      _refusal = null;
      _retryNotice = null;
      if (!_outcomeUnknown) _idempotencyKey = newIdempotencyKey();
    });
  }

  Future<void> _place() async {
    if (!_draft.isPlaceableIn(MenuScope.of(context).availability) ||
        _placing ||
        _refusal != null) {
      return;
    }
    final OrderGatewayScope? scope = OrderGatewayScope.maybeOf(context);
    setState(() {
      _placing = true;
      _retryNotice = null;
    });
    MawzoonHaptics.medium();
    if (scope == null) {
      Navigator.of(context).pop(CheckoutResult(draft: _draft));
      return;
    }

    final PlaceOrderOutcome outcome = await scope.gateway.place(
      _draft,
      idempotencyKey: _idempotencyKey,
    );
    if (!mounted) return;
    switch (outcome) {
      case OrderPlaced():
        Navigator.of(context).pop(
          CheckoutResult(draft: _draft, placed: outcome),
        );
      case OrderRefused(retryable: true):
        setState(() {
          _placing = false;
          _outcomeUnknown = false;
          _retryNotice = outcome.message;
        });
      case OrderRefused(
          reason: RefusalReason.unpaidOrderOpen,
          :final String openOrderId,
        ):
        Navigator.of(context).pop(
          CheckoutResult(draft: _draft, openOrderId: openOrderId),
        );
      case OrderRefused():
        if (outcome.reason == RefusalReason.soldOut ||
            outcome.reason == RefusalReason.menuChanged) {
          scope.onMenuStale?.call();
        }
        setState(() {
          _placing = false;
          _outcomeUnknown = false;
          _refusal = outcome.message;
        });
      case OrderUnreachable():
        setState(() {
          _placing = false;
          _outcomeUnknown = true;
          _retryNotice = OrderUnreachable.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: context.space.snug,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.canvas,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.space.radiusPlatter),
          ),
          border: Border.all(color: context.colors.hairline),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _Grabber(),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsetsDirectional.symmetric(
                    horizontal: context.space.comfortable,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _PlateSummary(draft: _draft),
                      SizedBox(height: context.space.loose),
                      if (widget.offerDelivery) ...<Widget>[
                        const _SectionLabel(
                          text: LocalizedText(
                            ar: 'كيف تستلم',
                            en: 'How you get it',
                          ),
                        ),
                        SizedBox(height: context.space.snug),
                        _ModeSwitch(
                          mode: _draft.mode,
                          onChanged: (FulfilmentMode mode) =>
                              _update(_draft.withMode(mode)),
                        ),
                      ] else
                        const _PickupLine(),
                      if (_draft.mode == FulfilmentMode.delivery) ...<Widget>[
                        SizedBox(height: context.space.base),
                        _AddressPicker(
                          selected: _draft.address,
                          onChanged: (DeliveryAddress address) =>
                              _update(_draft.copyWith(address: address)),
                        ),
                        SizedBox(height: context.space.snug),
                        _PhoneEntry(
                          phone: _draft.phone,
                          editing: _editingPhone,
                          controller: _phoneText,
                          onChanged: _typePhone,
                          onEdit: () => setState(() => _editingPhone = true),
                        ),
                      ],
                      SizedBox(height: context.space.loose),
                      const _SectionLabel(
                        text: LocalizedText(
                          ar: 'طريقة الدفع',
                          en: 'Payment',
                        ),
                      ),
                      SizedBox(height: context.space.snug),
                      _PaymentPicker(
                        methods: <PaymentMethod>[
                          PaymentMethod.counter,
                          if (widget.offerCard) PaymentMethod.card,
                        ],
                        mode: _draft.mode,
                        selected: _draft.payment,
                        onChanged: (PaymentMethod method) =>
                            _update(_draft.copyWith(payment: method)),
                      ),
                      SizedBox(height: context.space.loose),
                      _PriceLines(breakdown: _draft.price),
                      SizedBox(height: context.space.base),
                    ],
                  ),
                ),
              ),
              _ConfirmBar(
                draft: _draft,
                placing: _placing,
                refusal: _refusal,
                retryNotice: _retryNotice,
                onPlace: _place,
                language: language,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.symmetric(
          vertical: context.space.base,
        ),
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.inkFaint,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final LocalizedText text;

  @override
  Widget build(BuildContext context) => MawzoonText(
        text.resolve(context.appLanguage),
        style: context.type.sectionTitle,
      );
}

/// What is being ordered, restated so the guest can confirm without going back.
class _PlateSummary extends StatelessWidget {
  const _PlateSummary({required this.draft});

  final OrderDraft draft;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Container(
      padding: EdgeInsetsDirectional.all(context.space.base),
      decoration: BoxDecoration(
        color: context.colors.structure,
        borderRadius: context.space.surfaceRadius,
        border: Border.all(color: context.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const BalanceBadge(size: 18),
              SizedBox(width: context.space.snug),
              MawzoonText(
                draft.summary.framing.headline.resolve(language),
                style: context.type.capsuleLabel,
                color: context.colors.olive,
              ),
              const Spacer(),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${draft.summary.displayKilocalories} kcal · '
                  'P${draft.summary.displayProteinGrams}',
                  style: context.type.macroUnit
                      .copyWith(color: context.colors.inkSoft),
                ),
              ),
            ],
          ),
          SizedBox(height: context.space.snug),
          for (final IngredientOption option in draft.components)
            Padding(
              padding: EdgeInsetsDirectional.only(top: context.space.tight),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.colors
                          .toneForSegmentOrdinal(option.segment.ordinal),
                    ),
                  ),
                  SizedBox(width: context.space.snug),
                  Expanded(
                    child: MawzoonText(
                      option.name.resolve(language),
                      style: context.type.caption,
                      color: context.colors.inkSoft,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// With delivery off there is nothing to choose: one line says how and when.
class _PickupLine extends StatelessWidget {
  const _PickupLine();

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Row(
      children: <Widget>[
        Icon(
          Icons.storefront_outlined,
          size: 20,
          color: context.colors.inkSoft,
        ),
        SizedBox(width: context.space.snug),
        Expanded(
          child: MawzoonText(
            language == AppLanguage.arabic
                ? 'استلام من المطعم · ${FulfilmentMode.pickup.estimate.ar}'
                : 'Pickup at the restaurant · '
                    '${FulfilmentMode.pickup.estimate.en}',
            style: context.type.caption,
            color: context.colors.inkSoft,
          ),
        ),
      ],
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final FulfilmentMode mode;
  final ValueChanged<FulfilmentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Row(
      children: <Widget>[
        for (final FulfilmentMode option in FulfilmentMode.values)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                end: option == FulfilmentMode.values.last
                    ? 0
                    : context.space.snug,
              ),
              child: _Choice(
                selected: option == mode,
                onPressed: () => onChanged(option),
                semanticLabel: option.label.resolve(language),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    MawzoonText(
                      option.label.resolve(language),
                      style: context.type.capsuleLabel,
                      color: option == mode
                          ? context.colors.ink
                          : context.colors.inkSoft,
                    ),
                    MawzoonText(
                      // The real question behind "delivery or pickup" is
                      // "when do I eat", so the answer is on the control.
                      option.estimate.resolve(language),
                      style: context.type.tagLabel,
                      color: context.colors.inkFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Saved addresses, one tap each.
///
/// Recognised by the label the guest gave them — "Home", "The gym" — because
/// nobody identifies their own address from the street line while hungry.
class _AddressPicker extends StatelessWidget {
  const _AddressPicker({required this.selected, required this.onChanged});

  final DeliveryAddress? selected;
  final ValueChanged<DeliveryAddress> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Column(
      children: <Widget>[
        for (final DeliveryAddress address in SavedPlaces.all)
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: context.space.snug),
            child: _Choice(
              selected: address.id == selected?.id,
              onPressed: () => onChanged(address),
              semanticLabel: '${address.label.resolve(language)}, '
                  '${address.summary}',
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        MawzoonText(
                          address.label.resolve(language),
                          style: context.type.dishName,
                        ),
                        MawzoonText(
                          address.summary,
                          style: context.type.caption,
                          color: context.colors.inkFaint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (address.directions != null)
                          MawzoonText(
                            address.directions!,
                            style: context.type.tagLabel,
                            color: context.colors.inkFaint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (address.id == selected?.id) const BalanceBadge(size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The delivery phone: a field the first time, one line once remembered.
///
/// Shown only under delivery (a pickup guest is standing at the counter), and
/// it says why it's asked — a number with a stated use is one people give.
class _PhoneEntry extends StatelessWidget {
  const _PhoneEntry({
    required this.phone,
    required this.editing,
    required this.controller,
    required this.onChanged,
    required this.onEdit,
  });

  final String? phone;
  final bool editing;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final bool ar = language == AppLanguage.arabic;
    final String? remembered = phone;

    if (!editing && remembered != null) {
      return Container(
        constraints: BoxConstraints(minHeight: context.space.thumbTarget),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.colors.hairline)),
        ),
        child: Row(
          children: <Widget>[
            // Label over number, not beside it: a phone number can't be
            // ellipsised, and side by side it overflows a 390pt phone.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  MawzoonText(
                    ar ? 'جوال التوصيل' : 'Delivery phone',
                    style: context.type.caption,
                    color: context.colors.inkSoft,
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      formatIsraeliMobile(remembered),
                      style: context.type.dishName
                          .copyWith(color: context.colors.ink),
                    ),
                  ),
                ],
              ),
            ),
            TactileFeedbackWell(
              onPressed: onEdit,
              semanticLabel: ar ? 'تغيير رقم الجوال' : 'Change phone number',
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: context.space.thumbTarget,
                  minWidth: context.space.thumbTarget,
                ),
                child: Center(
                  child: MawzoonText(
                    ar ? 'تغيير' : 'Change',
                    style: context.type.capsuleLabel,
                    color: context.colors.olive,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MawzoonText(
          ar ? 'رقم جوالك' : 'Your phone',
          style: context.type.capsuleLabel,
          color: context.colors.ink,
        ),
        SizedBox(height: context.space.tight),
        Directionality(
          // A phone number reads left to right inside an Arabic sentence.
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            keyboardType: TextInputType.phone,
            autofillHints: const <String>[
              AutofillHints.telephoneNumberNational,
            ],
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
              LengthLimitingTextInputFormatter(10),
            ],
            cursorColor: context.colors.ember,
            style: context.type.body.copyWith(
              color: context.colors.ink,
              fontWeight: FontWeight.w600,
            ),
            decoration: mawzoonInputDecoration(
              context,
              hint: '05X-XXX-XXXX',
            ),
          ),
        ),
        SizedBox(height: context.space.tight),
        MawzoonText(
          ar
              ? 'للسائق فقط إن احتاج أن يصل إليك. نحفظه لطلبك القادم.'
              : 'Only for the driver, if they need to reach you. '
                  'Saved for your next order.',
          style: context.type.caption,
          color: context.colors.inkSoft,
        ),
      ],
    );
  }
}

/// Counter or card, as big cards with what happens next written on them.
class _PaymentPicker extends StatelessWidget {
  const _PaymentPicker({
    required this.methods,
    required this.mode,
    required this.selected,
    required this.onChanged,
  });

  final List<PaymentMethod> methods;
  final FulfilmentMode mode;
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Column(
      children: <Widget>[
        for (final PaymentMethod method in methods)
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: context.space.snug),
            child: Builder(
              builder: (BuildContext context) {
                // Greyed with its reason, not hidden: a missing option makes
                // the guest wonder where it went.
                final bool usable =
                    !(method.pickupOnly && mode == FulfilmentMode.delivery);
                final bool chosen = usable && method == selected;
                return _Choice(
                  selected: chosen,
                  enabled: usable,
                  onPressed: () => onChanged(method),
                  semanticLabel: method.label.resolve(language),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        method == PaymentMethod.counter
                            ? Icons.storefront_outlined
                            : Icons.credit_card_outlined,
                        size: 28,
                        color: chosen
                            ? context.colors.olive
                            : context.colors.inkSoft,
                      ),
                      SizedBox(width: context.space.base),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            MawzoonText(
                              method.label.resolve(language),
                              style: context.type.dishName,
                              color: usable ? null : context.colors.inkFaint,
                            ),
                            MawzoonText(
                              (usable
                                      ? method.detail
                                      : PaymentMethod.pickupOnlyReason)
                                  .resolve(language),
                              style: context.type.tagLabel,
                              color: context.colors.inkFaint,
                            ),
                          ],
                        ),
                      ),
                      if (chosen) const BalanceBadge(size: 18),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// A selectable row, shared by every picker on the sheet.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.onPressed,
    required this.child,
    required this.semanticLabel,
    this.enabled = true,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final Widget child;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => TactileFeedbackWell(
        onPressed: enabled ? onPressed : null,
        enabled: enabled,
        selected: selected,
        semanticLabel: semanticLabel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: double.infinity,
          constraints: BoxConstraints(minHeight: context.space.thumbTarget),
          padding: EdgeInsetsDirectional.all(context.space.base),
          decoration: BoxDecoration(
            color: selected
                ? context.colors.structureElevated
                : enabled
                    ? context.colors.structure
                    : context.colors.canvas,
            borderRadius: context.space.controlRadius,
            border: Border.all(
              color: selected ? context.colors.olive : context.colors.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: child,
        ),
      );
}

class _PriceLines extends StatelessWidget {
  const _PriceLines({required this.breakdown});

  final PriceBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final (LocalizedText, Money)? vat = breakdown.includedTaxNote;
    return Column(
      children: <Widget>[
        for (final (LocalizedText label, Money amount) in <(
          LocalizedText,
          Money
        )>[...breakdown.lines(), if (vat != null) vat])
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: context.space.tight),
            child: Row(
              children: <Widget>[
                MawzoonText(
                  label.resolve(language),
                  style: context.type.caption,
                  color: context.colors.inkSoft,
                ),
                const Spacer(),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    amount.format(language),
                    style: context.type.macroUnit
                        .copyWith(color: context.colors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The second tap.
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.draft,
    required this.placing,
    required this.onPlace,
    required this.language,
    this.refusal,
    this.retryNotice,
  });

  final OrderDraft draft;
  final bool placing;
  final VoidCallback onPlace;
  final AppLanguage language;

  /// The kitchen's last "no". Disables the button, like a local blocker.
  final LocalizedText? refusal;

  /// Replaces the label on a live button after a failed send.
  final LocalizedText? retryNotice;

  @override
  Widget build(BuildContext context) {
    final LocalizedText? blocker = refusal ??
        draft.blockerIn(
          MenuScope.of(context).availability,
        );
    final bool ready = blocker == null && !placing;

    return Container(
      padding: EdgeInsetsDirectional.all(context.space.comfortable),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              MawzoonText(
                language == AppLanguage.arabic ? 'الإجمالي' : 'Total',
                style: context.type.capsuleLabel,
                color: context.colors.inkSoft,
              ),
              const Spacer(),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  draft.price.total.format(language),
                  style: context.type.sectionTitle
                      .copyWith(color: context.colors.ink),
                ),
              ),
            ],
          ),
          SizedBox(height: context.space.base),
          TactileFeedbackWell(
            onPressed: ready ? onPlace : null,
            enabled: ready,
            semanticLabel:
                language == AppLanguage.arabic ? 'تأكيد الطلب' : 'Place order',
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: context.space.thumbTarget),
              alignment: Alignment.center,
              padding: EdgeInsetsDirectional.symmetric(
                vertical: context.space.base,
              ),
              decoration: BoxDecoration(
                color: ready ? context.colors.ember : context.colors.structure,
                borderRadius: context.space.pillRadius,
                border:
                    ready ? null : Border.all(color: context.colors.hairline),
              ),
              child: MawzoonText(
                // When it cannot be placed, the button says what is missing
                // rather than sitting grey and silent.
                blocker?.resolve(language) ??
                    retryNotice?.resolve(language) ??
                    (language == AppLanguage.arabic
                        ? 'تأكيد الطلب'
                        : 'Place order'),
                style: context.type.buttonLabel,
                color: ready ? context.colors.onEmber : context.colors.inkFaint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
