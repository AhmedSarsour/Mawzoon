import 'dart:async';

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
import '../../cart_checkout/domain/delivery_address.dart';
import '../../cart_checkout/domain/order_draft.dart';
import '../../cart_checkout/presentation/checkout_sheet.dart';
import '../../curated_menu/domain/signature_plate.dart';
import '../../curated_menu/presentation/curated_track.dart';
import '../../mindful_satiety/application/reflection_controller.dart';
import '../../mindful_satiety/domain/reflection_journal.dart';
import '../../mindful_satiety/domain/satiety_insight.dart';
import '../../mindful_satiety/presentation/reflection_sheet.dart';
import '../../mindful_satiety/presentation/reflection_surfaces.dart';
import '../../plate_builder/application/plate_builder_controller.dart';
import '../../plate_builder/domain/plate_builder_event.dart';
import '../../plate_builder/domain/plate_builder_state.dart';
import '../../plate_builder/presentation/plate_architect_track.dart';

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
  /// grip shift, and a grip shift is where an order gets abandoned.
  static const double thumbZoneFraction = 0.5;

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

  /// Opens checkout, and reports back when an order is placed.
  ///
  /// The screen does not know what placing an order means yet — there is no
  /// backend — so it confirms and clears. Everything the confirmation needs is
  /// already in the returned draft.
  Future<void> _openCheckout() async {
    final OrderDraft? placed = await showCheckoutSheet(
      context,
      selection: _controller.selection,
    );
    if (placed == null || !mounted) return;

    MawzoonHaptics.medium();
    final AppLanguage language = context.appLanguage;
    unawaited(
      ReflectionScope.maybeOf(context)?.orderPlaced(placed, language: language),
    );
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
                final double thumbZone =
                    constraints.maxHeight * OrderHomeScreen.thumbZoneFraction;
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
                      child: _PlateStage(summary: summary),
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
  const _PlateStage({required this.summary});

  final NutritionalSummary summary;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: context.space.screenGutter,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              MawzoonText('موزون', style: context.type.wordmark),
              const Spacer(),
              Flexible(child: _Verdict(summary: summary, language: language)),
            ],
          ),
          const Spacer(),
          TriPartitionPlate(summary: summary),
          const Spacer(),
        ],
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
          child: SingleChildScrollView(
            child: switch (track) {
              OrderTrack.curated => CuratedTrack(
                  scale: summary.scale,
                  selectedPlateId: curatedPlateId,
                  onPlateChosen: onCuratedChosen,
                ),
              OrderTrack.architect => PlateArchitectTrack(
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
            },
          ),
        ),
        SizedBox(height: context.space.base),
        _Insight(controller: controller, summary: summary),
        MacroCapsule(
          summary: summary,
          total: summary.isComplete
              ? PriceBreakdown.forPlate(
                  selection: state.selection,
                  mode: FulfilmentMode.delivery,
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

  final OrderTrack track;
  final ValueChanged<OrderTrack> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    // Two equal halves rather than intrinsically-sized pills: the labels are
    // translated, and "Build your plate · Three steps" does not fit beside
    // "Chef's plates" on a 390pt phone at any font the brand actually uses.
    return Row(
      children: <Widget>[
        for (final OrderTrack option in OrderTrack.values)
          Expanded(
            child: Padding(
            padding: EdgeInsetsDirectional.only(end: context.space.snug),
            child: TactileFeedbackWell(
              onPressed: () => onChanged(option),
              selected: option == track,
              semanticLabel: option.label.resolve(language),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: context.space.base,
                  vertical: context.space.snug,
                ),
                decoration: BoxDecoration(
                  color: option == track
                      ? context.colors.structureElevated
                      : Colors.transparent,
                  borderRadius: context.space.pillRadius,
                  border: Border.all(
                    color: option == track
                        ? context.colors.hairline
                        : Colors.transparent,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    MawzoonText(
                      option.label.resolve(language),
                      style: context.type.capsuleLabel,
                      color: option == track
                          ? context.colors.ink
                          : context.colors.inkFaint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    MawzoonText(
                      option.hint.resolve(language),
                      style: context.type.tagLabel,
                      color: context.colors.inkFaint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
      ],
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
