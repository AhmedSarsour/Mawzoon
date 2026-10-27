/// Features that are built but not offered yet.
///
/// Each switch has a twin on the server (`public.pricing`), and `place_order`
/// refuses what's off — so flipping one here alone can't turn a feature on.
abstract final class LaunchSwitches {
  /// Delivery: built, hidden until Mawzoon decides to deliver (Ahmed, 2026-10-22).
  static const bool delivery = false;

  /// Paying by card in the app: on once the payment provider is wired
  /// (Module 12, part E). Until then a card order would reach the kitchen unpaid.
  static const bool cardPayment = false;
}
