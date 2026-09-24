import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/measure/quantity.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/mawzoon_catalog.dart';
import '../../../core/menu/recipe_calibration.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../application/manager_suite_controller.dart';
import '../domain/plate_recipe.dart';
import '../domain/raw_ingredient.dart';
import 'inventory_screen.dart';

/// The recipe calibrator.
///
/// ## What this screen is actually for
///
/// A batch of chicken breast is not the chicken breast on the menu. It runs a
/// little leaner or a little fattier than the figure the panel publishes, and
/// a kitchen that weighs and tests its own product knows by how much. This is
/// where that measurement is entered.
///
/// Which makes it the most dangerous screen in the app. Every other screen
/// shows a guest a number; this one *changes* the number, for every guest, on
/// a panel some of them are making a dietary decision on. So it is built to
/// resist a mistake rather than to be quick: the published figure stays on
/// screen beside the new one, the projection updates live so a wrong number
/// looks wrong before it is saved, and a draft that describes an impossible
/// food cannot be committed at all.
class RecipeCalibratorScreen extends StatefulWidget {
  /// Creates the calibrator.
  const RecipeCalibratorScreen({required this.controller, super.key});

  /// The suite being managed.
  final ManagerSuiteController controller;

  @override
  State<RecipeCalibratorScreen> createState() => _RecipeCalibratorScreenState();
}

class _RecipeCalibratorScreenState extends State<RecipeCalibratorScreen> {
  late IngredientOption _published = MawzoonCatalog.all.first;
  late CalibrationDraft _draft = widget.controller.draftFor(_published);

  void _openComponent(IngredientOption published) {
    setState(() {
      _published = published;
      _draft = widget.controller.draftFor(published);
    });
  }

  void _edit(CalibrationField field, double value) =>
      setState(() => _draft = _draft.withField(field, value));

  void _save() {
    widget.controller.calibrate(_draft, published: _published);
    setState(() => _draft = widget.controller.draftFor(_published));
  }

  void _revert() {
    widget.controller.revertCalibration(_published.id);
    setState(() => _draft = widget.controller.draftFor(_published));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, _) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide =
                constraints.maxWidth >= ManagerMetrics.columnWidth * 2;
            final Widget picker = _ComponentPicker(
              controller: widget.controller,
              selectedId: _published.id,
              onChosen: _openComponent,
            );
            final Widget form = _CalibrationForm(
              controller: widget.controller,
              published: _published,
              draft: _draft,
              onEdit: _edit,
              onSave: _save,
              onRevert: _revert,
            );

            if (!wide) {
              return ListView(
                padding: EdgeInsetsDirectional.all(context.space.comfortable),
                children: <Widget>[
                  picker,
                  SizedBox(height: context.space.section),
                  form,
                ],
              );
            }
            return Padding(
              padding: EdgeInsetsDirectional.all(context.space.comfortable),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 300,
                    child: SingleChildScrollView(child: picker),
                  ),
                  SizedBox(width: context.space.section),
                  Expanded(child: SingleChildScrollView(child: form)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Which component is being measured.
class _ComponentPicker extends StatelessWidget {
  const _ComponentPicker({
    required this.controller,
    required this.selectedId,
    required this.onChosen,
  });

  final ManagerSuiteController controller;
  final String selectedId;
  final ValueChanged<IngredientOption> onChosen;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InventoryScreen.heading(
          context,
          const LocalizedText(ar: 'المكوّنات', en: 'Components'),
          trailing: '${controller.book.calibrations.length}',
        ),
        for (final IngredientOption option in MawzoonCatalog.all)
          TactileFeedbackWell(
            onPressed: () => onChosen(option),
            selected: option.id == selectedId,
            semanticLabel: option.name.resolve(language),
            child: Container(
              margin: EdgeInsetsDirectional.only(bottom: context.space.tight),
              constraints: const BoxConstraints(
                minHeight: ManagerMetrics.touchTarget,
              ),
              padding: EdgeInsetsDirectional.all(context.space.snug),
              decoration: BoxDecoration(
                color: option.id == selectedId
                    ? context.colors.structureElevated
                    : Colors.transparent,
                borderRadius: context.space.controlRadius,
                border: Border.all(
                  color: option.id == selectedId
                      ? context.colors.toneForSegmentOrdinal(
                          option.segment.ordinal,
                        )
                      : context.colors.hairline,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: MawzoonText(
                      option.name.resolve(language),
                      style: context.type.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // A dot, not a word. A manager scanning the list needs to
                  // see which dishes carry a measurement of their own; the
                  // measurement itself is one tap away.
                  if (controller.book.calibrationFor(option.id) != null)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.colors.ember,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The numbers, the findings, and what the change costs the store.
class _CalibrationForm extends StatelessWidget {
  const _CalibrationForm({
    required this.controller,
    required this.published,
    required this.draft,
    required this.onEdit,
    required this.onSave,
    required this.onRevert,
  });

  final ManagerSuiteController controller;
  final IngredientOption published;
  final CalibrationDraft draft;
  final void Function(CalibrationField field, double value) onEdit;
  final VoidCallback onSave;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final List<CalibrationFinding> findings = draft.review(published);
    final bool canSave =
        draft.canCommit(published) && draft.differsFrom(published);
    final bool isCalibrated =
        controller.book.calibrationFor(published.id) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InventoryScreen.heading(
          context,
          LocalizedText(
            ar: published.name.ar,
            en: published.name.en,
          ),
        ),
        _Projection(draft: draft, published: published),
        SizedBox(height: context.space.comfortable),
        for (final CalibrationField field in CalibrationField.values)
          _FieldRow(
            field: field,
            value: draft.valueOf(field),
            publishedValue: _publishedValue(published, field),
            finding: findings
                .where((CalibrationFinding f) => f.field == field)
                .firstOrNull,
            onChanged: (double v) => onEdit(field, v),
          ),
        SizedBox(height: context.space.base),
        _DrawPreview(
          controller: controller,
          published: published,
          draft: draft,
        ),
        SizedBox(height: context.space.comfortable),
        for (final CalibrationFinding finding in findings)
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: context.space.tight),
            child: Row(
              children: <Widget>[
                Icon(
                  finding.isBlocking
                      ? Icons.block_rounded
                      : Icons.info_outline_rounded,
                  size: 16,
                  color: finding.isBlocking
                      ? context.colors.protein
                      : context.colors.carb,
                ),
                SizedBox(width: context.space.snug),
                Expanded(
                  child: MawzoonText(
                    '${finding.field.label.resolve(language)}: '
                    '${finding.message.resolve(language)}',
                    style: context.type.caption,
                    color: finding.isBlocking
                        ? context.colors.protein
                        : context.colors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        SizedBox(height: context.space.base),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: canSave ? onSave : null,
                child: Text(
                  language == AppLanguage.arabic
                      ? 'احفظ القياس'
                      : 'Save measurement',
                ),
              ),
            ),
            if (isCalibrated) ...<Widget>[
              SizedBox(width: context.space.snug),
              TextButton(
                onPressed: onRevert,
                child: Text(
                  language == AppLanguage.arabic
                      ? 'عُد للمنشور'
                      : 'Back to published',
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static double _publishedValue(
    IngredientOption option,
    CalibrationField field,
  ) =>
      switch (field) {
        CalibrationField.portionGrams => option.basePortionGrams,
        CalibrationField.protein => option.baseMacros.proteinGrams,
        CalibrationField.carbohydrate => option.baseMacros.carbohydrateGrams,
        CalibrationField.fat => option.baseMacros.fatGrams,
        CalibrationField.fibre => option.baseMacros.dietaryFiberGrams,
        CalibrationField.sodium => option.baseMacros.sodiumMilligrams,
      };
}

/// What the plate will say, live, as the numbers move.
class _Projection extends StatelessWidget {
  const _Projection({required this.draft, required this.published});

  final CalibrationDraft draft;
  final IngredientOption published;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    // Atwater, applied to the draft rather than to a committed profile — the
    // point is to see the consequence before saving, not after.
    final double kcal = draft.proteinGrams * 4 +
        (draft.carbohydrateGrams - draft.dietaryFiberGrams).clamp(
              0,
              double.infinity,
            ) *
            4 +
        draft.dietaryFiberGrams * 2 +
        draft.fatGrams * 9;
    final double wasKcal = published.baseKilocalories;
    final double delta = kcal - wasKcal;

    return Container(
      padding: EdgeInsetsDirectional.all(context.space.base),
      decoration: BoxDecoration(
        color: context.colors.structure,
        borderRadius: context.space.surfaceRadius,
        border: Border.all(color: context.colors.hairline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: MawzoonText(
              language == AppLanguage.arabic
                  ? 'ما سيظهر للضيف'
                  : 'What the guest will see',
              style: context.type.tagLabel,
              color: context.colors.inkFaint,
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${kcal.round()} kcal',
              style: context.type.macroFigure.copyWith(
                color: context.colors.ink,
              ),
            ),
          ),
          if (delta.abs() >= 1) ...<Widget>[
            SizedBox(width: context.space.snug),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '${delta > 0 ? '+' : '−'}${delta.abs().round()}',
                style: context.type.macroUnit.copyWith(
                  color: delta > 0 ? context.colors.carb : context.colors.fiber,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One editable number, with what it used to be kept beside it.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.value,
    required this.publishedValue,
    required this.finding,
    required this.onChanged,
  });

  final CalibrationField field;
  final double value;
  final double publishedValue;
  final CalibrationFinding? finding;
  final ValueChanged<double> onChanged;

  /// The nudge a batch measurement actually needs.
  ///
  /// Typed entry on a tablet in a kitchen office is slower and more error-prone
  /// than a step, and batch variance is a nudge from a known figure rather than
  /// a fresh number. Sodium steps in tens because milligrams do.
  double get _step => field == CalibrationField.sodium ? 10 : 0.5;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final bool moved = value != publishedValue;
    final Color tone = finding?.isBlocking ?? false
        ? context.colors.protein
        : moved
            ? context.colors.ember
            : context.colors.inkFaint;

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: context.space.snug),
      child: Row(
        children: <Widget>[
          Expanded(
            child: MawzoonText(
              field.label.resolve(language),
              style: context.type.body,
            ),
          ),
          // The published figure never leaves the screen while its replacement
          // is being typed. A manager nudging a number has to be able to see
          // what they are nudging it away from.
          if (moved)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                _format(publishedValue),
                style: context.type.macroUnit.copyWith(
                  color: context.colors.inkFaint,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
          SizedBox(width: context.space.snug),
          _StepButton(
            icon: Icons.remove_rounded,
            semantic: '${field.label.resolve(language)} down',
            onPressed: () =>
                onChanged((value - _step).clamp(0, double.infinity)),
          ),
          SizedBox(
            width: 72,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                _format(value),
                textAlign: TextAlign.center,
                style: context.type.macroFigure.copyWith(color: tone),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            semantic: '${field.label.resolve(language)} up',
            onPressed: () => onChanged(value + _step),
          ),
        ],
      ),
    );
  }

  String _format(double v) {
    final String digits =
        v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    return field.isGrams ? '${digits}g' : '${digits}mg';
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.semantic,
    required this.onPressed,
  });

  final IconData icon;
  final String semantic;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TactileFeedbackWell(
        onPressed: onPressed,
        semanticLabel: semantic,
        child: Container(
          width: ManagerMetrics.touchTarget,
          height: ManagerMetrics.touchTarget,
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: context.colors.inkSoft),
        ),
      );
}

/// What the proposed portion costs the store.
///
/// The half of a calibration that is easy to forget. A portion measured 10%
/// heavier draws 10% more raw from every future order, and a manager who
/// cannot see that before saving finds out about it as a shortfall three days
/// later.
class _DrawPreview extends StatelessWidget {
  const _DrawPreview({
    required this.controller,
    required this.published,
    required this.draft,
  });

  final ManagerSuiteController controller;
  final IngredientOption published;
  final CalibrationDraft draft;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final PlateRecipe? recipe = MawzoonRecipes.forComponent(published.id);
    if (recipe == null) return const SizedBox.shrink();

    final double factor = published.basePortionGrams <= 0
        ? 1
        : draft.portionGrams / published.basePortionGrams;

    return Container(
      padding: EdgeInsetsDirectional.all(context.space.base),
      decoration: BoxDecoration(
        color: context.colors.structure,
        borderRadius: context.space.surfaceRadius,
        border: Border.all(color: context.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MawzoonText(
            language == AppLanguage.arabic
                ? 'ما يسحبه من المخزون'
                : 'What it draws from the store',
            style: context.type.tagLabel,
            color: context.colors.inkFaint,
          ),
          SizedBox(height: context.space.snug),
          for (final MapEntry<RawIngredient, Quantity> line in recipe
              .drawAt(
                PortionScale.standardBalance,
                segment: published.segment,
                portionFactor: factor,
              )
              .entries)
            Padding(
              padding: EdgeInsetsDirectional.symmetric(
                vertical: context.space.micro,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: MawzoonText(
                      line.key.name.resolve(language),
                      style: context.type.caption,
                      color: context.colors.inkSoft,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      line.value.format(language),
                      style: context.type.macroUnit.copyWith(
                        color: factor == 1
                            ? context.colors.inkSoft
                            : context.colors.ember,
                      ),
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
