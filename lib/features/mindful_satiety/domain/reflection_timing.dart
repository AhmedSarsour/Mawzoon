import '../../cart_checkout/domain/delivery_address.dart';

/// When to ask "how does your body feel?", and when the question goes stale.
///
/// We only know when the order was placed, so the meal is assumed to start
/// once the order could have arrived, and the question comes 45 minutes later.
abstract final class ReflectionTiming {
  /// Time from the start of the meal to the question.
  static const Duration afterMeal = Duration(minutes: 45);

  /// How long an unanswered question stays open. Past this, an answer is a
  /// guess, and a guess would mislead the correlation engine.
  static const Duration answerWindow = Duration(hours: 4);

  /// Local hour quiet hours start (inclusive).
  static const int quietFromHour = 22;

  /// Local hour quiet hours end (exclusive).
  static const int quietUntilHour = 7;

  /// When the question is due for an order placed at [placedAt].
  static DateTime dueAt(DateTime placedAt, FulfilmentMode mode) =>
      placedAt.add(mode.readyWithin).add(afterMeal);

  /// When a question due at [dueAt] stops being worth asking.
  static DateTime expiresAt(DateTime dueAt) => dueAt.add(answerWindow);

  /// Whether [moment] falls in quiet hours on the device's clock. No
  /// notification is sent then; the question still waits in the app.
  static bool isQuietHour(DateTime moment) {
    final int hour = moment.toLocal().hour;
    return hour >= quietFromHour || hour < quietUntilHour;
  }
}
