import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/mindful_satiety/application/reflection_controller.dart';
import 'package:mawzoon/features/mindful_satiety/data/reflection_notifier.dart';
import 'package:mawzoon/features/mindful_satiety/data/reflection_store.dart';
import 'package:mawzoon/features/mindful_satiety/domain/reflection_journal.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_answer.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_insight.dart';
import 'package:mawzoon/features/mindful_satiety/presentation/reflection_sheet.dart';
import 'package:mawzoon/features/mindful_satiety/presentation/reflection_surfaces.dart';
import 'package:mawzoon/features/order_home/presentation/order_home_screen.dart';
import 'package:mawzoon/ui_primitives/interaction/haptics.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

import 'reflection_fixtures.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

Widget _app(Widget home, {AppLanguage language = AppLanguage.arabic}) =>
    MaterialApp(
      theme: AppTheme.light(language: language, fonts: _fonts),
      locale: Locale(language.code),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      home: home,
    );

final PendingReflection _due =
    PendingReflection(id: 'q', snapshot: snapshot(), dueAt: noon);

/// Every string actually painted under [finder].
List<String> _painted(WidgetTester tester, [Finder? within]) => tester
    .widgetList<RichText>(
      within == null
          ? find.byType(RichText)
          : find.descendant(of: within, matching: find.byType(RichText)),
    )
    .map((RichText t) => t.text.toPlainText())
    .toList();

/// The home screen breathes forever (ambient glow), so it never settles.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Western and Arabic-Indic digits.
final RegExp _digit = RegExp('[0-9٠-٩۰-۹]');

void main() {
  setUp(() => MawzoonHaptics.enabled = false);
  tearDown(() => MawzoonHaptics.enabled = true);

  testWidgets('card → sheet → two taps → one answer saved', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final InMemoryReflectionStore store =
        InMemoryReflectionStore(ReflectionRecord(pending: _due));
    final ReflectionController controller = ReflectionController(
      store: store,
      notifier: FakeReflectionNotifier(),
      now: () => noon.add(const Duration(minutes: 10)),
    );
    await controller.start();

    await tester.pumpWidget(
      _app(ReflectionScope(controller: controller, child: const OrderHomeScreen())),
    );
    await _settle(tester);

    await tester.tap(find.byType(ReflectionCard));
    await _settle(tester);
    expect(find.byType(ReflectionSheet), findsOneWidget);

    // Energy row is hidden until fullness is picked.
    expect(find.bySemanticsLabel(EnergyLevel.calm.label.ar), findsNothing);

    await tester.tap(find.text(SatietyLevel.heavy.label.ar));
    await _settle(tester);
    await tester.tap(find.text(EnergyLevel.sluggish.label.ar));
    await _settle(tester);

    expect(find.text(ReflectionCopy.saved.ar), findsOneWidget);
    await tester.pump(ReflectionSheet.thanksHold);
    await _settle(tester);

    expect(find.byType(ReflectionSheet), findsNothing);
    expect(find.byType(ReflectionCard), findsNothing);
    final ReflectionRecord saved = await store.load();
    expect(saved.journal.entries, hasLength(1));
    expect(saved.journal.entries.single.satiety, SatietyLevel.heavy);
    expect(saved.journal.entries.single.energy, EnergyLevel.sluggish);

    controller.dispose();
  });

  testWidgets('no card before the question is due', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ReflectionController controller = ReflectionController(
      store: InMemoryReflectionStore(ReflectionRecord(pending: _due)),
      notifier: FakeReflectionNotifier(),
      now: () => noon.subtract(const Duration(minutes: 1)),
    );
    await controller.start();
    await tester.pumpWidget(
      _app(ReflectionScope(controller: controller, child: const OrderHomeScreen())),
    );
    await _settle(tester);
    expect(find.byType(ReflectionCard), findsNothing);
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dragging the sheet away is not a skip', (tester) async {
    int skips = 0;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showReflectionSheet(
              context,
              pending: _due,
              onAnswered: (_, __) async {},
              onSkipped: () async => skips++,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pumpAndSettle();
    expect(find.byType(ReflectionSheet), findsNothing);
    expect(skips, 0);
  });

  group('restraint: no numbers, no streaks, no calorie talk', () {
    for (final AppLanguage language in AppLanguage.values) {
      testWidgets('sheet, every state, ${language.code}', (tester) async {
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: ReflectionSheet(
                pending: _due,
                onAnswered: (_, __) async {},
                onSkipped: () async {},
              ),
            ),
            language: language,
          ),
        );
        final Finder sheet = find.byType(ReflectionSheet);
        void check(String state) {
          for (final String text in _painted(tester, sheet)) {
            expect(text, isNot(matches(_digit)), reason: '$state: "$text"');
          }
        }

        check('asking');
        await tester.tap(find.text(SatietyLevel.balanced.label.resolve(language)));
        await tester.pumpAndSettle();
        check('energy shown');
        await tester.tap(find.text(EnergyLevel.calm.label.resolve(language)));
        await tester.pumpAndSettle();
        check('saved');
        await tester.pump(ReflectionSheet.thanksHold);
      });

      testWidgets('insight lines, ${language.code}', (tester) async {
        for (final SatietyInsight insight in <SatietyInsight>[
          const PortionInsight(
            from: PortionScale.athleticLoad,
            suggested: PortionScale.standardBalance,
          ),
          const PortionInsight(
            from: PortionScale.standardBalance,
            suggested: PortionScale.athleticLoad,
          ),
          const CarbReleaseInsight(),
        ]) {
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: InsightLine(
                  insight: insight,
                  onApplyScale: (_) {},
                  onDismiss: () {},
                ),
              ),
              language: language,
            ),
          );
          for (final String text in _painted(tester)) {
            expect(text, isNot(matches(_digit)), reason: '$insight: "$text"');
          }
        }
      });
    }

    test('no copy mentions streaks, scores or calories', () {
      final RegExp banned = RegExp(
        r'streak|score|point|calorie|kcal|سلسل|نقاط|نقطة|سعر|هدف',
        caseSensitive: false,
      );
      final List<LocalizedText> copy = <LocalizedText>[
        ...ReflectionCopy.all,
        for (final SatietyLevel s in SatietyLevel.values) s.label,
        for (final EnergyLevel e in EnergyLevel.values) e.label,
        InsightLine.hideLabel,
        for (final PortionScale from in PortionScale.values) ...<LocalizedText>[
          PortionInsight(from: from, suggested: from.toggled).message,
          PortionInsight(from: from, suggested: from.toggled).action,
        ],
        const CarbReleaseInsight().message,
      ];
      for (final LocalizedText t in copy) {
        expect(t.ar, isNot(matches(banned)), reason: t.ar);
        expect(t.en, isNot(matches(banned)), reason: t.en);
        expect(t.ar, isNot(matches(_digit)), reason: t.ar);
        expect(t.en, isNot(matches(_digit)), reason: t.en);
      }
    });
  });
}
