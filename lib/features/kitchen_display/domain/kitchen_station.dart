import '../../../core/localization/localized_text.dart';
import '../../../core/menu/dietary_metadata.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/plate_segment.dart';
import '../../../core/nutrition/portion_scale.dart';

/// The three places a Mawzoon plate is assembled.
///
/// They map one-to-one onto the plate's compartments, which is the point: a
/// guest's mental model and the line's physical layout are the same three
/// things, so a ticket never has to be translated on its way to the pass.
enum KitchenStation {
  /// Grill and meat.
  grill(
    segment: PlateSegment.protein,
    label: LocalizedText(ar: 'الشوّاية', en: 'Grill'),
  ),

  /// Starch: fryer, steamer, pot.
  starch(
    segment: PlateSegment.smartCarb,
    label: LocalizedText(ar: 'النشويات', en: 'Starch'),
  ),

  /// Cold prep: salads and greens.
  prep(
    segment: PlateSegment.vitalFiber,
    label: LocalizedText(ar: 'التحضير', en: 'Prep'),
  );

  const KitchenStation({required this.segment, required this.label});

  /// The plate compartment this station fills.
  final PlateSegment segment;

  /// The station's name on the board.
  final LocalizedText label;

  /// The station that fills [segment].
  static KitchenStation forSegment(PlateSegment segment) => switch (segment) {
        PlateSegment.protein => KitchenStation.grill,
        PlateSegment.smartCarb => KitchenStation.starch,
        PlateSegment.vitalFiber => KitchenStation.prep,
      };

  /// Stations in assembly order.
  static const List<KitchenStation> line = <KitchenStation>[
    grill,
    starch,
    prep,
  ];
}

/// One station's share of one ticket.
///
/// Everything the cook needs and nothing they do not: what it is, how much of
/// it, how it is made, and the one instruction that is easy to get wrong.
/// Derived entirely from the catalogue, so a change to a dish reaches the line
/// without a second table being edited.
final class StationInstruction {
  const StationInstruction._({
    required this.station,
    required this.option,
    required this.targetGrams,
    required this.method,
    required this.doneness,
    required this.note,
  });

  /// Derives the instruction for [option] at [scale].
  factory StationInstruction.from(IngredientOption option, PortionScale scale) {
    final PortionedComponent portion = option.atScale(scale);
    return StationInstruction._(
      station: KitchenStation.forSegment(option.segment),
      option: option,
      targetGrams: portion.portionGrams,
      method: option.method,
      doneness:
          option is ProteinOption ? option.doneness : Doneness.notApplicable,
      note: option.kitchenNote,
    );
  }

  /// Which station this belongs to.
  final KitchenStation station;

  /// The component being made.
  final IngredientOption option;

  /// Target **cooked** weight on the plate, in grams.
  ///
  /// Cooked, not raw. The whole nutritional promise rests on what reaches the
  /// tray, so the number the cook weighs against is the number the guest was
  /// shown.
  final double targetGrams;

  /// How it is cooked — which is also which equipment it goes on.
  final CookingMethod method;

  /// How far it is cooked, for grilled cuts.
  final Doneness doneness;

  /// The one instruction that is easy to get wrong.
  final LocalizedText? note;

  /// The target weight as the line reads it.
  int get displayGrams => targetGrams.round();

  /// Whether doneness is meaningful for this component.
  bool get hasDoneness => doneness != Doneness.notApplicable;

  @override
  String toString() =>
      'StationInstruction(${station.name}, ${option.id}, ${displayGrams}g)';
}
