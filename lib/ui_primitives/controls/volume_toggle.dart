import 'package:flutter/material.dart';

import '../../core/localization/localized_text.dart';
import '../../core/nutrition/portion_scale.dart';
import '../motion/motion.dart';
import '../text/mawzoon_text.dart';
import '../theme/mawzoon_spacing.dart';
import '../theme/theme_context.dart';

/// The binary volume switch: Standard Balance or Athletic Load.
///
/// Two options and no slider. A hungry guest resolves a binary in well under
/// a second, where a continuous control forces them to invent a preference
/// they do not have and then second-guess it.
///
/// It lives in the dock rather than inside either track, because the portion
/// is a property of the plate and not of how the plate was chosen. Duplicating
/// it per track would let two copies disagree, and the guest would be right to
/// trust neither.
class VolumeToggle extends StatelessWidget {
  /// Creates the volume switch.
  const VolumeToggle({
    required this.scale,
    required this.onChanged,
    super.key,
    this.showNominal = true,
  });

  /// The scale currently in force.
  final PortionScale scale;

  /// Called with the scale the guest chose.
  final ValueChanged<PortionScale> onChanged;

  /// Whether to print the nominal energy under each label.
  final bool showNominal;

  @override
  Widget build(BuildContext context) {
    final MawzoonSpacing space = context.space;
    return Container(
      padding: EdgeInsetsDirectional.all(space.micro + 1),
      decoration: BoxDecoration(
        color: context.colors.structure,
        borderRadius: space.pillRadius,
        border: Border.all(color: context.colors.hairline),
      ),
      child: Row(
        children: <Widget>[
          for (final PortionScale option in PortionScale.values)
            Expanded(
              child: _VolumeOption(
                option: option,
                selected: option == scale,
                showNominal: showNominal,
                onPressed: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _VolumeOption extends StatelessWidget {
  const _VolumeOption({
    required this.option,
    required this.selected,
    required this.showNominal,
    required this.onPressed,
  });

  final PortionScale option;
  final bool selected;
  final bool showNominal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return TactileFeedbackWell(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: option.label.resolve(language),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsetsDirectional.symmetric(
          vertical: context.space.snug,
          horizontal: context.space.snug,
        ),
        decoration: BoxDecoration(
          color: selected ? context.colors.structureElevated : Colors.transparent,
          borderRadius: context.space.pillRadius,
          boxShadow: selected ? context.elevation.resting : const <BoxShadow>[],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MawzoonText(
              option.label.resolve(language),
              style: context.type.capsuleLabel,
              color: selected ? context.colors.ink : context.colors.inkSoft,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (showNominal) ...<Widget>[
              const SizedBox(height: 1),
              // A Latin figure inside Arabic flow: isolated so the bidi
              // algorithm cannot reorder "~550 kcal" into nonsense.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '~${option.nominalKilocalories} kcal',
                  style: context.type.macroUnit.copyWith(
                    color: selected
                        ? context.colors.inkSoft
                        : context.colors.inkFaint,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
