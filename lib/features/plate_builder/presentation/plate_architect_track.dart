import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/menu/dietary_metadata.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/mawzoon_catalog.dart';
import '../../../core/menu/plate_segment.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/interaction/snap_carousel.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../domain/plate_selection.dart';

/// Track two: build the plate yourself, one compartment at a time.
///
/// A single carousel rather than three stacked rows. Three rows cannot all sit
/// in the thumb zone on a phone, and the two that do not are exactly the ones
/// a guest stops filling. Showing one compartment at a time keeps the live
/// choice under the thumb and turns the build into the three steps the model
/// already describes.
///
/// It advances on its own after each pick, so the common path — protein, carb,
/// greens, done — is three taps with no navigation between them. The stepper
/// above stays tappable, because a guest who wants to change their protein
/// back should not have to undo two other choices to reach it.
class PlateArchitectTrack extends StatefulWidget {
  /// Creates the architect track.
  const PlateArchitectTrack({
    required this.selection,
    required this.onOptionChosen,
    required this.onOptionCleared,
    super.key,
    this.initialSegment,
    this.onActiveSegmentChanged,
  });

  /// The plate as it currently stands.
  final PlateSelection selection;

  /// Called with the component the guest chose.
  final ValueChanged<IngredientOption> onOptionChosen;

  /// Called when the guest taps the component already in a compartment.
  final ValueChanged<PlateSegment> onOptionCleared;

  /// The compartment to open on first build. Defaults to the first empty one.
  final PlateSegment? initialSegment;

  /// Called when the open compartment changes.
  final ValueChanged<PlateSegment>? onActiveSegmentChanged;

  /// Width of one ingredient chip.
  static const double chipWidth = 158;

  /// Height of the chip row.
  static const double rowHeight = 132;

  @override
  State<PlateArchitectTrack> createState() => _PlateArchitectTrackState();
}

class _PlateArchitectTrackState extends State<PlateArchitectTrack> {
  late PlateSegment _active =
      widget.initialSegment ?? widget.selection.nextSegment ?? PlateSegment.protein;

  void _setActive(PlateSegment segment) {
    if (_active == segment) return;
    setState(() => _active = segment);
    widget.onActiveSegmentChanged?.call(segment);
  }

  void _choose(IngredientOption option) {
    final bool alreadyChosen =
        widget.selection.optionFor(option.segment)?.id == option.id;
    if (alreadyChosen) {
      widget.onOptionCleared(option.segment);
      return;
    }

    widget.onOptionChosen(option);

    // Advance to the next compartment still empty, working from the selection
    // this pick produces rather than the one currently on screen — the parent
    // has not rebuilt us yet.
    final PlateSelection next = widget.selection.select(option);
    final PlateSegment? following = next.nextSegment;
    if (following != null) _setActive(following);
  }

  @override
  void didUpdateWidget(PlateArchitectTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the plate was replaced wholesale — a curated plate loaded, or a
    // reset — re-open the first compartment that still needs a choice.
    if (oldWidget.selection == widget.selection) return;
    final PlateSegment? next = widget.selection.nextSegment;
    if (next != null && widget.selection.optionFor(_active) != null) {
      _setActive(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<IngredientOption> options = MawzoonCatalog.optionsFor(_active);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: context.space.screenGutter,
          ),
          child: _SegmentStepper(
            active: _active,
            selection: widget.selection,
            onSegmentChosen: _setActive,
          ),
        ),
        SizedBox(height: context.space.base),
        SnapCarousel(
          // Rebuilding the row when the compartment changes resets the scroll
          // to the start, which is what a new step should look like.
          key: ValueKey<PlateSegment>(_active),
          itemCount: options.length,
          itemExtent: PlateArchitectTrack.chipWidth,
          height: PlateArchitectTrack.rowHeight,
          gutter: context.space.screenGutter,
          gap: context.space.snug,
          itemBuilder: (BuildContext context, int index) {
            final IngredientOption option = options[index];
            return IngredientChip(
              option: option,
              scale: widget.selection.scale,
              selected: widget.selection.optionFor(_active)?.id == option.id,
              onPressed: () => _choose(option),
            );
          },
        ),
      ],
    );
  }
}

/// The three-step indicator above the carousel.
class _SegmentStepper extends StatelessWidget {
  const _SegmentStepper({
    required this.active,
    required this.selection,
    required this.onSegmentChosen,
  });

  final PlateSegment active;
  final PlateSelection selection;
  final ValueChanged<PlateSegment> onSegmentChosen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final PlateSegment segment in PlateSegment.buildOrder)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                end: segment == PlateSegment.vitalFiber
                    ? 0
                    : context.space.snug,
              ),
              child: _StepPill(
                segment: segment,
                active: segment == active,
                chosen: selection.optionFor(segment),
                onPressed: () => onSegmentChosen(segment),
              ),
            ),
          ),
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.segment,
    required this.active,
    required this.chosen,
    required this.onPressed,
  });

  final PlateSegment segment;
  final bool active;
  final IngredientOption? chosen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final Color tone = context.colors.toneForSegmentOrdinal(segment.ordinal);
    final bool filled = chosen != null;

    return TactileFeedbackWell(
      onPressed: onPressed,
      selected: active,
      semanticLabel: '${segment.label.resolve(language)}'
          '${filled ? ': ${chosen!.name.resolve(language)}' : ''}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.snug,
          vertical: context.space.snug,
        ),
        decoration: BoxDecoration(
          color: active
              ? context.colors.structureElevated
              : context.colors.structure,
          borderRadius: context.space.controlRadius,
          border: Border.all(
            color: active ? tone : context.colors.hairline,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                // A filled compartment is marked by a solid dot and an
                // unfilled one by a ring: state that survives being looked at
                // by someone who cannot distinguish the three tones.
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? tone : Colors.transparent,
                    border: filled ? null : Border.all(color: tone, width: 1.2),
                  ),
                ),
                SizedBox(width: context.space.tight + 1),
                Expanded(
                  child: MawzoonText(
                    segment.label.resolve(language),
                    style: context.type.tagLabel,
                    color: active
                        ? context.colors.ink
                        : context.colors.inkFaint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One component, as a chip in the architect carousel.
class IngredientChip extends StatelessWidget {
  /// Creates the chip.
  const IngredientChip({
    required this.option,
    required this.scale,
    required this.onPressed,
    super.key,
    this.selected = false,
  });

  /// The component shown.
  final IngredientOption option;

  /// The portion to count at.
  final PortionScale scale;

  /// Called on tap.
  final VoidCallback onPressed;

  /// Whether this component is the one in the compartment.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final Color tone = context.colors.toneForSegmentOrdinal(option.segment.ordinal);
    final PortionedComponent portion = option.atScale(scale);

    return TactileFeedbackWell(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: '${option.name.resolve(language)}, '
          '${portion.kilocalories.round()} kcal',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsetsDirectional.all(context.space.base),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.structureElevated
              : context.colors.structure,
          borderRadius: context.space.controlRadius,
          border: Border.all(
            color: selected ? tone : context.colors.hairline,
            width: selected ? 1.5 : 1,
          ),
          boxShadow:
              selected ? context.elevation.lifted : context.elevation.resting,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: MawzoonText(
                option.name.resolve(language),
                style: context.type.dishName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: context.space.tight),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '${portion.kilocalories.round()} kcal · '
                '${portion.portionGrams.round()}g',
                style: context.type.macroUnit.copyWith(
                  color: selected ? tone : context.colors.inkFaint,
                ),
              ),
            ),
            if (option.allergens.isNotEmpty) ...<Widget>[
              SizedBox(height: context.space.micro),
              MawzoonText(
                option.allergens
                    .map<String>((Allergen a) => a.label.resolve(language))
                    .join('، '),
                style: context.type.tagLabel,
                color: context.colors.ember,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
