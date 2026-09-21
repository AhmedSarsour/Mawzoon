import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/ui_primitives/plate/plate_geometry.dart';

const Size _phone = Size(340, 150);

void main() {
  group('the dish', () {
    final PlateGeometry g = PlateGeometry.forSize(_phone);

    test('fits inside its box', () {
      final Rect bounds = g.dish.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(-0.5));
      expect(bounds.top, greaterThanOrEqualTo(-0.5));
      expect(bounds.right, lessThanOrEqualTo(_phone.width + 0.5));
      expect(bounds.bottom, lessThanOrEqualTo(_phone.height + 0.5));
    });

    test('the ring sits outside the dish but still inside the box', () {
      final Rect dish = g.dish.getBounds();
      final Rect ring = g.ring.getBounds();
      expect(ring.width, greaterThan(dish.width));
      expect(ring.height, greaterThan(dish.height));
      expect(ring.left, greaterThanOrEqualTo(-0.5));
      expect(ring.right, lessThanOrEqualTo(_phone.width + 0.5));
    });

    test('is elongated, not round', () {
      final Rect bounds = g.dish.getBounds();
      expect(bounds.width / bounds.height, greaterThan(1.6));
    });

    // A superellipse at this exponent holds more area than the ellipse on the
    // same axes; that difference is the whole reason for choosing it.
    test('is fuller than the ellipse on the same axes', () {
      final Rect bounds = g.dish.getBounds();
      final double ellipse = math.pi * (bounds.width / 2) * (bounds.height / 2);
      expect(g.dishArea, greaterThan(ellipse * 1.02));
      expect(g.dishArea, lessThan(bounds.width * bounds.height));
    });

    test('the outline is not a plain ellipse at any sampled angle', () {
      // The organic modulation must actually reach the path, not be rounded
      // away somewhere between the sampler and the Path.
      final Rect bounds = g.dish.getBounds();
      final Offset centre = bounds.center;
      final double a = bounds.width / 2;
      final double b = bounds.height / 2;
      bool anyOffEllipse = false;
      for (int i = 0; i < 64; i++) {
        final double t = 2 * math.pi * i / 64;
        final Offset p = Offset(
          centre.dx + a * math.cos(t),
          centre.dy + b * math.sin(t),
        );
        if (!g.dish.contains(p)) anyOffEllipse = true;
      }
      expect(anyOffEllipse, isTrue,
          reason: 'the dish should not coincide with its bounding ellipse',);
    });
  });

  // The headline claim of the module: the tray is split by area, so the middle
  // compartment does not look half again as big as the ends.
  group('the split is by area, not by width', () {
    final PlateGeometry g = PlateGeometry.forSize(_phone);

    test('each zone holds its requested share of the dish', () {
      final List<double> measured = g.measuredAreaFractions;
      for (int i = 0; i < 3; i++) {
        expect(
          measured[i],
          closeTo(PlateGeometry.defaultAreaFractions[i], 0.01),
          reason: 'zone $i is ${(measured[i] * 100).toStringAsFixed(2)}% '
              'but should be '
              '${(PlateGeometry.defaultAreaFractions[i] * 100).toStringAsFixed(2)}%',
        );
      }
    });

    test('the zones account for the whole dish', () {
      final double sum =
          g.zoneAreas.reduce((double a, double b) => a + b);
      expect(sum, closeTo(g.dishArea, g.dishArea * 0.02));
    });

    test('equal area demands unequal widths, which is the whole point', () {
      // An oval is fattest in the middle, so an equal-AREA middle compartment
      // has to be a narrower strip than the ends. Measured on the bow-free
      // shape so the dividers' curvature cannot flatter the numbers.
      final PlateGeometry even = PlateGeometry.forSize(
        _phone,
        areaFractions: const <double>[1 / 3, 1 / 3, 1 / 3],
        dividerBow: 0,
      );
      final double dishWidth = even.dish.getBounds().width;
      final List<double> widths = even.zones
          .map((Path p) => p.getBounds().width / dishWidth)
          .toList(growable: false);

      for (final double area in even.measuredAreaFractions) {
        expect(area, closeTo(1 / 3, 0.01));
      }
      expect(widths[1], lessThan(0.31),
          reason: 'the middle third by area should be a narrow strip, but it '
              'is ${(widths[1] * 100).toStringAsFixed(1)}% of the width — '
              'which would mean the split was really by width',);
      expect(widths[0], greaterThan(widths[1]));
      expect(widths[2], greaterThan(widths[1]));
    });

    test('the middle compartment stays the narrowest once bowed', () {
      final PlateGeometry even = PlateGeometry.forSize(
        _phone,
        areaFractions: const <double>[1 / 3, 1 / 3, 1 / 3],
      );
      final List<double> widths =
          even.zones.map((Path p) => p.getBounds().width).toList(growable: false);
      expect(widths[1], lessThan(widths[0]));
      expect(widths[1], lessThan(widths[2]));
    });

    test('zones are ordered left to right and do not overlap', () {
      final List<Rect> bounds =
          g.zones.map((Path p) => p.getBounds()).toList(growable: false);
      expect(bounds[0].left, lessThan(bounds[1].left));
      expect(bounds[1].left, lessThan(bounds[2].left));
      // Shared dividers are bowed, so a small overlap of the bounding boxes is
      // expected; the paths themselves still meet exactly.
      expect(bounds[0].right, lessThan(bounds[2].left));
    });

    test('every zone contains its own centroid', () {
      for (int i = 0; i < 3; i++) {
        expect(g.zones[i].contains(g.zoneCentroids[i]), isTrue,
            reason: 'zone $i centroid fell outside its own path',);
      }
    });

    test('centroids march left to right and sit near the midline', () {
      expect(g.zoneCentroids[0].dx, lessThan(g.zoneCentroids[1].dx));
      expect(g.zoneCentroids[1].dx, lessThan(g.zoneCentroids[2].dx));
      for (final Offset c in g.zoneCentroids) {
        expect(c.dy, closeTo(_phone.height / 2, _phone.height * 0.12));
      }
    });

    test('a lopsided split is honoured too', () {
      final PlateGeometry lopsided = PlateGeometry.forSize(
        _phone,
        areaFractions: const <double>[0.6, 0.25, 0.15],
      );
      final List<double> measured = lopsided.measuredAreaFractions;
      expect(measured[0], closeTo(0.6, 0.015));
      expect(measured[1], closeTo(0.25, 0.015));
      expect(measured[2], closeTo(0.15, 0.015));
    });
  });

  // Both of these were caught by looking at a rendered frame, not by any
  // amount of arithmetic. They are regression tests for exactly that.
  group('shared dividers coincide', () {
    final PlateGeometry g = PlateGeometry.forSize(_phone);

    test('every point along the plate belongs to exactly one zone', () {
      // Adjacent compartments trace the same divider in opposite directions.
      // If the bow is not negated on the return pass the two curves mirror
      // each other, opening a lens-shaped gap that no area check would notice.
      final Rect bounds = g.dish.getBounds();
      int gaps = 0;
      int overlaps = 0;

      for (int xi = 2; xi < 200; xi++) {
        final double x = bounds.left + bounds.width * xi / 200;
        for (int yi = 1; yi < 12; yi++) {
          final Offset p = Offset(x, bounds.top + bounds.height * yi / 12);
          if (!g.dish.contains(p)) continue;
          final int hits =
              g.zones.where((Path z) => z.contains(p)).length;
          if (hits == 0) gaps++;
          if (hits > 1) overlaps++;
        }
      }

      // The tiling is exact, so this is exact: with coincident dividers not
      // one of the ~2000 sampled points falls between two compartments or
      // inside both. Mismatched dividers put dozens in both.
      expect(gaps, 0, reason: '$gaps points fell between zones');
      expect(overlaps, 0, reason: '$overlaps points fell inside two zones');
    });

    test('the zones tile the dish almost exactly', () {
      final double sum = g.zoneAreas.reduce((double a, double b) => a + b);
      expect(sum, closeTo(g.dishArea, g.dishArea * 0.005));
    });
  });

  group('direction', () {
    test('mirroring flips the compartment sizes, not just their order', () {
      // Mapping a compartment to a different slot is not enough: the slots are
      // different sizes, so without reversing the fractions the protein — the
      // largest share — lands in the smallest well whenever the app runs in
      // Arabic.
      final PlateGeometryCache cache = PlateGeometryCache();
      final PlateGeometry ltr = cache.of(_phone);
      final List<double> ltrAreas = ltr.measuredAreaFractions;

      final PlateGeometry rtl = cache.of(_phone, mirror: true);
      final List<double> rtlAreas = rtl.measuredAreaFractions;

      expect(ltrAreas.first, closeTo(PlateGeometry.defaultAreaFractions.first, 0.012));
      expect(rtlAreas.last, closeTo(PlateGeometry.defaultAreaFractions.first, 0.012));
      expect(rtlAreas.last, greaterThan(rtlAreas.first));
      expect(ltrAreas.first, greaterThan(ltrAreas.last));
    });

    test('the cache keys on direction as well as size', () {
      final PlateGeometryCache cache = PlateGeometryCache();
      final PlateGeometry ltr = cache.of(_phone);
      final PlateGeometry rtl = cache.of(_phone, mirror: true);
      expect(identical(ltr, rtl), isFalse);
      expect(identical(cache.of(_phone, mirror: true), rtl), isTrue);
      expect(identical(cache.of(_phone), rtl), isFalse);
    });
  });

  group('the ring', () {
    final PlateGeometry g = PlateGeometry.forSize(_phone);

    test('has a measurable perimeter', () {
      expect(g.ringLength, greaterThan(0));
      final Rect bounds = g.ring.getBounds();
      // Between the inscribed diamond and the bounding rectangle's perimeter.
      expect(g.ringLength, greaterThan(2 * (bounds.width + bounds.height) / 2));
      expect(g.ringLength, lessThan(2 * (bounds.width + bounds.height)));
    });

    test('starts at the top of the dish, not wherever sampling began', () {
      final Path head = g.arc(0, 0.001);
      final Rect bounds = g.ring.getBounds();
      expect(head.getBounds().top, closeTo(bounds.top, bounds.height * 0.06));
      expect(
        head.getBounds().center.dx,
        closeTo(bounds.center.dx, bounds.width * 0.08),
      );
    });

    test('extractPath returns a genuine sub-path of the rim', () {
      final Path quarter = g.arc(0, 0.25);
      final Rect ringBounds = g.ring.getBounds().inflate(1);
      expect(ringBounds.contains(quarter.getBounds().topLeft), isTrue);
      expect(ringBounds.contains(quarter.getBounds().bottomRight), isTrue);
      // A quarter of the perimeter cannot span the whole ring.
      expect(quarter.getBounds().width, lessThan(g.ring.getBounds().width));
    });

    test('a longer run covers more of the rim', () {
      final double short = g.arc(0, 0.1).getBounds().width;
      final double long = g.arc(0, 0.45).getBounds().width;
      expect(long, greaterThan(short));
    });

    test('an empty or inverted run yields an empty path', () {
      expect(g.arc(0.5, 0.5).computeMetrics().isEmpty, isTrue);
      expect(g.arc(0.8, 0.2).computeMetrics().isEmpty, isTrue);
    });

    test('mirroring reflects the run about the start', () {
      final Rect normal = g.arc(0, 0.25).getBounds();
      final Rect mirrored = g.arc(0, 0.25, mirror: true).getBounds();
      final double centre = g.ring.getBounds().center.dx;
      // One run leans right of centre, the other the same distance left.
      expect(
        (normal.center.dx - centre).sign,
        isNot((mirrored.center.dx - centre).sign),
      );
      expect(
        (normal.center.dx - centre).abs(),
        closeTo((mirrored.center.dx - centre).abs(), 6),
      );
    });

    test('fractions are clamped rather than throwing', () {
      expect(() => g.arc(-1, 2), returnsNormally);
      expect(g.arc(-1, 2).computeMetrics().isNotEmpty, isTrue);
    });
  });

  group('stability across sizes', () {
    test('the area split holds at every plausible box', () {
      for (final Size size in const <Size>[
        Size(280, 120),
        Size(340, 150),
        Size(420, 190),
        Size(600, 240),
      ]) {
        final PlateGeometry g = PlateGeometry.forSize(size);
        final List<double> measured = g.measuredAreaFractions;
        for (int i = 0; i < 3; i++) {
          expect(
            measured[i],
            closeTo(PlateGeometry.defaultAreaFractions[i], 0.012),
            reason: '$size zone $i drifted to '
                '${(measured[i] * 100).toStringAsFixed(2)}%',
          );
        }
      }
    });

    test('a tiny box degrades without throwing', () {
      expect(() => PlateGeometry.forSize(const Size(24, 12)), returnsNormally);
    });

    test('rejects a non-positive box', () {
      expect(
        () => PlateGeometry.forSize(Size.zero),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('geometry cache', () {
    test('returns the same instance until the size changes', () {
      final PlateGeometryCache cache = PlateGeometryCache();
      final PlateGeometry first = cache.of(_phone);
      expect(identical(cache.of(_phone), first), isTrue);

      final PlateGeometry resized = cache.of(const Size(400, 170));
      expect(identical(resized, first), isFalse);
      expect(identical(cache.of(const Size(400, 170)), resized), isTrue);
    });

    test('clear forces a re-solve', () {
      final PlateGeometryCache cache = PlateGeometryCache();
      final PlateGeometry first = cache.of(_phone);
      cache.clear();
      expect(identical(cache.of(_phone), first), isFalse);
    });
  });
}
