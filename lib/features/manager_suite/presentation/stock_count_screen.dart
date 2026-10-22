import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/arabic_count.dart';
import '../../../core/localization/localized_text.dart';
import '../../../core/measure/quantity.dart';
import '../../../ui_primitives/controls/mawzoon_input_decoration.dart';
import '../../../ui_primitives/controls/mawzoon_pill_button.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../application/manager_suite_controller.dart';
import '../domain/raw_ingredient.dart';
import '../domain/stock_entry.dart';

/// Opens count mode over the inventory.
Future<void> showStockCount(
  BuildContext context,
  ManagerSuiteController controller,
) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            StockCountScreen(controller: controller),
      ),
    );

/// A stock take: every ingredient in the order the store room is walked,
/// one field each, saved once.
///
/// A blank field means "not counted" and leaves that ingredient's book alone,
/// so a count can cover one shelf as well as the whole room.
class StockCountScreen extends StatefulWidget {
  /// Creates the screen.
  const StockCountScreen({required this.controller, super.key});

  /// The suite being counted.
  final ManagerSuiteController controller;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final Map<RawIngredient, TextEditingController> _fields =
      <RawIngredient, TextEditingController>{
    for (final RawIngredient i in RawStore.all) i: TextEditingController(),
  };

  @override
  void dispose() {
    for (final TextEditingController c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Filled fields, parsed. Null values are fields that don't parse.
  Map<RawIngredient, Quantity?> get _entries => <RawIngredient, Quantity?>{
        for (final MapEntry<RawIngredient, TextEditingController> e
            in _fields.entries)
          if (e.value.text.trim().isNotEmpty)
            e.key: parseBulkAmount(e.value.text, e.key.unit),
      };

  void _save() {
    final Map<RawIngredient, Quantity?> entries = _entries;
    for (final MapEntry<RawIngredient, Quantity?> e in entries.entries) {
      widget.controller.setCount(e.key, e.value!);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bool ar = context.appLanguage == AppLanguage.arabic;
    final Map<RawIngredient, Quantity?> entries = _entries;
    final bool anyInvalid = entries.values.contains(null);
    final int counted = entries.length;
    final bool canSave = counted > 0 && !anyInvalid;
    final bool nothingOnBook = RawStore.all
        .every((RawIngredient i) => widget.controller.ledger.onHand(i).isZero);

    final String saveLabel = counted == 0
        ? (ar ? 'احفظ الجرد' : 'Save count')
        : (ar
            ? 'احفظ جرد ${arabicItemsGenitive(counted)}'
            : 'Save $counted ${counted == 1 ? 'item' : 'items'}');

    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: context.space.section,
            vertical: context.space.loose,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: context.space.base,
                runSpacing: context.space.snug,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      MawzoonText(
                        ar ? 'المخزون' : 'Stock',
                        style: context.type.wordmark,
                      ),
                      SizedBox(width: context.space.base),
                      Container(
                        padding: EdgeInsetsDirectional.symmetric(
                          horizontal: context.space.base,
                          vertical: context.space.tight,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.structureElevated,
                          borderRadius: context.space.pillRadius,
                          border: Border.all(color: context.colors.olive),
                        ),
                        child: MawzoonText(
                          ar ? 'جرد' : 'Count',
                          style: context.type.capsuleLabel,
                          color: context.colors.olive,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      MawzoonPillButton(
                        label: ar ? 'إلغاء' : 'Cancel',
                        primary: false,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      SizedBox(width: context.space.snug),
                      MawzoonPillButton(
                        label: saveLabel,
                        primary: true,
                        onPressed: canSave ? _save : null,
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: context.space.comfortable),
              Container(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: context.space.comfortable,
                  vertical: context.space.base,
                ),
                decoration: BoxDecoration(
                  color: context.colors.structure,
                  borderRadius: context.space.surfaceRadius,
                  border: Border.all(color: context.colors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (nothingOnBook)
                      MawzoonText(
                        ar
                            ? 'القائمة كلها نافدة الآن: لم يُسجَّل أي جرد بعد.'
                            : 'The whole menu is sold out: no count recorded yet.',
                        style: context.type.dishName,
                      ),
                    MawzoonText(
                      ar
                          ? 'اكتب ما تعدّه على الرف. اترك الخانة فارغة لما لم تعدّه — يبقى رقمه كما هو. لا يُحفظ شيء حتى تضغط «احفظ».'
                          : "Type what you count on the shelf. Leave a field blank if you didn't count it — its number stays. Nothing saves until you press Save.",
                      style: context.type.capsuleLabel,
                      color: context.colors.inkSoft,
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.space.comfortable),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    // One column per ~380pt, up to one per storage area.
                    final int columns = (box.maxWidth / 380)
                        .floor()
                        .clamp(1, StorageArea.values.length);
                    final double gap = context.space.loose;
                    final double width =
                        (box.maxWidth - gap * (columns - 1)) / columns;
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: gap,
                        runSpacing: context.space.loose,
                        children: <Widget>[
                          for (final StorageArea area in StorageArea.values)
                            SizedBox(
                              width: width,
                              child: _AreaColumn(
                                area: area,
                                fields: _fields,
                                controller: widget.controller,
                                onChanged: () => setState(() {}),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaColumn extends StatelessWidget {
  const _AreaColumn({
    required this.area,
    required this.fields,
    required this.controller,
    required this.onChanged,
  });

  final StorageArea area;
  final Map<RawIngredient, TextEditingController> fields;
  final ManagerSuiteController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MawzoonText(
          area.label.resolve(language),
          style: context.type.eyebrow,
          color: context.colors.inkFaint,
        ),
        SizedBox(height: context.space.snug),
        for (final RawIngredient ingredient in RawStore.inArea(area))
          _CountRow(
            ingredient: ingredient,
            onBook: controller.ledger.onHand(ingredient),
            field: fields[ingredient]!,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.ingredient,
    required this.onBook,
    required this.field,
    required this.onChanged,
  });

  final RawIngredient ingredient;
  final Quantity onBook;
  final TextEditingController field;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final bool ar = language == AppLanguage.arabic;
    final String text = field.text.trim();
    final bool invalid =
        text.isNotEmpty && parseBulkAmount(text, ingredient.unit) == null;
    final String name = ingredient.name.resolve(language);

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.hairline)),
      ),
      padding: EdgeInsetsDirectional.symmetric(vertical: context.space.tight),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MawzoonText(
                  name,
                  style: context.type.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    MawzoonText(
                      ar ? 'في الدفتر: ' : 'On the book: ',
                      style: context.type.caption,
                      color: context.colors.inkFaint,
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        onBook.format(language),
                        style: context.type.caption
                            .copyWith(color: context.colors.inkFaint),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: context.space.snug),
          SizedBox(
            width: 132,
            child: StockAmountField(
              key: ValueKey<String>('count.${ingredient.id}'),
              controller: field,
              unit: ingredient.unit,
              invalid: invalid,
              semanticLabel: name,
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A number field in an ingredient's bulk unit, with the unit beside it.
class StockAmountField extends StatelessWidget {
  /// Creates the field.
  const StockAmountField({
    required this.controller,
    required this.unit,
    required this.onChanged,
    required this.semanticLabel,
    this.invalid = false,
    this.sign,
    this.autofocus = false,
    super.key,
  });

  /// The typed text.
  final TextEditingController controller;

  /// The ingredient's unit; the field shows its bulk label.
  final MeasureUnit unit;

  /// Called on every edit.
  final ValueChanged<String> onChanged;

  /// What a screen reader announces.
  final String semanticLabel;

  /// Whether the text doesn't parse (drawn with a terracotta ring).
  final bool invalid;

  /// `+` or `−` before the number, for a delivery or a write-off.
  final String? sign;

  /// Whether to take focus on open.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final InputDecoration base = mawzoonInputDecoration(
      context,
      hint: '—',
      prefix: sign == null
          ? null
          : Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: context.space.base,
              ),
              child: Text(
                sign!,
                style: context.type.sectionTitle.copyWith(
                  color: context.colors.olive,
                ),
              ),
            ),
    );
    return Semantics(
      label: semanticLabel,
      child: Directionality(
        // "12.4 kg" stays in that order inside an Arabic row.
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹.,٫]')),
            LengthLimitingTextInputFormatter(8),
          ],
          cursorColor: context.colors.ember,
          style: context.type.dishName.copyWith(color: context.colors.ink),
          decoration: base.copyWith(
            // Always shown (suffixText only appears once typing starts): the
            // unit is what stops "12.4" being read as grams.
            suffixIcon: Padding(
              padding: EdgeInsetsDirectional.only(end: context.space.base),
              child: Text(
                unit.bulk.resolve(context.appLanguage),
                style: context.type.capsuleLabel
                    .copyWith(color: context.colors.inkSoft),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(),
            enabledBorder: invalid
                ? OutlineInputBorder(
                    borderRadius: context.space.controlRadius,
                    borderSide:
                        BorderSide(color: context.colors.protein, width: 1.5),
                  )
                : controller.text.trim().isNotEmpty
                    ? OutlineInputBorder(
                        borderRadius: context.space.controlRadius,
                        borderSide:
                            BorderSide(color: context.colors.olive, width: 1.5),
                      )
                    : null,
          ),
        ),
      ),
    );
  }
}
