import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/glycemic.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/mindful_satiety/domain/meal_snapshot.dart';
import 'package:mawzoon/features/mindful_satiety/domain/reflection_journal.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_answer.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';

/// A fixed afternoon, well clear of quiet hours either side of the due time.
final DateTime noon = DateTime(2026, 9, 24, 12);

MealSnapshot snapshot({
  PortionScale scale = PortionScale.standardBalance,
  GlycemicBalance balance = GlycemicBalance.balanced,
  DateTime? placedAt,
}) =>
    MealSnapshot(
      placedAt: placedAt ?? noon,
      scale: scale,
      glycemicBalance: balance,
      componentNames: const <LocalizedText>[
        LocalizedText(ar: 'دجاج', en: 'Chicken'),
      ],
      kilocalories: 550,
      proteinEnergyShare: 0.3,
      carbohydrateEnergyShare: 0.45,
      fatEnergyShare: 0.25,
      fiberGrams: 9,
    );

MealReflection reflection({
  SatietyLevel satiety = SatietyLevel.balanced,
  EnergyLevel energy = EnergyLevel.calm,
  PortionScale scale = PortionScale.standardBalance,
  GlycemicBalance balance = GlycemicBalance.balanced,
  int id = 0,
}) =>
    MealReflection(
      id: '$id',
      snapshot: snapshot(scale: scale, balance: balance),
      satiety: satiety,
      energy: energy,
      answeredAt: noon,
    );

/// A record whose journal holds [entries] (newest first).
ReflectionRecord recordOf(
  List<MealReflection> entries, {
  int? totalAnswered,
}) =>
    ReflectionRecord(
      journal: ReflectionJournal(entries),
      totalAnswered: totalAnswered ?? entries.length,
    );

OrderDraft draft({
  FulfilmentMode mode = FulfilmentMode.delivery,
  PortionScale scale = PortionScale.standardBalance,
}) =>
    OrderDraft(
      selection: PlateSelection(
        protein: MawzoonCatalog.herbGrilledBreast,
        carb: MawzoonCatalog.wholeBulgur,
        fiber: MawzoonCatalog.charredGardenVeggies,
        scale: scale,
      ),
      mode: mode,
      payment: PaymentMethod.wallet,
    );
