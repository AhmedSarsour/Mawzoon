import 'package:flutter/material.dart';

import '../../core/localization/localized_text.dart';
import '../../core/nutrition/nutritional_summary.dart';
import '../../core/nutrition/portion_scale.dart';
import '../interaction/pressable_scale.dart';
import '../text/mawzoon_text.dart';
import '../theme/theme_context.dart';
import 'volume_toggle.dart';

/// The persistent dock: the plate's numbers, the volume switch, and checkout.
///
/// Always visible and never covering the plate. A guest tracking macros should
/// never have to scroll to find out what they are currently holding — the
/// figure updating under their thumb as they choose *is* the feedback loop the
/// whole app is built around.
///
/// The energy reading is framed, never judged. There is no cap, no colour that
/// means "too much", and the three readings the band produces are written in
/// the same neutral register.
class MacroCapsule extends StatelessWidget {
  /// Creates the dock.
  const MacroCapsule({
    required this.summary,
    required this.onScaleChanged,
    required this.onCheckout,
    super.key,
    this.checkoutLabel,
    this.waitingLabel,
  });

  /// The live plate reading.
  final NutritionalSummary summary;

  /// Called when the volume switch is used.
  final ValueChanged<PortionScale> onScaleChanged;

  /// Called when a complete plate is sent to the cart.
  final VoidCallback onCheckout;

  /// Overrides the checkout label.
  final String? checkoutLabel;

  /// Overrides the label shown while the plate is unfinished.
  final String? waitingLabel;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final bool ready = summary.isComplete;

    return Container(
      padding: EdgeInsetsDirectional.only(
        start: context.space.screenGutter,
        end: context.space.screenGutter,
        top: context.space.base,
        // The dock sits on the bottom edge, so it owns the home-indicator
        // inset rather than leaving a stripe of canvas under itself.
        bottom: context.space.dockPadding + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: context.colors.canvas,
        border: Border(
          top: BorderSide(color: context.colors.hairline),
        ),
        boxShadow: context.elevation.dock,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          VolumeToggle(scale: summary.scale, onChanged: onScaleChanged),
          SizedBox(height: context.space.base),
          Row(
            children: <Widget>[
              Expanded(child: _Figures(summary: summary)),
              SizedBox(width: context.space.base),
              // Capped so a long translated label cannot starve the figures,
              // which are the reason the dock exists.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 176),
                child: _CheckoutAction(
                ready: ready,
                onPressed: onCheckout,
                label: ready
                    ? (checkoutLabel ??
                        (language == AppLanguage.arabic
                            ? 'أضف إلى السلة'
                            : 'Add to cart'))
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
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.summary});

  final NutritionalSummary summary;

  @override
  Widget build(BuildContext context) {
    // The whole numeric block is one isolated LTR run. Arabic reads
    // right-to-left, but "412 kcal · P54 C34 F9" is a Latin expression and
    // must not be reordered by the bidi algorithm.
    // Scaled down rather than clipped when the dock is tight: a calorie
    // figure that has been cut in half is worse than a slightly smaller one.
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
                style: context.type.macroFigure.copyWith(
                  color: context.colors.ink,
                ),
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
            'P${summary.displayProteinGrams}  '
            'C${summary.displayCarbohydrateGrams}  '
            'F${summary.displayFatGrams}  '
            'GL${summary.glycemic.displayLoad}',
            style: context.type.macroUnit
                .copyWith(color: context.colors.inkSoft),
          ),
        ],
        ),
      ),
    );
  }
}

class _CheckoutAction extends StatelessWidget {
  const _CheckoutAction({
    required this.ready,
    required this.onPressed,
    required this.label,
  });

  final bool ready;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      // An unfinished plate makes the action inert rather than absent. A
      // control that vanishes and reappears moves everything beside it, and
      // the guest loses the place their thumb was already heading for.
      onPressed: ready ? onPressed : null,
      enabled: ready,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        constraints: BoxConstraints(minHeight: context.space.thumbTarget),
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.loose,
          vertical: context.space.base,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ready ? context.colors.ember : context.colors.structure,
          borderRadius: context.space.pillRadius,
          border: ready ? null : Border.all(color: context.colors.hairline),
        ),
        child: MawzoonText(
          label,
          style: context.type.buttonLabel,
          color: ready ? context.colors.onEmber : context.colors.inkFaint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
