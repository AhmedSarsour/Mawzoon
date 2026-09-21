import 'package:flutter/material.dart';

import 'motion_tokens.dart';
import 'spring_motion.dart';

/// Opens [child] in a sheet that expands and dismisses on the house spring,
/// inheriting the velocity of the guest's drag.
///
/// Returns whatever the sheet pops with, or `null` if it was dismissed.
Future<T?> showSpringSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return Navigator.of(context).push<T>(
    _SpringSheetRoute<T>(builder: builder, dismissible: dismissible),
  );
}

class _SpringSheetRoute<T> extends PopupRoute<T> {
  _SpringSheetRoute({required this.builder, required this.dismissible});

  final WidgetBuilder builder;
  final bool dismissible;

  @override
  Color? get barrierColor => const Color(0x99000000);

  @override
  bool get barrierDismissible => dismissible;

  @override
  String get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => MawzoonMotion.structuralSettle;

  @override
  Duration get reverseTransitionDuration => MawzoonMotion.tactileRelease;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      SpringSheet(
        animation: animation,
        onDismiss: () => Navigator.of(context).maybePop(),
        child: Builder(builder: builder),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// Tier 2 — a sheet whose expansion and dismissal are driven by a spring that
/// carries the gesture's velocity.
///
/// A sheet is the one place in the app where the guest is physically pushing
/// something, so it is the one place where inheriting velocity genuinely
/// matters. Release it slowly near the top and it settles open; flick it
/// downward from almost anywhere and it goes, because a decisive throw means
/// the guest has decided and arguing with them makes the gesture feel sticky.
///
/// The drag moves a [Transform], never a layout offset, so a sheet being
/// dragged does not re-run layout on the content inside it.
class SpringSheet extends StatefulWidget {
  /// Creates a draggable spring sheet.
  const SpringSheet({
    required this.animation,
    required this.child,
    required this.onDismiss,
    super.key,
  });

  /// The route's animation, which this widget drives directly.
  final Animation<double> animation;

  /// The sheet's contents.
  final Widget child;

  /// Called when the sheet has travelled far enough to be dismissed.
  final VoidCallback onDismiss;

  @override
  State<SpringSheet> createState() => _SpringSheetState();
}

class _SpringSheetState extends State<SpringSheet> {
  double _extent = 1;
  bool _dragging = false;

  AnimationController? get _controller {
    final Animation<double> animation = widget.animation;
    return animation is AnimationController ? animation : null;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final AnimationController? controller = _controller;
    if (controller == null || _extent <= 0) return;
    _dragging = true;
    controller.value -= details.primaryDelta! / _extent;
  }

  void _onDragEnd(DragEndDetails details) {
    final AnimationController? controller = _controller;
    if (controller == null || !_dragging) return;
    _dragging = false;

    final double velocity = details.primaryVelocity ?? 0;
    final double target = SpringDrive.restingTarget(
      position: controller.value,
      velocity: velocity,
    );

    // The gesture's own speed becomes the spring's initial velocity, so the
    // sheet keeps travelling at the speed the thumb left it at.
    SpringDrive.release(
      controller,
      target: target,
      // Downward drag is positive velocity but decreasing controller value.
      velocity: -velocity,
      extent: _extent,
    ).whenCompleteOrCancel(() {
      if (!mounted) return;
      if (controller.value <= 0.001) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _extent = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onVerticalDragUpdate: reduced ? null : _onDragUpdate,
          onVerticalDragEnd: reduced ? null : _onDragEnd,
          child: AnimatedBuilder(
            animation: widget.animation,
            builder: (BuildContext context, Widget? child) => Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                // Paint-only: the sheet slides without its contents relaying
                // out on every frame of the drag.
                offset: Offset(
                  0,
                  (1 - widget.animation.value) * _extent,
                ),
                child: child,
              ),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}
