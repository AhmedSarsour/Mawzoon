import 'package:flutter/material.dart';

import '../../../core/localization/arabic_count.dart';
import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/interaction/snap_carousel.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/mawzoon_colors.dart';
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
  static const double cardWidth = 288;

  /// Height of the row.
  static const double rowHeight = 136;

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

  /// The photo well's side length. 16px corner radius, one step tighter than
  /// the card's own — concentric corners read as the photo sitting inside
  /// the card rather than merely overlapping it.
  static const double photoSize = 96;

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
      // The card has a fixed height, set by the carousel's itemExtent. Text
      // is free to grow with the platform's accessibility setting up to a
      // point; past that, growing further can only overflow the fixed row
      // rather than fit anything more, so the scale is capped here — the
      // rest of the app still scales without limit.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsetsDirectional.all(context.space.base),
          decoration: BoxDecoration(
            color: context.colors.porcelain,
            borderRadius: context.space.surfaceRadius,
            // The ring replaces the old ember-border + elevation swap: one
            // signal for "this is the loaded plate" instead of two competing
            // ones (a border colour and a shadow depth) that used to change
            // together, which made neither read as the thing that mattered.
            border: Border.all(
              color: selected ? context.colors.olive : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: context.elevation.porcelain,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: photoSize,
                  height: photoSize,
                  child: switch (plate.imageAsset) {
                    final String asset => Image.asset(asset, fit: BoxFit.cover),
                    null => const _PlatePhotoFallback(),
                  },
                ),
              ),
              SizedBox(width: context.space.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MawzoonText(
                      plate.name.resolve(language),
                      style: context.type.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: context.space.tight),
                    // The one flexible line: at the base text scale it has
                    // room for two lines, and at a larger scale it gives up
                    // lines to `ellipsis` rather than pushing the figures row
                    // (or the card itself) into an overflow.
                    Expanded(
                      child: MawzoonText(
                        plate.tagline.resolve(language),
                        style: context.type.dishDescription,
                        color: context.colors.inkSoft,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _MacroBadges(summary: summary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dish photo not yet shot: a warm radial gradient, no icon and no text —
/// a placeholder that reads as "coming soon" rather than "broken image".
class _PlatePhotoFallback extends StatelessWidget {
  const _PlatePhotoFallback();

  @override
  Widget build(BuildContext context) {
    final MawzoonColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: <Color>[
            colors.ember.withValues(alpha: 0.16),
            colors.structureElevated,
          ],
        ),
      ),
    );
  }
}

/// The kcal and protein capsules under a chef card's tagline.
///
/// A [Wrap], not a [Row]: at a larger text scale a capsule grows past a
/// single line's width before it could ever overflow one, so the second
/// capsule drops to its own line instead of blowing out the card.
class _MacroBadges extends StatelessWidget {
  const _MacroBadges({required this.summary});

  final NutritionalSummary summary;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final int kcal = summary.displayKilocalories;
    final int protein = summary.displayProteinGrams;
    // Digits sit correctly inside either paragraph direction on their own —
    // no isolated LTR run is needed here the way the old Latin "kcal"/"P"
    // abbreviations needed one; every word around the number is now in the
    // paragraph's own language.
    final String kcalText = language == AppLanguage.arabic
        ? arabicKilocalories(kcal)
        : '$kcal kcal';
    final String proteinText = language == AppLanguage.arabic
        ? '$protein غ بروتين'
        : '${protein}g protein';

    return Wrap(
      spacing: context.space.tight,
      runSpacing: context.space.tight,
      children: <Widget>[
        _MacroBadge(
          text: kcalText,
          background: context.colors.kcalTint,
          foreground: context.colors.ink,
        ),
        _MacroBadge(
          text: proteinText,
          background: context.colors.protein.withValues(alpha: 0.10),
          foreground: context.colors.protein,
        ),
      ],
    );
  }
}

class _MacroBadge extends StatelessWidget {
  const _MacroBadge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: context.space.pillRadius,
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.snug,
          vertical: context.space.micro,
        ),
        child: MawzoonText(
          text,
          style: context.type.tagLabel,
          color: foreground,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
