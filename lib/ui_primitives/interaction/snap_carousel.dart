import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'haptics.dart';

/// Scroll physics that settle on an item boundary.
///
/// A free-scrolling row of choices always stops halfway through one, which
/// leaves the guest looking at two half-cards and deciding which one the app
/// meant. Snapping removes that question. The magnetism also gives the row a
/// detent the thumb can feel, which is what the selection tick is reinforcing.
class SnapScrollPhysics extends ScrollPhysics {
  /// Creates physics that snap every [itemExtent] logical pixels.
  const SnapScrollPhysics({required this.itemExtent, super.parent})
      : assert(itemExtent > 0, 'itemExtent must be positive');

  /// The pitch of the row: item width plus the gap after it.
  final double itemExtent;

  @override
  SnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      SnapScrollPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));

  double _snapTarget(ScrollMetrics position, double velocity) {
    // Let a decisive flick carry to the next item rather than fighting it.
    final double raw = position.pixels + velocity * 0.12;
    final double index = (raw / itemExtent).roundToDouble();
    return (index * itemExtent)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // At the ends, defer to the parent so the overscroll glow and bounce stay
    // native to the platform.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final double target = _snapTarget(position, velocity);
    if ((target - position.pixels).abs() < toleranceFor(position).distance) {
      return null;
    }

    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// A horizontal row of choices with magnetic snapping and a selection tick.
///
/// The tick fires as the centred item *changes*, not on every scroll frame:
/// the guest feels the row click past each candidate, the way a well-made
/// dial does. That is the cue the brief calls for while scrolling; committing
/// a choice is a heavier cue, emitted by the domain rather than here, so the
/// two never collapse into one buzz.
class SnapCarousel extends StatefulWidget {
  /// Creates a snapping row of [itemCount] items.
  const SnapCarousel({
    required this.itemCount,
    required this.itemBuilder,
    required this.itemExtent,
    required this.height,
    super.key,
    this.gutter = 16,
    this.gap = 8,
    this.controller,
    this.onCentredItemChanged,
    this.tickOnScroll = true,
  });

  /// How many items the row holds.
  final int itemCount;

  /// Builds item [index].
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Width of one item, excluding [gap].
  final double itemExtent;

  /// Height of the row.
  final double height;

  /// Padding at both ends, so the first and last items clear the screen edge.
  final double gutter;

  /// Space between items.
  final double gap;

  /// An optional external controller.
  final ScrollController? controller;

  /// Called when the centred item changes.
  final ValueChanged<int>? onCentredItemChanged;

  /// Whether to tick as the centred item changes.
  final bool tickOnScroll;

  @override
  State<SnapCarousel> createState() => _SnapCarouselState();
}

class _SnapCarouselState extends State<SnapCarousel> {
  late final ScrollController _controller =
      widget.controller ?? ScrollController();
  bool _ownsController = false;
  int _centred = 0;

  double get _pitch => widget.itemExtent + widget.gap;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final int next = (_controller.offset / _pitch)
        .round()
        .clamp(0, math.max(0, widget.itemCount - 1));
    if (next == _centred) return;
    _centred = next;
    if (widget.tickOnScroll) MawzoonHaptics.selection();
    widget.onCentredItemChanged?.call(next);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: SnapScrollPhysics(
          itemExtent: _pitch,
          parent: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
        ),
        padding: EdgeInsetsDirectional.symmetric(horizontal: widget.gutter),
        itemCount: widget.itemCount,
        separatorBuilder: (_, __) => SizedBox(width: widget.gap),
        itemBuilder: (BuildContext context, int index) => SizedBox(
          width: widget.itemExtent,
          child: widget.itemBuilder(context, index),
        ),
      ),
    );
  }
}
