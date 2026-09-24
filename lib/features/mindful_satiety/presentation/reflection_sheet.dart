import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme.dart';
import '../domain/reflection_journal.dart';
import '../domain/satiety_answer.dart';

/// The words on the reflection surfaces, in one place so the restraint test
/// can read every one of them.
abstract final class ReflectionCopy {
  /// The question.
  static const LocalizedText question =
      LocalizedText(ar: 'كيف يشعر جسمك الآن؟', en: 'How does your body feel?');

  /// Above the question.
  static const LocalizedText eyebrow =
      LocalizedText(ar: 'عن وجبتك قبل قليل', en: 'About your meal earlier');

  /// Satiety row label.
  static const LocalizedText fullness = LocalizedText(ar: 'الشبع', en: 'Fullness');

  /// Energy row label.
  static const LocalizedText energy = LocalizedText(ar: 'الطاقة', en: 'Energy');

  /// Skip.
  static const LocalizedText notNow = LocalizedText(ar: 'ليس الآن', en: 'Not now');

  /// After the second tap.
  static const LocalizedText saved = LocalizedText(
    ar: 'شكراً. سنتذكّر هذا في طلبك القادم.',
    en: "Thanks. We'll remember this next time.",
  );

  /// Every string above, for the restraint test.
  static const List<LocalizedText> all = <LocalizedText>[
    question,
    eyebrow,
    fullness,
    energy,
    notNow,
    saved,
  ];
}

/// Opens the question about [pending].
///
/// Dragging the sheet away is not a skip: the question stays open until it
/// expires. Only "Not now" drops it.
Future<void> showReflectionSheet(
  BuildContext context, {
  required PendingReflection pending,
  required Future<void> Function(SatietyLevel, EnergyLevel) onAnswered,
  required Future<void> Function() onSkipped,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => ReflectionSheet(
      pending: pending,
      onAnswered: onAnswered,
      onSkipped: onSkipped,
    ),
  );
}

/// Two rows of three. Energy appears once fullness is picked; picking energy
/// saves. No submit button, no numbers.
class ReflectionSheet extends StatefulWidget {
  /// Creates the sheet.
  const ReflectionSheet({
    required this.pending,
    required this.onAnswered,
    required this.onSkipped,
    super.key,
  });

  /// How long the thank-you line stays before the sheet closes.
  static const Duration thanksHold = Duration(milliseconds: 1400);

  /// The meal being asked about.
  final PendingReflection pending;

  /// Both answers, once.
  final Future<void> Function(SatietyLevel, EnergyLevel) onAnswered;

  /// "Not now".
  final Future<void> Function() onSkipped;

  @override
  State<ReflectionSheet> createState() => _ReflectionSheetState();
}

class _ReflectionSheetState extends State<ReflectionSheet> {
  SatietyLevel? _satiety;
  EnergyLevel? _energy;
  bool _saved = false;

  Future<void> _pickEnergy(EnergyLevel energy) async {
    final SatietyLevel? satiety = _satiety;
    if (satiety == null || _energy != null) return;
    setState(() => _energy = energy);
    await widget.onAnswered(satiety, energy);
    if (!mounted) return;
    setState(() => _saved = true);
    await Future<void>.delayed(ReflectionSheet.thanksHold);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    await widget.onSkipped();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final bool reduced = MediaQuery.of(context).disableAnimations;
    final Duration fade =
        reduced ? Duration.zero : const Duration(milliseconds: 220);
    final String dishes = widget.pending.snapshot.componentNames
        .map((LocalizedText n) => n.resolve(language))
        .join(' · ');

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: context.space.snug),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.canvas,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.space.radiusPlatter),
          ),
          border: Border.all(color: context.colors.hairline),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.space.comfortable,
              0,
              context.space.comfortable,
              context.space.base,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _Grabber(),
                MawzoonText(
                  ReflectionCopy.eyebrow.resolve(language),
                  style: context.type.caption,
                  color: context.colors.inkSoft,
                ),
                if (dishes.isNotEmpty)
                  MawzoonText(
                    dishes,
                    style: context.type.caption,
                    color: context.colors.inkFaint,
                    maxLines: 2,
                  ),
                SizedBox(height: context.space.tight),
                MawzoonText(
                  ReflectionCopy.question.resolve(language),
                  style: context.type.sectionTitle,
                  color: context.colors.ink,
                ),
                SizedBox(height: context.space.loose),
                AnimatedSwitcher(
                  duration: fade,
                  child: _saved
                      ? Padding(
                          key: const ValueKey<String>('saved'),
                          padding: EdgeInsetsDirectional.symmetric(
                            vertical: context.space.loose,
                          ),
                          child: MawzoonText(
                            ReflectionCopy.saved.resolve(language),
                            style: context.type.body,
                            color: context.colors.ink,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Column(
                          key: const ValueKey<String>('ask'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _ChoiceRow<SatietyLevel>(
                              label: ReflectionCopy.fullness,
                              options: SatietyLevel.values,
                              labelOf: (SatietyLevel s) => s.label,
                              selected: _satiety,
                              onPicked: (SatietyLevel s) {
                                if (_energy != null) return;
                                setState(() => _satiety = s);
                              },
                            ),
                            SizedBox(height: context.space.comfortable),
                            // Progressive disclosure: one decision at a time.
                            AnimatedOpacity(
                              opacity: _satiety == null ? 0 : 1,
                              duration: fade,
                              child: IgnorePointer(
                                ignoring: _satiety == null,
                                child: ExcludeSemantics(
                                  excluding: _satiety == null,
                                  child: _ChoiceRow<EnergyLevel>(
                                    label: ReflectionCopy.energy,
                                    options: EnergyLevel.values,
                                    labelOf: (EnergyLevel e) => e.label,
                                    selected: _energy,
                                    onPicked: _pickEnergy,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: context.space.base),
                            Center(
                              child: TextButton(
                                onPressed: _skip,
                                child: MawzoonText(
                                  ReflectionCopy.notNow.resolve(language),
                                  style: context.type.capsuleLabel,
                                  color: context.colors.inkSoft,
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
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onPicked,
  });

  final LocalizedText label;
  final List<T> options;
  final LocalizedText Function(T) labelOf;
  final T? selected;
  final ValueChanged<T> onPicked;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MawzoonText(
          label.resolve(language),
          style: context.type.caption,
          color: context.colors.inkSoft,
        ),
        SizedBox(height: context.space.tight),
        Row(
          children: <Widget>[
            for (final T option in options) ...<Widget>[
              if (option != options.first) SizedBox(width: context.space.tight),
              Expanded(
                child: _Chip(
                  text: labelOf(option).resolve(language),
                  selected: option == selected,
                  onPressed: () => onPicked(option),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// All three chips look the same until one is picked, so none of them reads
/// as the right answer.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.selected,
    required this.onPressed,
  });

  final String text;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TactileFeedbackWell(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: text,
      child: AnimatedContainer(
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 180),
        constraints: BoxConstraints(minHeight: context.space.thumbTarget),
        alignment: Alignment.center,
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.tight,
          vertical: context.space.snug,
        ),
        decoration: BoxDecoration(
          color: selected ? context.colors.olive : context.colors.structure,
          borderRadius: BorderRadius.circular(context.space.radiusControl),
          border: Border.all(
            color: selected ? context.colors.olive : context.colors.hairline,
          ),
        ),
        child: MawzoonText(
          text,
          style: context.type.capsuleLabel,
          color: selected ? context.colors.onOlive : context.colors.ink,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            vertical: context.space.base,
          ),
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.inkFaint,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
}
