import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/measure/quantity.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/stock_status.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/mawzoon_colors.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../application/manager_suite_controller.dart';
import '../domain/plate_recipe.dart';
import '../domain/raw_ingredient.dart';

/// Sizing for a back-office tool.
///
/// Deliberately not the kitchen's 64dp. This is read at a desk on a laptop or
/// a held tablet, by someone who is looking at it, so it runs at the platform
/// target and spends the space it saves on showing more of the count at once.
abstract final class ManagerMetrics {
  /// Minimum edge of anything tappable.
  static const double touchTarget = 48;

  /// The width a stock column wants before the board adds another.
  static const double columnWidth = 420;
}

/// The stock board: what is on the shelf, and what it lets the kitchen sell.
///
/// Two panels rather than one list. A manager arrives with one of two
/// questions — "what can I not sell tonight" or "what do I need to order" —
/// and a single list sorted one way answers only the first.
class InventoryScreen extends StatelessWidget {
  /// Creates the board.
  const InventoryScreen({required this.controller, super.key});

  /// The suite being managed.
  final ManagerSuiteController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide =
                constraints.maxWidth >= ManagerMetrics.columnWidth * 2;
            final Widget menu = _MenuPanel(controller: controller);
            final Widget store = _StorePanel(controller: controller);

            if (!wide) {
              return ListView(
                padding: EdgeInsetsDirectional.all(context.space.comfortable),
                children: <Widget>[
                  menu,
                  SizedBox(height: context.space.section),
                  store,
                ],
              );
            }
            return Padding(
              padding: EdgeInsetsDirectional.all(context.space.comfortable),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: SingleChildScrollView(child: menu)),
                  SizedBox(width: context.space.section),
                  Expanded(child: SingleChildScrollView(child: store)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// The heading used by both panels and by the calibrator.
  static Widget heading(
    BuildContext context,
    LocalizedText text, {
    String? trailing,
  }) =>
      Padding(
        padding: EdgeInsetsDirectional.only(bottom: context.space.base),
        child: Row(
          children: <Widget>[
            MawzoonText(
              text.resolve(context.appLanguage),
              style: context.type.sectionTitle,
            ),
            if (trailing != null) ...<Widget>[
              SizedBox(width: context.space.snug),
              MawzoonText(
                trailing,
                style: context.type.tagLabel,
                color: context.colors.inkFaint,
              ),
            ],
          ],
        ),
      );
}

/// What the menu can sell tonight.
class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.controller});

  final ManagerSuiteController controller;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final MenuAvailability availability = controller.availability;

    final List<IngredientOption> menu = controller.book.all
        .where(
          (IngredientOption o) => MawzoonRecipes.forComponent(o.id) != null,
        )
        .toList()
      ..sort((IngredientOption a, IngredientOption b) {
        final int left = availability.statusOf(a.id).portionsRemaining;
        final int right = availability.statusOf(b.id).portionsRemaining;
        return left.compareTo(right);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Scarcest first. A manager opening this wants the problems, and a
        // list in menu order buries them under nine dishes that are fine.
        InventoryScreen.heading(
          context,
          const LocalizedText(ar: 'ما يمكن بيعه', en: 'What can be sold'),
          trailing: '${availability.soldOut.length}',
        ),
        for (final IngredientOption option in menu)
          _ComponentRow(
            option: option,
            status: availability.statusOf(option.id),
            constraint: controller.ledger.bindingConstraintFor(
              option.id,
              portions: controller.book,
            ),
            language: language,
            onToggleOff: () => controller.setForcedOff(
              option.id,
              off: !controller.ledger.forcedOff.contains(option.id),
            ),
            forcedOff: controller.ledger.forcedOff.contains(option.id),
          ),
      ],
    );
  }
}

/// One dish and how many of it the store can still make.
class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.option,
    required this.status,
    required this.constraint,
    required this.language,
    required this.onToggleOff,
    required this.forcedOff,
  });

  final IngredientOption option;
  final StockStatus status;
  final RawIngredient? constraint;
  final AppLanguage language;
  final VoidCallback onToggleOff;
  final bool forcedOff;

  /// The tone for a status, reusing the plate's own macro palette rather than
  /// inventing a third traffic-light scheme for the back office.
  static Color toneFor(StockStatus status, MawzoonColors colors) =>
      switch (status) {
        InStock() => colors.fiber,
        RunningLow() => colors.carb,
        SoldOut() => colors.protein,
      };

  @override
  Widget build(BuildContext context) {
    final Color tone = toneFor(status, context.colors);
    final SoldOutReason? reason =
        status is SoldOut ? (status as SoldOut).reason : null;

    return Container(
      margin: EdgeInsetsDirectional.only(bottom: context.space.snug),
      constraints: const BoxConstraints(
        minHeight: ManagerMetrics.touchTarget,
      ),
      padding: EdgeInsetsDirectional.all(context.space.base),
      decoration: BoxDecoration(
        color: context.colors.structure,
        borderRadius: context.space.controlRadius,
        border: Border.all(color: context.colors.hairline),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: context.space.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MawzoonText(
                  option.name.resolve(language),
                  style: context.type.dishName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (reason != null)
                  MawzoonText(
                    // A manager is owed the reason, not just the state. "Off"
                    // is not actionable; "off because of the parsley" is.
                    constraint != null &&
                            reason == SoldOutReason.belowSafetyBuffer
                        ? '${reason.note.resolve(language)} · '
                            '${constraint!.name.resolve(language)}'
                        : reason.note.resolve(language),
                    style: context.type.tagLabel,
                    color: context.colors.inkFaint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(width: context.space.snug),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${status.portionsRemaining}',
              style: context.type.macroFigure.copyWith(color: tone),
            ),
          ),
          SizedBox(width: context.space.base),
          TactileFeedbackWell(
            onPressed: onToggleOff,
            selected: forcedOff,
            semanticLabel: forcedOff
                ? '${option.name.resolve(language)}, put back on'
                : '${option.name.resolve(language)}, take off',
            child: Container(
              constraints: const BoxConstraints(
                minWidth: ManagerMetrics.touchTarget,
                minHeight: ManagerMetrics.touchTarget,
              ),
              alignment: Alignment.center,
              child: Icon(
                forcedOff
                    ? Icons.play_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                color:
                    forcedOff ? context.colors.ember : context.colors.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What is on the shelf, walked in the order the shelves are.
class _StorePanel extends StatelessWidget {
  const _StorePanel({required this.controller});

  final ManagerSuiteController controller;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InventoryScreen.heading(
          context,
          const LocalizedText(ar: 'المخزون', en: 'On the shelf'),
        ),
        for (final StorageArea area in StorageArea.values) ...<Widget>[
          Padding(
            padding: EdgeInsetsDirectional.only(
              top: context.space.base,
              bottom: context.space.snug,
            ),
            child: MawzoonText(
              area.label.resolve(language),
              style: context.type.eyebrow,
              color: context.colors.inkFaint,
            ),
          ),
          for (final RawIngredient ingredient in RawStore.inArea(area))
            _StockRow(
              ingredient: ingredient,
              onHand: controller.ledger.onHand(ingredient),
              language: language,
            ),
        ],
      ],
    );
  }
}

/// One ingredient and what the book says is left of it.
class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.ingredient,
    required this.onHand,
    required this.language,
  });

  final RawIngredient ingredient;
  final Quantity onHand;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(vertical: context.space.tight),
      child: Row(
        children: <Widget>[
          Expanded(
            child: MawzoonText(
              ingredient.name.resolve(language),
              style: context.type.body,
              color: onHand.isZero
                  ? context.colors.inkFaint
                  : context.colors.inkSoft,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Directionality(
            // A measurement is a Latin expression even in an Arabic sentence:
            // "12.4 kg" must not be reordered into "kg 12.4".
            textDirection: TextDirection.ltr,
            child: Text(
              onHand.format(language),
              style: context.type.macroUnit.copyWith(
                color:
                    onHand.isZero ? context.colors.protein : context.colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
