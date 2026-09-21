import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/feedback/haptic_cue.dart';
import '../core/localization/localized_text.dart';
import '../core/menu/ingredient_option.dart';
import '../core/menu/mawzoon_catalog.dart';
import '../core/menu/plate_segment.dart';
import '../core/nutrition/nutritional_summary.dart';
import '../core/nutrition/portion_scale.dart';
import '../features/plate_builder/application/plate_builder_controller.dart';
import '../features/plate_builder/domain/plate_builder_event.dart';
import '../features/plate_builder/domain/plate_builder_state.dart';
import '../ui_primitives/plate/tri_partition_plate.dart';
import '../ui_primitives/text/mawzoon_text.dart';
import '../ui_primitives/theme/theme.dart';

/// A workbench for inspecting the hero plate.
///
/// Not a product screen — the checkout dock, carousels and curated track are
/// still to come. This exists so the canvas can be driven by hand on a device:
/// fill and empty compartments, flip the portion, flip the language, and watch
/// the ring and the balance lock behave against real menu data.
class PlateWorkbenchApp extends StatefulWidget {
  /// Creates the workbench.
  const PlateWorkbenchApp({super.key});

  @override
  State<PlateWorkbenchApp> createState() => _PlateWorkbenchAppState();
}

class _PlateWorkbenchAppState extends State<PlateWorkbenchApp> {
  AppLanguage _language = AppLanguage.arabic;
  ThemeMode _themeMode = ThemeMode.dark;

  // Built once per language, not per frame: a fresh ThemeData on every build
  // would make AnimatedTheme lerp the whole tree constantly.
  late ThemeData _dark = AppTheme.dark(language: _language);
  late ThemeData _light = AppTheme.light(language: _language);

  void _setLanguage(AppLanguage language) {
    setState(() {
      _language = language;
      _dark = AppTheme.dark(language: language);
      _light = AppTheme.light(language: language);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mawzoon — Plate Workbench',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: _themeMode,
        locale: Locale(_language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: PlateWorkbench(
          language: _language,
          onLanguageChanged: _setLanguage,
          themeMode: _themeMode,
          onThemeModeChanged: (ThemeMode m) => setState(() => _themeMode = m),
        ),
      );
}

/// The workbench screen.
class PlateWorkbench extends StatefulWidget {
  /// Creates the workbench screen.
  const PlateWorkbench({
    required this.language,
    required this.onLanguageChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  /// The language in force.
  final AppLanguage language;

  /// Called when the language toggle is used.
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// The theme mode in force.
  final ThemeMode themeMode;

  /// Called when the theme toggle is used.
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<PlateWorkbench> createState() => _PlateWorkbenchState();
}

class _PlateWorkbenchState extends State<PlateWorkbench> {
  final PlateBuilderController _controller = PlateBuilderController();

  @override
  void initState() {
    super.initState();
    // The one place haptics are mapped from intent to platform, exactly as
    // HapticCue is documented to be used.
    _controller.events.listen((PlateBuilderEvent event) {
      switch (event.haptic) {
        case HapticCue.selection:
          HapticFeedback.selectionClick();
        case HapticCue.light:
          HapticFeedback.lightImpact();
        case HapticCue.medium:
          HapticFeedback.mediumImpact();
        case HapticCue.none:
          break;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _t(String ar, String en) => widget.language == AppLanguage.arabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    final MawzoonColors colors = context.colors;
    final MawzoonSpacing space = context.space;

    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<PlateBuilderState>(
          valueListenable: _controller,
          builder: (BuildContext context, PlateBuilderState state, _) {
            final NutritionalSummary summary = state.macros;
            return ListView(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: space.screenGutter,
              ),
              children: <Widget>[
                _header(context),
                SizedBox(height: space.base),

                // The module under inspection.
                TriPartitionPlate(summary: summary),

                SizedBox(height: space.base),
                _readout(context, state),
                SizedBox(height: space.loose),

                for (final PlateSegment segment in PlateSegment.buildOrder) ...<Widget>[
                  _segmentRail(context, segment),
                  SizedBox(height: space.snug),
                  _segmentTrack(context, segment, state),
                  SizedBox(height: space.base),
                ],

                SizedBox(height: space.snug),
                _scaleToggle(context, state),
                SizedBox(height: space.snug),
                OutlinedButton(
                  onPressed: _controller.reset,
                  child: MawzoonText(
                    _t('أفرغ الطبق', 'Empty the plate'),
                    style: context.type.buttonLabel,
                    color: colors.ink,
                  ),
                ),
                SizedBox(height: space.chapter),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final MawzoonTypography type = context.type;
    return Padding(
      padding: EdgeInsetsDirectional.only(top: context.space.base),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MawzoonText('موزون', style: type.wordmark),
                MawzoonText(
                  _t('ورشة الطبق', 'Plate workbench'),
                  style: type.eyebrow,
                  color: context.colors.inkFaint,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _t('الوضع', 'Theme'),
            onPressed: () => widget.onThemeModeChanged(
              widget.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
            ),
            icon: Icon(
              widget.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          TextButton(
            onPressed: () => widget.onLanguageChanged(
              widget.language == AppLanguage.arabic
                  ? AppLanguage.english
                  : AppLanguage.arabic,
            ),
            child: Text(widget.language == AppLanguage.arabic ? 'EN' : 'ع'),
          ),
        ],
      ),
    );
  }

  Widget _readout(BuildContext context, PlateBuilderState state) {
    final NutritionalSummary s = state.macros;
    final MawzoonTypography type = context.type;
    final MawzoonColors colors = context.colors;

    final String stateName = switch (state) {
      PlateEmpty() => 'PlateEmpty',
      PlateConfiguring() => 'PlateConfiguring',
      PlateVolumeAdjusted() => 'PlateVolumeAdjusted',
      PlateBalanced() => 'PlateBalanced',
    };

    return Container(
      padding: EdgeInsetsDirectional.all(context.space.base),
      decoration: BoxDecoration(
        color: colors.structure,
        borderRadius: context.space.surfaceRadius,
        border: Border.all(color: colors.hairline),
        boxShadow: context.elevation.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text('${s.displayKilocalories}', style: type.macroFigure),
              const SizedBox(width: 4),
              Text('kcal', style: type.macroUnit.copyWith(color: colors.inkFaint)),
              const Spacer(),
              Text(
                'P${s.displayProteinGrams} · C${s.displayCarbohydrateGrams} · '
                'F${s.displayFatGrams} · GL${s.glycemic.displayLoad}',
                style: type.macroUnit.copyWith(color: colors.inkSoft),
              ),
            ],
          ),
          SizedBox(height: context.space.snug),
          MawzoonText(
            s.isComplete
                ? s.framing.headline.resolve(widget.language)
                : _t('أكمل الأقسام', 'Finish the plate'),
            style: type.capsuleLabel,
            color: s.isComplete ? colors.olive : colors.inkFaint,
          ),
          SizedBox(height: context.space.tight),
          Text(
            '$stateName · ${s.scale.name} · '
            '${s.glycemic.balance.name} release',
            style: type.tagLabel.copyWith(color: colors.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _segmentRail(BuildContext context, PlateSegment segment) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          MawzoonText(
            segment.label.resolve(widget.language),
            style: context.type.sectionTitle,
          ),
          MawzoonText(
            segment.invitation.resolve(widget.language),
            style: context.type.caption,
            color: context.colors.inkFaint,
          ),
        ],
      );

  Widget _segmentTrack(
    BuildContext context,
    PlateSegment segment,
    PlateBuilderState state,
  ) {
    final MawzoonColors colors = context.colors;
    final MawzoonSpacing space = context.space;
    final Color tone = colors.toneForSegmentOrdinal(segment.ordinal);
    final IngredientOption? chosen = state.selection.optionFor(segment);

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: MawzoonCatalog.optionsFor(segment).length,
        separatorBuilder: (_, __) => SizedBox(width: space.snug),
        itemBuilder: (BuildContext context, int index) {
          final IngredientOption option =
              MawzoonCatalog.optionsFor(segment)[index];
          final bool selected = chosen?.id == option.id;
          final PortionedComponent portion = option.atScale(state.scale);

          return GestureDetector(
            onTap: () => selected
                ? _controller.clearSegment(segment)
                : _controller.select(option),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 150,
              padding: EdgeInsetsDirectional.all(space.base),
              decoration: BoxDecoration(
                color: selected ? colors.structureElevated : colors.structure,
                borderRadius: space.controlRadius,
                border: Border.all(
                  color: selected ? tone : colors.hairline,
                  width: 1.5,
                ),
                boxShadow: selected
                    ? context.elevation.lifted
                    : context.elevation.resting,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: MawzoonText(
                      option.name.resolve(widget.language),
                      style: context.type.dishName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${portion.kilocalories.round()} kcal · '
                    '${portion.portionGrams.round()}g',
                    style: context.type.macroUnit.copyWith(
                      color: selected ? tone : colors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _scaleToggle(BuildContext context, PlateBuilderState state) => Row(
        children: <Widget>[
          for (final PortionScale scale in PortionScale.values)
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: context.space.snug),
                child: FilledButton(
                  onPressed: () => _controller.setScale(scale),
                  style: state.scale == scale
                      ? null
                      : FilledButton.styleFrom(
                          backgroundColor: context.colors.structure,
                          foregroundColor: context.colors.inkSoft,
                        ),
                  child: MawzoonText(
                    scale.label.resolve(widget.language),
                    style: context.type.buttonLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      );
}
