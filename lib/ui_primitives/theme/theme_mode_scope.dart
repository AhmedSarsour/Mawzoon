import 'package:flutter/material.dart';

/// Lets any screen read and flip the app's light/dark choice.
///
/// An inherited widget rather than a callback threaded down the tree: the
/// toggle sits in a header deep inside the order screen. `maybeOf` returns
/// `null` when no scope exists (tests, the workbench), and the toggle hides.
class ThemeModeScope extends InheritedWidget {
  /// Creates the scope.
  const ThemeModeScope({
    required this.mode,
    required this.onChanged,
    required super.child,
    super.key,
  });

  /// The mode currently applied by the app.
  final ThemeMode mode;

  /// Asks the app to switch to [ThemeMode].
  final ValueChanged<ThemeMode> onChanged;

  /// The nearest scope, or `null`.
  static ThemeModeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeModeScope>();

  @override
  bool updateShouldNotify(ThemeModeScope old) => mode != old.mode;
}
