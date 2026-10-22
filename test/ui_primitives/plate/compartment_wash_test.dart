import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/ui_primitives/plate/plate_canvas_painter.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

/// P2: a richer wash must not cost the label its legibility. The label is
/// drawn in the compartment's own tone, so a stronger wash of that same tone
/// is exactly what could pull the two together.
void main() {
  test('the wash is richer than the first pass, and richer in dark', () {
    for (final double fill in <double>[0, 0.5, 1]) {
      expect(
        PlateCanvasPainter.compartmentWashAlpha(dark: false, fill: fill),
        greaterThan(0.10 + 0.09 * fill),
      );
      expect(
        PlateCanvasPainter.compartmentWashAlpha(dark: true, fill: fill),
        greaterThan(
          PlateCanvasPainter.compartmentWashAlpha(dark: false, fill: fill),
        ),
      );
    }
  });

  test('a tone that already clears 3:1 keeps its colour', () {
    // Light fibre (ordinal 2) is comfortably above 3:1 on its own wash.
    final MawzoonColors c = MawzoonColors.light();
    final Color tone = c.toneForSegmentOrdinal(2);
    expect(PlateCanvasPainter.compartmentLabelInk(c, tone), tone);
  });

  for (final bool dark in <bool>[false, true]) {
    test('label tone clears 3:1 on its blended wash (${dark ? 'dark' : 'light'})',
        () {
      final MawzoonColors c = dark ? MawzoonColors.dark() : MawzoonColors.light();
      final double alpha =
          PlateCanvasPainter.compartmentWashAlpha(dark: dark, fill: 1);
      for (int ordinal = 0; ordinal < 3; ordinal++) {
        final Color tone = c.toneForSegmentOrdinal(ordinal);
        final Color ink = PlateCanvasPainter.compartmentLabelInk(c, tone);
        // Both surfaces the well can look like: the darker and lighter ends.
        for (final Color well in <Color>[c.structure, c.structureElevated]) {
          final Color blended =
              Color.alphaBlend(tone.withValues(alpha: alpha), well);
          expect(
            MawzoonBrand.contrastRatio(ink, blended),
            greaterThanOrEqualTo(3),
            reason: 'ordinal $ordinal on $well',
          );
        }
      }
    });
  }
}
