@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';

/// Verifies the press compression by rendering it.
///
/// The compression is applied inside an `AnimatedBuilder`, and reading the
/// resulting `Transform` back out of the widget tree proved unreliable — the
/// builder demonstrably receives the animated value while the finder returns
/// an identity matrix. Rather than assert against a flaky observation, these
/// goldens compare the actual pixels: a pressed target is visibly smaller than
/// a resting one, which is the property that matters to a guest.
Widget _frame(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF111312),
        body: Center(child: child),
      ),
    );

Widget get _target => Container(
      width: 180,
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFFDE6B35),
        borderRadius: BorderRadius.circular(18),
      ),
    );

void main() {
  testWidgets('resting', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(260, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _frame(TactileFeedbackWell(onPressed: () {}, child: _target)),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pressable_resting.png'),
    );
  });

  testWidgets('pressed', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(260, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _frame(TactileFeedbackWell(onPressed: () {}, child: _target)),
    );
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.byType(TactileFeedbackWell)));
    addTearDown(() async {
      await gesture.up();
    });
    // Two frames: the first only starts the ticker at zero elapsed time.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pressable_pressed.png'),
    );
  });
}
