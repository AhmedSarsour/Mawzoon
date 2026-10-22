import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/measure/quantity.dart';
import '../../../ui_primitives/controls/mawzoon_pill_button.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../application/manager_suite_controller.dart';
import '../domain/raw_ingredient.dart';
import '../domain/stock_entry.dart';
import 'stock_count_screen.dart';

/// Records a delivery, a write-off or a count for one ingredient.
Future<void> showStockMovement(
  BuildContext context, {
  required ManagerSuiteController controller,
  required RawIngredient ingredient,
}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext context) =>
          StockMovementDialog(controller: controller, ingredient: ingredient),
    );

/// One ingredient, one movement, and what the book will say after it —
/// shown before saving, so "5 kg" typed as "50" is caught on the screen,
/// not at the next stock take.
class StockMovementDialog extends StatefulWidget {
  /// Creates the dialog.
  const StockMovementDialog({
    required this.controller,
    required this.ingredient,
    super.key,
  });

  /// The suite being changed.
  final ManagerSuiteController controller;

  /// The ingredient.
  final RawIngredient ingredient;

  @override
  State<StockMovementDialog> createState() => _StockMovementDialogState();
}

class _StockMovementDialogState extends State<StockMovementDialog> {
  // A delivery is the common case at a desk; counts go through count mode.
  StockMovement _movement = StockMovement.delivery;
  final TextEditingController _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Quantity? get _parsed =>
      parseBulkAmount(_amount.text, widget.ingredient.unit);

  void _save() {
    final Quantity amount = _parsed!;
    final RawIngredient i = widget.ingredient;
    switch (_movement) {
      case StockMovement.count:
        widget.controller.setCount(i, amount);
      case StockMovement.delivery:
        widget.controller.receive(i, amount);
      case StockMovement.writeOff:
        widget.controller.writeOff(i, amount);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final bool ar = language == AppLanguage.arabic;
    final Quantity onHand = widget.controller.ledger.onHand(widget.ingredient);
    final Quantity? amount = _parsed;
    final bool invalid = _amount.text.trim().isNotEmpty && amount == null;
    final Quantity? after =
        amount == null ? null : applyMovement(onHand, _movement, amount);

    String movementLabel(StockMovement m) => switch (m) {
          StockMovement.count => ar ? 'جرد' : 'Count',
          StockMovement.delivery => ar ? 'استلام' : 'Delivery',
          StockMovement.writeOff => ar ? 'هدر' : 'Write-off',
        };

    final String fieldLabel = switch (_movement) {
      StockMovement.count => ar ? 'الكمية على الرف' : 'On the shelf',
      StockMovement.delivery => ar ? 'الكمية المستلمة' : 'Amount received',
      StockMovement.writeOff => ar ? 'الكمية المهدرة' : 'Amount written off',
    };
    final String action = switch (_movement) {
      StockMovement.count => ar ? 'احفظ الجرد' : 'Save count',
      StockMovement.delivery => ar ? 'سجّل الاستلام' : 'Record delivery',
      StockMovement.writeOff => ar ? 'سجّل الهدر' : 'Record write-off',
    };

    Widget ltr(String text, TextStyle style) => Directionality(
          textDirection: TextDirection.ltr,
          child: Text(text, style: style),
        );

    return Dialog(
      backgroundColor: context.colors.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.space.radiusPlatter),
        side: BorderSide(color: context.colors.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: EdgeInsetsDirectional.all(context.space.loose),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MawzoonText(
                widget.ingredient.name.resolve(language),
                style: context.type.wordmark,
              ),
              Row(
                children: <Widget>[
                  MawzoonText(
                    ar ? 'في الدفتر الآن: ' : 'On the book now: ',
                    style: context.type.capsuleLabel,
                    color: context.colors.inkSoft,
                  ),
                  ltr(
                    onHand.format(language),
                    context.type.capsuleLabel
                        .copyWith(color: context.colors.inkSoft),
                  ),
                ],
              ),
              SizedBox(height: context.space.comfortable),
              Container(
                padding: EdgeInsetsDirectional.all(context.space.tight),
                decoration: BoxDecoration(
                  color: context.colors.structure,
                  borderRadius: context.space.controlRadius,
                ),
                child: Row(
                  children: <Widget>[
                    for (final StockMovement m in StockMovement.values)
                      Expanded(
                        child: TactileFeedbackWell(
                          onPressed: () => setState(() => _movement = m),
                          selected: m == _movement,
                          semanticLabel: movementLabel(m),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 44),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: m == _movement
                                  ? context.colors.porcelain
                                  : null,
                              borderRadius: BorderRadius.circular(
                                context.space.radiusControl - 3,
                              ),
                            ),
                            child: MawzoonText(
                              movementLabel(m),
                              style: context.type.capsuleLabel,
                              color: m == _movement
                                  ? context.colors.ink
                                  : context.colors.inkSoft,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: context.space.comfortable),
              MawzoonText(fieldLabel, style: context.type.capsuleLabel),
              SizedBox(height: context.space.tight),
              StockAmountField(
                controller: _amount,
                unit: widget.ingredient.unit,
                invalid: invalid,
                autofocus: true,
                semanticLabel: fieldLabel,
                sign: switch (_movement) {
                  StockMovement.count => null,
                  StockMovement.delivery => '+',
                  StockMovement.writeOff => '−',
                },
                onChanged: (_) => setState(() {}),
              ),
              if (after != null) ...<Widget>[
                SizedBox(height: context.space.base),
                Container(
                  padding: EdgeInsetsDirectional.all(context.space.base),
                  decoration: BoxDecoration(
                    color: context.colors.structure,
                    borderRadius: context.space.controlRadius,
                  ),
                  // Wraps onto two lines rather than overflow when the
                  // amounts are long.
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: context.space.snug,
                    children: <Widget>[
                      MawzoonText(
                        ar ? 'بعد الحفظ' : 'After saving',
                        style: context.type.capsuleLabel,
                        color: context.colors.inkSoft,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ltr(
                            onHand.format(language),
                            context.type.caption.copyWith(
                              color: context.colors.inkFaint,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          SizedBox(width: context.space.snug),
                          ltr(
                            after.format(language),
                            context.type.sectionTitle.copyWith(
                              // A write-off past zero is allowed (the book can
                              // run short) but shown in the warning tone.
                              color: after.minorUnits < 0
                                  ? context.colors.protein
                                  : context.colors.ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: context.space.loose),
              Row(
                children: <Widget>[
                  Expanded(
                    child: MawzoonPillButton(
                      label: ar ? 'إلغاء' : 'Cancel',
                      primary: false,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  SizedBox(width: context.space.snug),
                  Expanded(
                    flex: 2,
                    child: MawzoonPillButton(
                      label: action,
                      primary: true,
                      onPressed: amount == null ? null : _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
