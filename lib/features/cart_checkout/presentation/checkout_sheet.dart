import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/pricing/money.dart';
import '../../../ui_primitives/controls/macro_capsule.dart';
import '../../../ui_primitives/interaction/haptics.dart';
import '../../../ui_primitives/interaction/pressable_scale.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../../plate_builder/domain/plate_selection.dart';
import '../domain/delivery_address.dart';
import '../domain/order_draft.dart';
import '../domain/saved_places.dart';

/// Opens the checkout sheet for [selection] and returns the placed order.
///
/// Returns `null` if the guest dismissed it. The caller decides what a placed
/// order means — this function's job ends at a confirmed [OrderDraft].
Future<OrderDraft?> showCheckoutSheet(
  BuildContext context, {
  required PlateSelection selection,
}) {
  return showModalBottomSheet<OrderDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => CheckoutSheet(selection: selection),
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
  const CheckoutSheet({required this.selection, super.key});

  /// The plate being ordered.
  final PlateSelection selection;

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  late OrderDraft _draft = OrderDraft(
    selection: widget.selection,
    mode: FulfilmentMode.delivery,
    // The fastest instrument, preselected. A checkout that opens with nothing
    // chosen has quietly made the guest do the work twice.
    payment: PaymentMethod.wallet,
    address: SavedPlaces.defaultAddress,
  );

  bool _placing = false;

  void _update(OrderDraft next) {
    if (next == _draft) return;
    MawzoonHaptics.selection();
    setState(() => _draft = next);
  }

  Future<void> _place() async {
    if (!_draft.isPlaceable || _placing) return;
    setState(() => _placing = true);
    MawzoonHaptics.medium();
    if (!mounted) return;
    Navigator.of(context).pop(_draft);
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
                            _update(_draft.copyWith(mode: mode)),
                      ),
                      if (_draft.mode == FulfilmentMode.delivery) ...<Widget>[
                        SizedBox(height: context.space.base),
                        _AddressPicker(
                          selected: _draft.address,
                          onChanged: (DeliveryAddress address) =>
                              _update(_draft.copyWith(address: address)),
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

class _PaymentPicker extends StatelessWidget {
  const _PaymentPicker({required this.selected, required this.onChanged});

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Column(
      children: <Widget>[
        for (final PaymentMethod method in PaymentMethod.values)
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: context.space.snug),
            child: _Choice(
              selected: method == selected,
              onPressed: () => onChanged(method),
              semanticLabel: method.label.resolve(language),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        MawzoonText(
                          method.label.resolve(language),
                          style: context.type.dishName,
                        ),
                        MawzoonText(
                          method.detail.resolve(language),
                          style: context.type.tagLabel,
                          color: context.colors.inkFaint,
                        ),
                      ],
                    ),
                  ),
                  if (method == selected) const BalanceBadge(size: 18),
                ],
              ),
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
  });

  final bool selected;
  final VoidCallback onPressed;
  final Widget child;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => PressableScale(
        onPressed: onPressed,
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
                : context.colors.structure,
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
    return Column(
      children: <Widget>[
        for (final (LocalizedText label, Money amount) in breakdown.lines())
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
  });

  final OrderDraft draft;
  final bool placing;
  final VoidCallback onPlace;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final LocalizedText? blocker = draft.blocker;
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
          PressableScale(
            onPressed: ready ? onPlace : null,
            enabled: ready,
            semanticLabel: language == AppLanguage.arabic
                ? 'تأكيد الطلب'
                : 'Place order',
            child: Container(
              width: double.infinity,
              constraints:
                  BoxConstraints(minHeight: context.space.thumbTarget),
              alignment: Alignment.center,
              padding: EdgeInsetsDirectional.symmetric(
                vertical: context.space.base,
              ),
              decoration: BoxDecoration(
                color:
                    ready ? context.colors.ember : context.colors.structure,
                borderRadius: context.space.pillRadius,
                border:
                    ready ? null : Border.all(color: context.colors.hairline),
              ),
              child: MawzoonText(
                // When it cannot be placed, the button says what is missing
                // rather than sitting grey and silent.
                blocker?.resolve(language) ??
                    (language == AppLanguage.arabic
                        ? 'تأكيد الطلب'
                        : 'Place order'),
                style: context.type.buttonLabel,
                color: ready
                    ? context.colors.onEmber
                    : context.colors.inkFaint,
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
