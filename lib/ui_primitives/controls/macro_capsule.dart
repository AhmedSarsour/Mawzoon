import 'package:flutter/material.dart';

import '../../core/localization/localized_text.dart';
import '../../core/nutrition/macro_targets.dart';
import '../../core/nutrition/nutritional_summary.dart';
import '../../core/nutrition/portion_scale.dart';
import '../../core/pricing/money.dart';
import '../interaction/pressable_scale.dart';
import '../text/mawzoon_text.dart';
import '../theme/theme_context.dart';
import 'volume_toggle.dart';

/// The floating order dock.
///
/// Three jobs, in one object that never leaves the screen: say what the plate
/// currently is, let the portion change, and take the order. A guest tracking
/// macros should never scroll to find out what they are holding — the figure
/// moving under their thumb as they choose *is* the feedback loop the app is
/// built around.
///
/// It floats rather than spanning the full width: inset from the edges, fully
/// rounded, with its shadow cast upward. That reads as a control resting on
/// top of the page rather than a chrome bar the page ends at, and it lets the
/// carousel above scroll visibly beneath it.
///
/// The energy reading is framed, never judged. No cap, no colour that means
/// "too much", and the three readings the band produces share one register.
class MacroCapsule extends StatelessWidget {
  /// Creates the dock.
  const MacroCapsule({
    required this.summary,
    required this.onScaleChanged,
    required this.onCheckout,
    super.key,
    this.total,
    this.checkoutLabel,
    this.waitingLabel,
  });

  /// The live plate reading.
  final NutritionalSummary summary;

  /// Called when the volume switch is used.
  final ValueChanged<PortionScale> onScaleChanged;

  /// Called when a complete plate is sent to checkout.
  final VoidCallback onCheckout;

  /// What the plate costs, shown on the action once it is orderable.
  final Money? total;

  /// Overrides the checkout label.
  final String? checkoutLabel;

  /// Overrides the label shown while the plate is unfinished.
  final String? waitingLabel;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final bool ready = summary.isComplete;
    final MacroTargets targets = MacroTargets.forScale(summary.scale);

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: context.space.screenGutter,
        end: context.space.screenGutter,
        bottom: context.space.base + MediaQuery.paddingOf(context).bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.structure,
          borderRadius: BorderRadius.circular(context.space.radiusPlatter),
          border: Border.all(color: context.colors.hairline),
          boxShadow: context.elevation.dock,
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.all(context.space.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              VolumeToggle(scale: summary.scale, onChanged: onScaleChanged),
              SizedBox(height: context.space.base),
              ProteinProgressBar(summary: summary, targets: targets),
              SizedBox(height: context.space.base),
              Row(
                children: <Widget>[
                  Expanded(child: _Figures(summary: summary)),
                  SizedBox(width: context.space.snug),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: BalanceLockAction(
                      ready: ready,
                      total: total,
                      onPressed: onCheckout,
                      label: ready
                          ? (checkoutLabel ??
                              (language == AppLanguage.arabic
                                  ? 'إتمام الطلب'
                                  : 'Checkout'))
                          : (waitingLabel ??
                              (language == AppLanguage.arabic
                                  ? 'أكمل الأقسام'
                                  : 'Finish the plate')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A slim bar showing how far the plate has come toward its protein target.
///
/// A target, not a cap: the bar fills toward olive and stops there. Passing
/// the target does not turn it red, because eating more protein than the house
/// aims for is not a mistake a guest needs warning about.
class ProteinProgressBar extends StatelessWidget {
  /// Creates the progress bar.
  const ProteinProgressBar({
    required this.summary,
    required this.targets,
    super.key,
  });

  /// The live plate reading.
  final NutritionalSummary summary;

  /// What this portion is aiming at.
  final MacroTargets targets;

  /// Height of the track.
  static const double trackHeight = 5;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final double grams = summary.totalMacros.proteinGrams;
    final double progress = targets.proteinProgress(grams);
    final bool met = targets.meetsProtein(grams);
    final Color fill = met ? context.colors.olive : context.colors.protein;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            MawzoonText(
              targets.proteinCaption(grams).resolve(language),
              style: context.type.tagLabel,
              color: met ? context.colors.olive : context.colors.inkFaint,
            ),
            const Spacer(),
            Directionality(
              // "42 / 40 g" is a Latin expression and must not be reordered.
              textDirection: TextDirection.ltr,
              child: Text(
                '${grams.round()} / ${targets.proteinGrams.round()} g',
                style: context.type.macroUnit.copyWith(
                  color: met ? context.colors.olive : context.colors.inkSoft,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: context.space.tight + 1),
        ClipRRect(
          borderRadius: BorderRadius.circular(trackHeight),
          child: Stack(
            children: <Widget>[
              Container(height: trackHeight, color: context.colors.track),
              // Scaled horizontally rather than resized. Animating a width
              // re-runs layout every frame; a Transform is paint-only, and
              // anchoring it to the start edge keeps it filling the correct
              // way round under RTL.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double value, Widget? child) =>
                    Transform.scale(
                  scaleX: value.clamp(0.0, 1.0),
                  alignment: AlignmentDirectional.centerStart
                      .resolve(Directionality.of(context)),
                  child: child,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  height: trackHeight,
                  width: double.infinity,
                  color: fill,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.summary});

  final NutritionalSummary summary;

  @override
  Widget build(BuildContext context) {
    // One isolated Latin run, and scaled down rather than clipped when the
    // dock is tight: a calorie figure cut in half is worse than a smaller one.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  '${summary.displayKilocalories}',
                  style: context.type.macroFigure
                      .copyWith(color: context.colors.ink),
                ),
                const SizedBox(width: 4),
                Text(
                  'kcal',
                  style: context.type.macroUnit
                      .copyWith(color: context.colors.inkFaint),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'C${summary.displayCarbohydrateGrams}  '
              'F${summary.displayFatGrams}  '
              'GL${summary.glycemic.displayLoad}',
              style:
                  context.type.macroUnit.copyWith(color: context.colors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// The primary action, and the visible half of the balance lock.
///
/// While the plate is unfinished the action is present but inert — a control
/// that vanishes and reappears moves everything beside it and the guest loses
/// the place their thumb was already heading for.
///
/// On completion it springs into Roasted Ember and grows an olive badge. The
/// spring is a scale overshoot, not a colour flash: the eye reads a size
/// change as the object arriving, where a flash reads as an alert.
class BalanceLockAction extends StatefulWidget {
  /// Creates the action.
  const BalanceLockAction({
    required this.ready,
    required this.onPressed,
    required this.label,
    super.key,
    this.total,
  });

  /// Whether the plate is complete and orderable.
  final bool ready;

  /// Called on tap, only when [ready].
  final VoidCallback onPressed;

  /// The label.
  final String label;

  /// What the plate costs, shown once the action is live.
  final Money? total;

  /// How far the action overshoots as it locks.
  static const double lockOvershoot = 1.06;

  @override
  State<BalanceLockAction> createState() => _BalanceLockActionState();
}

class _BalanceLockActionState extends State<BalanceLockAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  late final Animation<double> _spring = _lock.drive(
    Tween<double>(begin: 1, end: BalanceLockAction.lockOvershoot)
        .chain(CurveTween(curve: Curves.easeOutBack)),
  );

  @override
  void didUpdateWidget(BalanceLockAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fires on the crossing only. Swapping a component on an already-complete
    // plate must not spend the milestone again.
    if (widget.ready && !oldWidget.ready) {
      _lock.forward(from: 0).then((_) {
        if (mounted) _lock.reverse();
      });
    } else if (!widget.ready && oldWidget.ready) {
      _lock.value = 0;
    }
  }

  @override
  void dispose() {
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;

    return AnimatedBuilder(
      animation: _spring,
      builder: (BuildContext context, Widget? child) => Transform.scale(
        scale: _spring.value,
        child: child,
      ),
      child: PressableScale(
        onPressed: widget.ready ? widget.onPressed : null,
        enabled: widget.ready,
        semanticLabel: widget.label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          constraints: BoxConstraints(minHeight: context.space.thumbTarget),
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: context.space.base,
            vertical: context.space.snug + 2,
          ),
          decoration: BoxDecoration(
            color: widget.ready
                ? context.colors.ember
                : context.colors.structureElevated,
            borderRadius: context.space.pillRadius,
            border: widget.ready
                ? null
                : Border.all(color: context.colors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.ready) ...<Widget>[
                const BalanceBadge(),
                SizedBox(width: context.space.snug),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MawzoonText(
                      widget.label,
                      style: context.type.buttonLabel,
                      color: widget.ready
                          ? context.colors.onEmber
                          : context.colors.inkFaint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.ready && widget.total != null)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          widget.total!.format(language),
                          style: context.type.macroUnit.copyWith(
                            color: context.colors.onEmber
                                .withValues(alpha: 0.78),
                          ),
                        ),
                      ),
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

/// The olive mark that appears when the plate balances.
///
/// Cold-Pressed Olive is the brand's equilibrium colour, and it carries a
/// check rather than only a colour — a badge that means something only to
/// people who can distinguish olive from ember means nothing to the rest.
class BalanceBadge extends StatelessWidget {
  /// Creates the badge.
  const BalanceBadge({super.key, this.size = 20});

  /// Edge length of the badge.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.olive,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.check_rounded,
          size: size * 0.66,
          color: context.colors.onOlive,
        ),
      ),
    );
  }
}
