import 'package:flutter/widgets.dart';

import '../../core/menu/ingredient_option.dart';
import '../../core/menu/plate_segment.dart';
import '../../core/menu/recipe_book.dart';
import '../../core/menu/stock_status.dart';

/// The menu as served, handed down the tree.
///
/// Lives in `ui_primitives` rather than beside the types it carries because it
/// is a widget, and `core/` stays free of Flutter so the nutrition engine and
/// the store can be tested without a widget tree.
///
/// ## Why this is inherited rather than fetched
///
/// Two things about the menu change while people are using the app: what the
/// kitchen has measured, and what it can still make. Both are decided in the
/// back office and both have to reach a guest who is mid-plate.
///
/// Passing them down as an [InheritedWidget] makes the delivery mechanism the
/// same one Flutter already uses for the theme: a screen reads the menu at
/// build time, and when the menu changes every screen reading it rebuilds
/// once, with a consistent snapshot. No screen polls, no screen holds a stale
/// copy it forgot to refresh, and — the part that matters — no screen is ever
/// handed a half-updated menu, because [book] and [availability] arrive
/// together or not at all.
class MenuScope extends InheritedWidget {
  /// Creates a scope.
  const MenuScope({
    required super.child,
    super.key,
    this.book = RecipeBook.published,
    this.availability = MenuAvailability.everything,
  });

  /// The menu as the kitchen has measured it.
  final RecipeBook book;

  /// What the kitchen can still make.
  final MenuAvailability availability;

  /// The menu in force above [context].
  ///
  /// Falls back to the published menu with everything available, so a widget
  /// can be tested, or dropped into a screen with no back office attached,
  /// without a null check at every call site. A missing scope means "nothing
  /// has told me otherwise", which for a menu is the right default.
  static MenuScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MenuScope>() ??
      const MenuScope(child: SizedBox.shrink());

  /// The options for [segment], as measured, with their stock status.
  ///
  /// Sold-out components are *kept in the list*, not filtered out of it. A
  /// carousel that silently loses an item has moved everything the guest was
  /// reaching for; one that shows the item greyed has told them why. The
  /// difference is whether a guest thinks the app is broken.
  List<MenuEntry> entriesFor(BuildContext context, PlateSegment segment) =>
      <MenuEntry>[
        for (final IngredientOption option in book.optionsFor(segment))
          MenuEntry(option: option, status: availability.statusOf(option.id)),
      ];

  @override
  bool updateShouldNotify(MenuScope oldWidget) =>
      oldWidget.book != book || oldWidget.availability != availability;
}

/// One component and whether it can be ordered.
final class MenuEntry {
  /// Creates an entry.
  const MenuEntry({required this.option, required this.status});

  /// The component, as measured.
  final IngredientOption option;

  /// What the store says about it.
  final StockStatus status;

  /// Whether a guest can choose it.
  bool get isOrderable => status.isOrderable;

  @override
  String toString() => 'MenuEntry(${option.id}, $status)';
}
