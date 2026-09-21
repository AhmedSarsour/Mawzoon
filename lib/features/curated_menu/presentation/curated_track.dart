import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/interaction/snap_carousel.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../data/signature_plate_catalog.dart';
import '../domain/signature_plate.dart';

/// Track one: the chef's plates, one tap each.
///
/// The fast path for a guest who is hungry rather than curious. Everything a
/// decision needs is on the card — the name, the three components, the energy
/// and the protein — so nobody has to open a detail screen to find out what
/// they would be ordering. Opening a screen to decide whether to open a screen
/// is where hungry people give up.
///
/// The cards carry live figures for the portion currently selected, so
/// flipping the volume switch updates the whole row rather than leaving six
/// stale numbers behind a toggle that claims otherwise.
class CuratedTrack extends StatelessWidget {
  /// Creates the curated carousel.
  const CuratedTrack({
    required this.scale,
    required this.onPlateChosen,
    super.key,
    this.selectedPlateId,
    this.plates = SignaturePlateCatalog.all,
  });

  /// The portion the cards should cost and count at.
  final PortionScale scale;

  /// Called with the plate the guest tapped.
  final ValueChanged<SignaturePlate> onPlateChosen;

  /// The plate currently loaded, if it is one of these.
  final String? selectedPlateId;

  /// The plates to show.
  final List<SignaturePlate> plates;

  /// Width of one card.
  static const double cardWidth = 196;

  /// Height of the row.
  static const double rowHeight = 168;

  @override
  Widget build(BuildContext context) {
    return SnapCarousel(
      itemCount: plates.length,
      itemExtent: cardWidth,
      height: rowHeight,
      gutter: context.space.screenGutter,
      gap: context.space.snug,
      itemBuilder: (BuildContext context, int index) {
        final SignaturePlate plate = plates[index];
        return SignaturePlateCard(
          plate: plate,
          scale: scale,
          selected: plate.id == selectedPlateId,
          onPressed: () => onPlateChosen(plate),
        );
      },
    );
  }
}

/// One chef's plate, as a card.
class SignaturePlateCard extends StatelessWidget {
  /// Creates the card.
  const SignaturePlateCard({
    required this.plate,
    required this.scale,
    required this.onPressed,
    super.key,
    this.selected = false,
  });

  /// The plate shown.
  final SignaturePlate plate;

  /// The portion to cost and count at.
  final PortionScale scale;

  /// Called on tap.
  final VoidCallback onPressed;

  /// Whether this plate is the one currently loaded.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final NutritionalSummary summary = plate.summaryAt(scale);

    return TactileFeedbackWell(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: '${plate.name.resolve(language)}, '
          '${summary.displayKilocalories} kcal, '
          '${summary.displayProteinGrams}g protein',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsetsDirectional.all(context.space.base),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.structureElevated
              : context.colors.structure,
          borderRadius: context.space.surfaceRadius,
          border: Border.all(
            color: selected ? context.colors.ember : context.colors.hairline,
            width: selected ? 1.5 : 1,
          ),
          boxShadow:
              selected ? context.elevation.lifted : context.elevation.resting,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MawzoonText(
              plate.name.resolve(language),
              style: context.type.dishName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: context.space.tight),
            Expanded(
              child: MawzoonText(
                plate.tagline.resolve(language),
                style: context.type.caption,
                color: context.colors.inkFaint,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: context.space.snug),
            _PlateFigures(summary: summary),
          ],
        ),
      ),
    );
  }
}

class _PlateFigures extends StatelessWidget {
  const _PlateFigures({required this.summary});

  final NutritionalSummary summary;

  @override
  Widget build(BuildContext context) {
    // One isolated Latin run: an Arabic card must not reorder "501 kcal".
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: <Widget>[
          Text(
            '${summary.displayKilocalories}',
            style: context.type.capsuleLabel.copyWith(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'kcal',
            style:
                context.type.macroUnit.copyWith(color: context.colors.inkFaint),
          ),
          const Spacer(),
          Text(
            'P${summary.displayProteinGrams}',
            style:
                context.type.macroUnit.copyWith(color: context.colors.inkSoft),
          ),
        ],
      ),
    );
  }
}
