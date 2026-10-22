import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../text/mawzoon_text.dart';
import '../theme/theme_context.dart';

/// A full pill button: ember when it's the screen's one action, quiet
/// otherwise, and quiet-and-faint when it can't be pressed yet.
class MawzoonPillButton extends StatelessWidget {
  /// Creates the button.
  const MawzoonPillButton({
    required this.label,
    required this.primary,
    required this.onPressed,
    super.key,
  });

  /// The words on it.
  final String label;

  /// Whether it's the screen's one primary action.
  final bool primary;

  /// Null disables it.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool live = onPressed != null;
    final bool filled = primary && live;
    return TactileFeedbackWell(
      onPressed: onPressed,
      enabled: live,
      semanticLabel: label,
      child: Container(
        constraints: BoxConstraints(minHeight: context.space.thumbTarget),
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.loose,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              filled ? context.colors.ember : context.colors.structureElevated,
          borderRadius: context.space.pillRadius,
          border: filled ? null : Border.all(color: context.colors.hairline),
        ),
        child: MawzoonText(
          label,
          style: context.type.buttonLabel,
          color: filled
              ? context.colors.onEmber
              : (live ? context.colors.ink : context.colors.inkFaint),
        ),
      ),
    );
  }
}
