import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/localization/arabic_count.dart';
import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/mawzoon_brand.dart';
import '../../../ui_primitives/theme/mawzoon_colors.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../data/signature_plate_catalog.dart';
import '../../plate_builder/domain/plate_selection.dart';
import '../domain/signature_plate.dart';

/// Track one: the chef's plates, one tap each.
///
/// The fast path for a guest who is hungry rather than curious. Everything a
/// decision needs is on the card — the name, the three components, the energy
/// and the protein — so nobody has to open a detail screen to find out what
/// they would be ordering. Opening a screen to decide whether to open a screen
/// is where hungry people give up.
///
/// One plate sits centred and large; the plate before and after it peek in at
/// a smaller scale. Swiping — or tapping a peeking card — animates it to the
/// centre while it grows, and that is also the moment it becomes the loaded
/// plate: browsing and choosing are the same gesture here, not two steps.
class CuratedTrack extends StatefulWidget {
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

  /// Called with the plate that has become centred.
  final ValueChanged<SignaturePlate> onPlateChosen;

  /// The plate currently loaded, if it is one of these.
  final String? selectedPlateId;

  /// The plates to show.
  final List<SignaturePlate> plates;

  /// Width of the centred card's own render box, used to size it in
  /// isolation (widget tests). The carousel itself sizes the centred card as
  /// a fraction of the viewport (`_viewportFraction`) so it stays
  /// proportionate from a 320pt phone up.
  static const double cardWidth = 210;

  /// Height of the carousel row: the card plus a little air for its shadow.
  static const double rowHeight = 300;

  /// Height of one card. The 4:3 photo is the flexible part: at a large text
  /// scale the text block grows and the photo gives up height to it, so the
  /// card never overflows.
  static const double cardHeight = 288;

  /// Share of the viewport the centred card occupies. The remainder splits
  /// between the two peeking neighbours, which is what tells the guest there
  /// is more to swipe to.
  static const double _viewportFraction = 0.68;

  /// How far a peeking card shrinks relative to the centred one.
  static const double _sideScale = 0.84;

  /// The widest a card may grow. Past this the 4:3 photo would push the card
  /// taller than [rowHeight]; a phone never gets here, but a foldable or a
  /// tablet in a phone-sized window might.
  static const double maxCardWidth = 300;

  @override
  State<CuratedTrack> createState() => _CuratedTrackState();
}

class _CuratedTrackState extends State<CuratedTrack> {
  late final PageController _controller = PageController(
    viewportFraction: CuratedTrack._viewportFraction,
    initialPage: _indexOf(widget.selectedPlateId),
  );

  int _indexOf(String? plateId) {
    if (plateId == null) return 0;
    final int i =
        widget.plates.indexWhere((SignaturePlate p) => p.id == plateId);
    return i < 0 ? 0 : i;
  }

  void _onCardPressed(int index) {
    if (!_controller.hasClients) return;
    final int centred = (_controller.page ?? _controller.initialPage).round();
    if (index == centred) {
      // Already centred, so there is no page change to report: choose it
      // directly. This is the first-tap path too, since the plate opens on
      // the first card without having loaded it.
      widget.onPlateChosen(widget.plates[index]);
      return;
    }
    // A peeking card: centre it. `onPageChanged` reports the choice once it
    // arrives, so it is never reported twice.
    unawaited(
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _onPageChanged(int index) {
    widget.onPlateChosen(widget.plates[index]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // Take the height on offer, up to the design height. The card keeps
        // a little air inside the row for its shadow.
        final double rowHeight = box.hasBoundedHeight
            ? math.min(CuratedTrack.rowHeight, box.maxHeight)
            : CuratedTrack.rowHeight;
        return _buildRow(context, rowHeight, box.maxWidth);
      },
    );
  }

  Widget _buildRow(BuildContext context, double rowHeight, double rowWidth) {
    return SizedBox(
      height: rowHeight,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.plates.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (BuildContext context, int index) {
          final SignaturePlate plate = widget.plates[index];
          return AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              final double page =
                  _controller.hasClients && _controller.position.haveDimensions
                      ? (_controller.page ?? index.toDouble())
                      : _controller.initialPage.toDouble();
              final double distance = (page - index).abs().clamp(0.0, 1.0);
              final double scale = ui.lerpDouble(
                1,
                CuratedTrack._sideScale,
                distance,
              )!;
              // A shrunken card leaves a gap on its inner side; slide it toward
              // the centre by exactly what it lost, so the gap between cards
              // stays a constant few pixels (reference: cards nearly touch).
              final bool rtl = Directionality.of(context) == TextDirection.rtl;
              final double toward = (index - page).sign * (rtl ? 1 : -1);
              final double cardWidth = math.min(
                rowWidth * CuratedTrack._viewportFraction,
                CuratedTrack.maxCardWidth,
              );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: CuratedTrack.maxCardWidth,
                  ),
                  child: Transform.translate(
                    offset: Offset(
                      toward * distance * (1 - scale) * cardWidth / 2,
                      0,
                    ),
                    child: Transform.scale(scale: scale, child: child),
                  ),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: context.space.micro,
              ),
              child: SizedBox(
                height: rowHeight -
                    (CuratedTrack.rowHeight - CuratedTrack.cardHeight),
                child: SignaturePlateCard(
                  plate: plate,
                  scale: widget.scale,
                  selected: plate.id == widget.selectedPlateId,
                  onPressed: () => _onCardPressed(index),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One chef's plate, as a tall card.
///
/// Photo on top, full width; the name, a one-line tagline and a single quiet
/// meta line beneath it. No pill badges here — the photo is what the eye
/// lands on first, and a card that competes with itself for attention is a
/// worse card (K4).
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
    final int kcal = summary.displayKilocalories;
    final int protein = summary.displayProteinGrams;
    final String metaText = language == AppLanguage.arabic
        ? '${arabicKilocalories(kcal)} · $protein غ بروتين'
        : '$kcal kcal · ${protein}g protein';

    return TactileFeedbackWell(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: '${plate.name.resolve(language)}, '
          '${summary.displayKilocalories} kcal, '
          '${summary.displayProteinGrams}g protein',
      // The card has a fixed height, set by the carousel's row height. Text
      // is free to grow with the platform's accessibility setting up to a
      // point; past that, growing further can only overflow the fixed card
      // rather than fit anything more, so the scale is capped here — the
      // rest of the app still scales without limit.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: DecoratedBox(
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
          child: ClipRRect(
            borderRadius: context.space.surfaceRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      switch (plate.imageAsset) {
                        final String asset => LayoutBuilder(
                            builder:
                                (BuildContext context, BoxConstraints box) =>
                                    Image.asset(
                              asset,
                              fit: BoxFit.cover,
                              // Decode at display size, not file size: six
                              // 1200px WebPs would otherwise all sit in memory
                              // at full resolution.
                              cacheWidth: (box.maxWidth *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                              // A missing or corrupt file shows the warm
                              // placeholder, never a broken-image icon.
                              errorBuilder: (_, __, ___) =>
                                  const _PlatePhotoFallback(),
                            ),
                          ),
                        null => _PlateComposite(
                            selection: plate.selectionAt(scale),
                          ),
                      },
                      if (plate.badge case final LocalizedText badge)
                        PositionedDirectional(
                          top: context.space.snug,
                          start: context.space.snug,
                          child: _PlateBadge(text: badge.resolve(language)),
                        ),
                    ],
                  ),
                ),
                // Never scrolls: it only stops a very short card (a 320pt
                // phone) from throwing an overflow. The photo above gives up
                // height first; past that the last line clips.
                Flexible(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsetsDirectional.all(context.space.base),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          MawzoonText(
                            plate.name.resolve(language),
                            style: context.type.sectionTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: context.space.tight),
                          MawzoonText(
                            plate.tagline.resolve(language),
                            style: context.type.dishDescription,
                            color: context.colors.inkSoft,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: context.space.tight),
                          MawzoonText(
                            metaText,
                            style: context.type.caption,
                            color: context.colors.inkFaint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "مميز" / "Chef's pick" pill on the house default's photo (K5).
///
/// `MawzoonBrand.warmMaize` used as a raw fill — allowed, like other brand
/// hexes used directly as a fill rather than composed into a themed role.
class _PlateBadge extends StatelessWidget {
  const _PlateBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final Color ink = context.colors.bestInkOn(MawzoonBrand.warmMaize);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MawzoonBrand.warmMaize,
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
          color: ink,
          maxLines: 1,
        ),
      ),
    );
  }
}

/// A plate card with no plate photo yet: the plate's three component cut-outs
/// arranged in a dark stoneware bowl, so the card shows the real food.
///
/// Falls back to [_PlatePhotoFallback] if none of the components has a photo.
class _PlateComposite extends StatelessWidget {
  const _PlateComposite({required this.selection});

  final PlateSelection selection;

  @override
  Widget build(BuildContext context) {
    final List<String?> assets = <String?>[
      selection.protein?.imageAsset,
      selection.carb?.imageAsset,
      selection.fiber?.imageAsset,
    ];
    if (assets.every((String? a) => a == null)) {
      return const _PlatePhotoFallback();
    }
    final MawzoonColors colors = context.colors;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double bowl = math.min(box.maxWidth, box.maxHeight) * 0.98;
        // (dx, dy) of the food's centre from the bowl's centre, and its size
        // as a fraction of the bowl: protein leads, carb and greens flank it.
        const List<(double, double, double)> spots = <(double, double, double)>[
          (-0.14, 0.02, 0.66),
          (0.24, 0.20, 0.50),
          (0.20, -0.24, 0.46),
        ];
        Widget food(int i) {
          final String? asset = assets[i];
          if (asset == null) return const SizedBox.shrink();
          final (double dx, double dy, double size) = spots[i];
          return Positioned(
            left: box.maxWidth / 2 + dx * bowl - size * bowl / 2,
            top: box.maxHeight / 2 + dy * bowl - size * bowl / 2,
            width: size * bowl,
            height: size * bowl,
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              cacheWidth: (size * bowl * dpr).round(),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          );
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: <Color>[
                colors.structureElevated,
                colors.structure,
              ],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              Center(
                child: Container(
                  width: bowl,
                  height: bowl,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: <Color>[Color(0xFF3A342E), Color(0xFF1E1A17)],
                    ),
                    border: Border.all(
                      color: const Color(0xFF574E45),
                      width: 3,
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 12,
                        offset: Offset(3, 6),
                      ),
                    ],
                  ),
                ),
              ),
              food(2),
              food(1),
              food(0),
            ],
          ),
        );
      },
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
