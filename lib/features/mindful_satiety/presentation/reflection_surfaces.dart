import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme.dart';
import '../application/reflection_controller.dart';
import '../domain/satiety_insight.dart';
import 'reflection_sheet.dart';

/// Hands the [ReflectionController] down the tree. Absent in tests and
/// previews that don't care about the loop; every surface then hides itself.
class ReflectionScope extends InheritedNotifier<ReflectionController> {
  /// Creates the scope.
  const ReflectionScope({
    required ReflectionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or null.
  static ReflectionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReflectionScope>()
      ?.notifier;
}

/// The question, waiting quietly on the home screen when it's due. The path
/// that works when notifications are off.
class ReflectionCard extends StatelessWidget {
  /// Creates the card.
  const ReflectionCard({required this.onOpen, super.key});

  /// Opens the sheet.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return TactileFeedbackWell(
      onPressed: onOpen,
      semanticLabel: ReflectionCopy.question.resolve(language),
      child: Container(
        padding: EdgeInsetsDirectional.all(context.space.base),
        decoration: BoxDecoration(
          color: context.colors.structure,
          borderRadius: BorderRadius.circular(context.space.radiusSurface),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  MawzoonText(
                    ReflectionCopy.question.resolve(language),
                    style: context.type.capsuleLabel,
                    color: context.colors.ink,
                  ),
                  MawzoonText(
                    ReflectionCopy.eyebrow.resolve(language),
                    style: context.type.caption,
                    color: context.colors.inkSoft,
                  ),
                ],
              ),
            ),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              color: context.colors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// One suggestion, under the portion toggle. Never applied on its own.
class InsightLine extends StatelessWidget {
  /// Creates the line.
  const InsightLine({
    required this.insight,
    required this.onApplyScale,
    required this.onDismiss,
    super.key,
  });

  /// What to say.
  final SatietyInsight insight;

  /// Switches the portion, for a [PortionInsight].
  final ValueChanged<PortionScale> onApplyScale;

  /// Hides this kind for a while.
  final VoidCallback onDismiss;

  /// Hide label, for the restraint test and screen readers.
  static const LocalizedText hideLabel = LocalizedText(ar: 'إخفاء', en: 'Hide');

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final SatietyInsight insight = this.insight;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: context.space.tight,
            children: <Widget>[
              MawzoonText(
                insight.message.resolve(language),
                style: context.type.caption,
                color: context.colors.inkSoft,
              ),
              if (insight is PortionInsight)
                TactileFeedbackWell(
                  onPressed: () => onApplyScale(insight.suggested),
                  semanticLabel: insight.action.resolve(language),
                  child: Padding(
                    padding: EdgeInsetsDirectional.symmetric(
                      vertical: context.space.tight,
                    ),
                    child: MawzoonText(
                      insight.action.resolve(language),
                      style: context.type.capsuleLabel,
                      color: context.colors.olive,
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onDismiss,
          tooltip: hideLabel.resolve(language),
          icon: Icon(Icons.close_rounded, size: 18, color: context.colors.inkFaint),
        ),
      ],
    );
  }
}
