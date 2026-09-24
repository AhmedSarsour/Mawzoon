import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/glycemic.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../cart_checkout/domain/order_draft.dart';

/// The plate as it was when the guest ordered it, frozen.
///
/// Never recomputed from today's menu: a recipe recalibrated after the order
/// (Module 09) would otherwise rewrite what the guest's answer was about.
final class MealSnapshot {
  /// Creates a snapshot.
  const MealSnapshot({
    required this.placedAt,
    required this.scale,
    required this.glycemicBalance,
    required this.componentNames,
    required this.kilocalories,
    required this.proteinEnergyShare,
    required this.carbohydrateEnergyShare,
    required this.fatEnergyShare,
    required this.fiberGrams,
  });

  /// Freezes a placed order.
  factory MealSnapshot.ofOrder(OrderDraft draft, {required DateTime placedAt}) {
    final NutritionalSummary summary = draft.summary;
    return MealSnapshot(
      placedAt: placedAt,
      scale: summary.scale,
      glycemicBalance: summary.glycemic.balance,
      componentNames: <LocalizedText>[
        for (final component in draft.components) component.name,
      ],
      kilocalories: summary.totalKilocalories,
      proteinEnergyShare: summary.proteinEnergyShare,
      carbohydrateEnergyShare: summary.carbohydrateEnergyShare,
      fatEnergyShare: summary.fatEnergyShare,
      fiberGrams: summary.totalMacros.dietaryFiberGrams,
    );
  }

  /// When the order was placed.
  final DateTime placedAt;

  /// The portion the guest chose.
  final PortionScale scale;

  /// How fast the plate's carbohydrate releases.
  final GlycemicBalance glycemicBalance;

  /// The dishes, by name. Shown on the reflection sheet so the guest
  /// recognises the meal instead of having to recall it.
  final List<LocalizedText> componentNames;

  /// Kept for the engine; never shown on the reflection surfaces.
  final double kilocalories;

  /// Share of energy from protein, 0–1.
  final double proteinEnergyShare;

  /// Share of energy from carbohydrate, 0–1.
  final double carbohydrateEnergyShare;

  /// Share of energy from fat, 0–1.
  final double fatEnergyShare;

  /// Dietary fibre on the plate.
  final double fiberGrams;
}
