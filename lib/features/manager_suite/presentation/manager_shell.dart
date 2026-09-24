import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../application/manager_suite_controller.dart';
import 'inventory_screen.dart';
import 'recipe_calibrator_screen.dart';

/// The two halves of the back office.
enum ManagerTab {
  /// What the store holds and what the menu can sell.
  inventory(label: LocalizedText(ar: 'المخزون', en: 'Inventory')),

  /// What the kitchen has measured.
  recipes(label: LocalizedText(ar: 'المقادير', en: 'Recipes'));

  const ManagerTab({required this.label});

  /// The tab's name.
  final LocalizedText label;
}

/// The manager suite.
///
/// Inventory opens first. A manager reaching for this on a Tuesday evening is
/// almost always asking what they can still sell, not re-measuring a recipe —
/// and the screen that answers the common question should not be the one
/// behind a tab.
class ManagerShell extends StatefulWidget {
  /// Creates the shell.
  const ManagerShell({required this.controller, super.key, this.initialTab});

  /// The suite being managed.
  final ManagerSuiteController controller;

  /// Which half to open on. Defaults to inventory.
  final ManagerTab? initialTab;

  @override
  State<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends State<ManagerShell> {
  late ManagerTab _tab = widget.initialTab ?? ManagerTab.inventory;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;

    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsetsDirectional.all(context.space.comfortable),
              child: Row(
                children: <Widget>[
                  MawzoonText(
                    language == AppLanguage.arabic ? 'الإدارة' : 'Back office',
                    style: context.type.display,
                  ),
                  const Spacer(),
                  for (final ManagerTab tab in ManagerTab.values) ...<Widget>[
                    SizedBox(width: context.space.snug),
                    _TabChip(
                      tab: tab,
                      active: tab == _tab,
                      onPressed: () => setState(() => _tab = tab),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                ManagerTab.inventory => InventoryScreen(
                    controller: widget.controller,
                  ),
                ManagerTab.recipes => RecipeCalibratorScreen(
                    controller: widget.controller,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onPressed,
  });

  final ManagerTab tab;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;

    return TactileFeedbackWell(
      onPressed: onPressed,
      selected: active,
      semanticLabel: tab.label.resolve(language),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: ManagerMetrics.touchTarget,
        ),
        alignment: Alignment.center,
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.comfortable,
        ),
        decoration: BoxDecoration(
          color: active ? context.colors.structureElevated : Colors.transparent,
          borderRadius: context.space.pillRadius,
          border: Border.all(
            color: active ? context.colors.ember : context.colors.hairline,
          ),
        ),
        child: MawzoonText(
          tab.label.resolve(language),
          style: context.type.buttonLabel,
          color: active ? context.colors.ink : context.colors.inkFaint,
        ),
      ),
    );
  }
}
