import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/menu/plate_segment.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../ui_primitives/controls/macro_capsule.dart';
import '../../../ui_primitives/interaction/haptics.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/plate/tri_partition_plate.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../../../ui_primitives/theme/theme_mode_scope.dart';
import '../../cart_checkout/domain/delivery_address.dart';
import '../../cart_checkout/domain/order_draft.dart';
import '../../cart_checkout/presentation/checkout_sheet.dart';
import '../../cart_checkout/domain/guest_phone.dart';
import '../../cart_checkout/domain/order_placement.dart';
import '../../cart_checkout/presentation/order_gateway_scope.dart';
import '../../curated_menu/domain/signature_plate.dart';
import '../../curated_menu/presentation/curated_track.dart';
import '../../mindful_satiety/application/reflection_controller.dart';
import '../../order_tracking/domain/tracked_order.dart';
import '../../order_tracking/presentation/order_status_screen.dart';
import '../../mindful_satiety/domain/reflection_journal.dart';
import '../../mindful_satiety/domain/satiety_insight.dart';
import '../../mindful_satiety/presentation/reflection_sheet.dart';
import '../../mindful_satiety/presentation/reflection_surfaces.dart';
import '../../plate_builder/application/plate_builder_controller.dart';
import '../../plate_builder/domain/plate_builder_event.dart';
import '../../plate_builder/domain/plate_builder_state.dart';
import '../../plate_builder/domain/plate_selection.dart';
import '../../plate_builder/presentation/plate_architect_track.dart';
import 'component_images.dart';

/// Which way the guest is ordering.
enum OrderTrack {
  /// Chef's plates, one tap.
  curated(
    label: LocalizedText(ar: 'أطباق الشيف', en: "Chef's plates"),
    hint: LocalizedText(ar: 'نقرة واحدة', en: 'One tap'),
  ),

  /// Build it yourself, three steps.
  architect(
    label: LocalizedText(ar: 'ابنِ طبقك', en: 'Build your plate'),
    hint: LocalizedText(ar: 'ثلاث خطوات', en: 'Three steps'),
  );

  const OrderTrack({required this.label, required this.hint});

  /// The track's name.
  final LocalizedText label;

  /// A few words on what it costs the guest.
  final LocalizedText hint;
}

/// The primary ordering screen.
///
/// ## Two tracks, one thumb zone
///
/// A hungry guest and a deliberate one want different things, so the screen
/// offers both — but only one at a time in the reachable half of the display.
/// Showing both at once would mean one of them sits under the thumb and the
/// other sits where nobody reaches, which is a worse answer than choosing.
///
/// The plate stays put across the switch. It is the thing being built either
/// way, so it must not move when the guest changes their mind about how to
/// build it.
///
/// ## Layout contract
///
/// Everything interactive sits in the bottom [thumbZoneFraction] of the
/// screen: the track switch, the carousels and the dock. The plate occupies
/// the top, where it is seen rather than touched. This is enforced by the
/// layout and asserted by test, because "put it in the thumb zone" is the kind
/// of intention that quietly stops being true the first time a row is added.
class OrderHomeScreen extends StatefulWidget {
  /// Creates the ordering screen.
  const OrderHomeScreen({
    super.key,
    this.controller,
    this.initialTrack = OrderTrack.curated,
  });

  /// The share of the screen reserved for reachable controls.
  ///
  /// Measured from the bottom. On a phone held one-handed the thumb sweeps a
  /// rough arc over the lower half; anything above it takes a second hand or a
  /// grip shift, and a grip shift is where an order gets abandoned. Raised
  /// from 0.5 to 0.62 for the tall chef cards (K4): they need the room, and
  /// the track switch — the only control that lands near the top of the
  /// reach arc — is the least-used control on the screen.
  static const double thumbZoneFraction = 0.62;

  /// An externally owned controller, for tests or a restored order.
  final PlateBuilderController? controller;

  /// Which track opens first. Curated by default: the fast path is the
  /// default path.
  final OrderTrack initialTrack;

  @override
  State<OrderHomeScreen> createState() => _OrderHomeScreenState();
}

class _OrderHomeScreenState extends State<OrderHomeScreen> {
  late final PlateBuilderController _controller =
      widget.controller ?? PlateBuilderController();
  late final bool _ownsController = widget.controller == null;
  late OrderTrack _track = widget.initialTrack;
  StreamSubscription<PlateBuilderEvent>? _events;
  String? _curatedPlateId;

  @override
  void initState() {
    super.initState();
    // The one subscription that turns domain intent into device feedback.
    _events = _controller.events.listen(MawzoonHaptics.forEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeOpenOrder());
  }

  /// Reopening the app with an order still open lands on that order, not the
  /// menu (A5). Once per launch; the guest can back out to the menu.
  Future<void> _resumeOpenOrder() async {
    final OrderTracker? tracker = OrderGatewayScope.maybeOf(context)?.tracker;
    if (tracker == null) return;
    final TrackedOrder? open = await tracker.openOrder();
    if (open == null || !mounted) return;
    _showOrder(open.id, initial: open, tracker: tracker);
  }

  void _showOrder(String id, {TrackedOrder? initial, OrderTracker? tracker}) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => OrderStatusScreen(
            orderId: id,
            initial: initial,
            tracker: tracker,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _switchTrack(OrderTrack track) {
    if (_track == track) return;
    setState(() => _track = track);
  }

  /// Opens checkout, and confirms once the kitchen has the order.
  ///
  /// The sheet only closes on the kitchen's yes, so the number shown here is
  /// the one called out at the pass.
  Future<void> _openCheckout() async {
    final OrderGatewayScope? scope = OrderGatewayScope.maybeOf(context);
    final PhoneMemory? phones = scope?.phoneMemory;
    final String? phone = await phones?.read();
    if (!mounted) return;
    final CheckoutResult? result = await showCheckoutSheet(
      context,
      selection: _controller.selection,
      phone: phone,
    );
    if (result == null || !mounted) return;
    final String? openId = result.openOrderId;
    if (openId != null) {
      // Refused: one unpaid order at a time. Show that one; keep the plate.
      _showOrder(openId, tracker: scope?.tracker);
      return;
    }
    final OrderDraft placed = result.draft;
    final String? usedPhone = placed.phone;
    if (result.placed != null && usedPhone != null && usedPhone != phone) {
      unawaited(phones?.write(usedPhone));
    }
    final OrderPlaced? order = result.placed;

    MawzoonHaptics.medium();
    final AppLanguage language = context.appLanguage;
    unawaited(
      ReflectionScope.maybeOf(context)?.orderPlaced(placed, language: language),
    );
    if (order != null) {
      // Not the old "received" snackbar: an unpaid order is not with the
      // kitchen yet, and the receipt says so and shows when it expires.
      _showOrder(
        order.orderId,
        tracker: scope?.tracker,
        initial: TrackedOrder(
          id: order.orderId,
          number: order.orderNumber,
          stage: order.awaitingPayment
              ? OrderStage.awaitingPayment
              : OrderStage.paid,
          total: order.total,
          dueAt: order.paymentDueAt,
          isDelivery: placed.mode == FulfilmentMode.delivery,
        ),
      );
    } else {
      // No gateway (demo/preview): confirmed locally.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: MawzoonText(
            language == AppLanguage.arabic
                ? 'تم استلام طلبك · ${placed.mode.estimate.resolve(language)}'
                : 'Order in · ${placed.mode.estimate.resolve(language)}',
            style: context.type.capsuleLabel,
            color: context.colors.ink,
          ),
        ),
      );
    }
    _controller.reset();
    setState(() => _curatedPlateId = null);
  }

  bool _reflectionOpen = false;

  /// Opens the post-meal question. Guarded so a notification tap and a card
  /// tap in the same frame can't stack two sheets.
  Future<void> _openReflection(ReflectionController reflections) async {
    final PendingReflection? pending = reflections.askable;
    reflections.consumeSheetRequest();
    if (pending == null || _reflectionOpen) return;
    _reflectionOpen = true;
    await showReflectionSheet(
      context,
      pending: pending,
      onAnswered: reflections.answer,
      onSkipped: reflections.skip,
    );
    _reflectionOpen = false;
  }

  void _chooseCurated(SignaturePlate plate) {
    setState(() => _curatedPlateId = plate.id);
    _controller.replaceSelection(plate.selectionAt(_controller.scale));
    MawzoonHaptics.light();
  }

  @override
  Widget build(BuildContext context) {
    final ReflectionController? reflections = ReflectionScope.maybeOf(context);
    if (reflections != null && reflections.sheetRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openReflection(reflections));
      });
    }
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<PlateBuilderState>(
          valueListenable: _controller,
          builder: (BuildContext context, PlateBuilderState state, _) {
            final NutritionalSummary summary = state.macros;
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // Floor: the plate never drops below 150pt, even if the
                // thumb zone's own content (reflection card + dock) grows
                // past its usual size on a future change.
                const double minPlateHeight = 150;
                final double thumbZone = math.min(
                  constraints.maxHeight * OrderHomeScreen.thumbZoneFraction,
                  constraints.maxHeight - minPlateHeight,
                );
                return Column(
                  children: <Widget>[
                    if (reflections?.askable != null)
                      Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          context.space.screenGutter,
                          context.space.snug,
                          context.space.screenGutter,
                          0,
                        ),
                        child: ReflectionCard(
                          onOpen: () => _openReflection(reflections!),
                        ),
                      ),
                    // ---- seen, not touched ----
                    Expanded(
                      child: _PlateStage(
                        summary: summary,
                        selection: state.selection,
                      ),
                    ),
                    // ---- reached ----
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: thumbZone),
                      child: _ThumbZone(
                        track: _track,
                        onTrackChanged: _switchTrack,
                        controller: _controller,
                        summary: summary,
                        state: state,
                        curatedPlateId: _curatedPlateId,
                        onCuratedChosen: _chooseCurated,
                        onArchitectTouched: () =>
                            setState(() => _curatedPlateId = null),
                        onCheckout: _openCheckout,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The upper half: wordmark, plate, and how the plate reads.
class _PlateStage extends StatelessWidget {
  const _PlateStage({required this.summary, required this.selection});

  final NutritionalSummary summary;
  final PlateSelection selection;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    // Side view: the platter tips back to show its rim and body once food is
    // on it. Motion spent on the peak moment (a compartment filling), not idle.
    final bool hasFood = summary.remainingSegmentCount < 3;
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: context.space.screenGutter,
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              MawzoonText('موزون', style: context.type.wordmark),
              const Spacer(),
              Flexible(child: _Verdict(summary: summary, language: language)),
              const _ThemeToggle(),
            ],
          ),
          // The plate takes the height left, bottom-aligned so it sits right
          // above the track switch; when a reflection card squeezes the stage
          // it scales down rather than overflowing.
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) => FittedBox(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: box.maxWidth,
                  child: TweenAnimationBuilder<double>(
                    tween:
                        Tween<double>(end: hasFood ? _tiltFilled : _tiltEmpty),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder:
                        (BuildContext context, double tilt, Widget? plate) =>
                            Transform(
                      alignment: Alignment.center,
                      // Entry (3,2) is perspective: the far edge shrinks, which is
                      // what reads as depth instead of a flat sticker being rotated.
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0018)
                        ..rotateX(tilt),
                      child: plate,
                    ),
                    child: TriPartitionPlate(
                      summary: summary,
                      aspectRatio: 2.0,
                      bodyDepth: _plateBodyDepth,
                      componentImages: componentImagesFor(
                        selection,
                        decodeWidth:
                            (300 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: context.space.base),
        ],
      ),
    );
  }

  /// Tilt, in radians, of the platter with nothing on it / with food on it.
  static const double _tiltEmpty = 0.16;
  static const double _tiltFilled = 0.62;

  /// Thickness of the platter's body, in logical pixels.
  static const double _plateBodyDepth = 20;
}

/// Light/dark switch. Hidden when the app gives no [ThemeModeScope].
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final ThemeModeScope? scope = ThemeModeScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final bool ar = context.appLanguage == AppLanguage.arabic;
    return IconButton(
      onPressed: () {
        MawzoonHaptics.light();
        scope.onChanged(dark ? ThemeMode.light : ThemeMode.dark);
      },
      tooltip: dark
          ? (ar ? 'الوضع الفاتح' : 'Light mode')
          : (ar ? 'الوضع الداكن' : 'Dark mode'),
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 22,
        color: context.colors.inkSoft,
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.summary, required this.language});

  final NutritionalSummary summary;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (!summary.isComplete) {
      final int remaining = summary.remainingSegmentCount;
      return MawzoonText(
        language == AppLanguage.arabic
            ? (remaining == 1 ? 'بقي قسم واحد' : 'بقي $remaining أقسام')
            : (remaining == 1 ? 'One to go' : '$remaining to go'),
        style: context.type.caption,
        color: context.colors.inkFaint,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.olive,
          ),
        ),
        SizedBox(width: context.space.tight + 1),
        MawzoonText(
          summary.framing.headline.resolve(language),
          style: context.type.capsuleLabel,
          color: context.colors.olive,
        ),
      ],
    );
  }
}

/// The lower half: everything a thumb has to reach.
class _ThumbZone extends StatelessWidget {
  const _ThumbZone({
    required this.track,
    required this.onTrackChanged,
    required this.controller,
    required this.summary,
    required this.state,
    required this.curatedPlateId,
    required this.onCuratedChosen,
    required this.onArchitectTouched,
    required this.onCheckout,
  });

  final OrderTrack track;
  final ValueChanged<OrderTrack> onTrackChanged;
  final PlateBuilderController controller;
  final NutritionalSummary summary;
  final PlateBuilderState state;
  final String? curatedPlateId;
  final ValueChanged<SignaturePlate> onCuratedChosen;
  final VoidCallback onArchitectTouched;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: context.space.screenGutter,
            end: context.space.screenGutter,
            bottom: context.space.base,
          ),
          child: _TrackSwitch(track: track, onChanged: onTrackChanged),
        ),
        Flexible(
          child: switch (track) {
            // The carousel fits the height it is given rather than scrolling:
            // a card whose text hides behind the dock is worse than a
            // slightly shorter card.
            OrderTrack.curated => CuratedTrack(
                scale: summary.scale,
                selectedPlateId: curatedPlateId,
                onPlateChosen: onCuratedChosen,
              ),
            OrderTrack.architect => SingleChildScrollView(
                child: PlateArchitectTrack(
                  selection: state.selection,
                  onOptionChosen: (option) {
                    onArchitectTouched();
                    controller.select(option);
                  },
                  onOptionCleared: (PlateSegment segment) {
                    onArchitectTouched();
                    controller.clearSegment(segment);
                  },
                ),
              ),
          },
        ),
        SizedBox(height: context.space.base),
        _Insight(controller: controller, summary: summary),
        MacroCapsule(
          summary: summary,
          total: summary.isComplete
              ? PriceBreakdown.forPlate(
                  selection: state.selection,
                  // The price checkout opens on, so the two never disagree.
                  mode: defaultFulfilment,
                ).total
              : null,
          onScaleChanged: controller.setScale,
          onCheckout: onCheckout,
        ),
      ],
    );
  }
}

class _TrackSwitch extends StatelessWidget {
  const _TrackSwitch({required this.track, required this.onChanged});

  /// Share of the available width the capsule occupies.
  static const double widthFraction = 0.72;

  /// The narrowest it goes before it stops being narrower: two labels have
  /// to fit side by side.
  static const double minWidth = 260;

  final OrderTrack track;
  final ValueChanged<OrderTrack> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final int index = OrderTrack.values.indexOf(track);

    // Two equal halves rather than intrinsically-sized pills: the labels are
    // translated, and "Build your plate · Three steps" does not fit beside
    // "Chef's plates" on a 390pt phone at any font the brand actually uses.
    //
    // Narrower than the screen (reference A: ~3/4 of the width, centred):
    // a full-bleed bar reads as a nav bar, a capsule with air around it
    // reads as a choice. The floor keeps both labels legible on small phones.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = math.max(
          constraints.maxWidth * _TrackSwitch.widthFraction,
          math.min(constraints.maxWidth, _TrackSwitch.minWidth),
        );
        return Center(
          child: SizedBox(
            width: width,
            child: _buildTrack(context, language, reducedMotion, index),
          ),
        );
      },
    );
  }

  Widget _buildTrack(
    BuildContext context,
    AppLanguage language,
    bool reducedMotion,
    int index,
  ) {
    return Container(
      padding: EdgeInsetsDirectional.all(context.space.micro),
      decoration: BoxDecoration(
        color: context.colors.track,
        borderRadius: context.space.pillRadius,
      ),
      child: Stack(
        children: <Widget>[
          // One porcelain pill, not per-cell decoration: which half is
          // selected is the position of a single physical object, not two
          // cells independently redrawing themselves.
          Positioned.fill(
            child: AnimatedAlign(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: AlignmentDirectional(
                // -1 (first half) .. 1 (second half), evenly spaced by
                // track count — mirrors for free under RTL because this is
                // *Directional*, not a raw left/right Alignment.
                -1 + 2 * index / (OrderTrack.values.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / OrderTrack.values.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.olive,
                    borderRadius: context.space.pillRadius,
                    boxShadow: context.elevation.resting,
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              for (final OrderTrack option in OrderTrack.values)
                Expanded(
                  child: TactileFeedbackWell(
                    onPressed: () => onChanged(option),
                    selected: option == track,
                    semanticLabel: option.label.resolve(language),
                    child: Padding(
                      padding: EdgeInsetsDirectional.symmetric(
                        horizontal: context.space.base,
                        vertical: context.space.snug,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          MawzoonText(
                            option.label.resolve(language),
                            style: context.type.capsuleLabel.copyWith(
                              fontWeight:
                                  option == track ? FontWeight.w700 : null,
                            ),
                            color: option == track
                                ? context.colors.onOlive
                                : context.colors.inkFaint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          MawzoonText(
                            option.hint.resolve(language),
                            style: context.type.tagLabel,
                            color: option == track
                                ? context.colors.onOlive.withValues(alpha: 0.85)
                                : context.colors.inkFaint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one suggestion the guest's own answers make about this plate, if any.
/// Shows the first only: one message at a time.
class _Insight extends StatelessWidget {
  const _Insight({required this.controller, required this.summary});

  final PlateBuilderController controller;
  final NutritionalSummary summary;

  @override
  Widget build(BuildContext context) {
    final ReflectionController? reflections = ReflectionScope.maybeOf(context);
    if (reflections == null) return const SizedBox.shrink();
    final List<SatietyInsight> insights = reflections.insightsFor(
      scale: summary.scale,
      balance: summary.isComplete ? summary.glycemic.balance : null,
    );
    if (insights.isEmpty) return const SizedBox.shrink();
    final SatietyInsight insight = insights.first;
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: context.space.screenGutter,
      ),
      child: InsightLine(
        insight: insight,
        onApplyScale: controller.setScale,
        onDismiss: () => unawaited(reflections.dismiss(insight.kind)),
      ),
    );
  }
}
