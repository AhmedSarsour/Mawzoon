import 'dart:math' as math;
import 'dart:ui';

/// The mathematics of the Mawzoon platter.
///
/// Pure geometry: it builds paths and measures areas and holds no colours, no
/// animation and no widgets. Everything here is deterministic for a given
/// [Size], which is what lets the whole shape be unit-tested rather than
/// eyeballed in a screenshot.
///
/// ## The dish
///
/// A true ellipse reads as a logo. The dish is a **superellipse**
///
/// ```text
///   |x/a|^n + |y/b|^n = 1
/// ```
///
/// at [exponent] ≈ 2.7, which flattens the long sides and fills the ends the
/// way a thrown ceramic platter does, then carries a very low-amplitude
/// three-lobe modulation so the outline is never machine-perfect. The
/// modulation is far too small to read as a wobble and exactly large enough
/// that the eye stops recognising a formula.
///
/// ## The split
///
/// The three compartments are divided by **area, not by width**. An oval is
/// fattest in the middle, so three equal-width slices produce a middle
/// compartment that looks half again as large as the ends — which would say
/// something false about the plate, since the tray's compartments are a fixed
/// physical fact. The boundaries are solved numerically so the three zones
/// hold [areaFractions] of the dish to within a fraction of a percent, and a
/// test asserts it.
///
/// Dividers are S-curves rather than straight lines, with control points
/// mirrored about the midpoint so the area each curve gives up above it is
/// returned below it. The split stays true and the tray stops looking stamped.
final class PlateGeometry {
  PlateGeometry._({
    required this.size,
    required this.dish,
    required this.ring,
    required this.zones,
    required this.zoneCentroids,
    required this.zoneAreas,
    required this.dishArea,
    required this.ringMetric,
    required this.ringLength,
  });

  /// Solves the geometry for [size].
  ///
  /// Costly enough — a few hundred trig evaluations plus two bisections — that
  /// it must not run per frame. [PlateGeometryCache] holds the result for a
  /// given size; the painter re-solves only when the box actually changes.
  factory PlateGeometry.forSize(
    Size size, {
    List<double> areaFractions = defaultAreaFractions,
    double exponent = defaultExponent,
    double ringGap = defaultRingGap,
    double organicAmplitude = defaultOrganicAmplitude,
    double dividerBow = defaultDividerBow,
    int samples = defaultSamples,
  }) {
    assert(areaFractions.length == 3, 'the plate has exactly three zones');
    assert(
      (areaFractions.reduce((double a, double b) => a + b) - 1).abs() < 1e-9,
      'area fractions must sum to 1',
    );
    assert(size.width > 0 && size.height > 0, 'size must be positive');
    assert(exponent >= 2, 'an exponent below 2 pinches the ends into a lens');
    assert(samples >= 64 && samples.isEven, 'samples must be even and >= 64');

    // Leave room outside the dish for the ring and its stroke.
    final double inset = ringGap * 2;
    final double a = math.max(1, size.width / 2 - inset);
    final double b = math.max(1, size.height / 2 - inset);
    final Offset centre = Offset(size.width / 2, size.height / 2);

    final _Outline dishOutline = _Outline.superellipse(
      centre: centre,
      a: a,
      b: b,
      exponent: exponent,
      organicAmplitude: organicAmplitude,
      samples: samples,
    );
    final _Outline ringOutline = _Outline.superellipse(
      centre: centre,
      a: a + ringGap,
      b: b + ringGap,
      exponent: exponent,
      organicAmplitude: organicAmplitude,
      samples: samples,
    );

    final double totalArea = dishOutline.area;

    // Solve the two boundaries that cut the dish into the requested areas.
    final double firstCut = dishOutline.xAtAreaFraction(areaFractions[0]);
    final double secondCut =
        dishOutline.xAtAreaFraction(areaFractions[0] + areaFractions[1]);
    final List<double> cuts = <double>[firstCut, secondCut];

    final List<Path> zones = <Path>[];
    final List<Offset> centroids = <Offset>[];
    final List<double> areas = <double>[];

    for (int i = 0; i < 3; i++) {
      final double left = i == 0 ? dishOutline.minX : cuts[i - 1];
      final double right = i == 2 ? dishOutline.maxX : cuts[i];
      final _ZoneShape zone = dishOutline.zoneBetween(
        left,
        right,
        bow: dividerBow * a,
        bowLeft: i != 0,
        bowRight: i != 2,
      );
      zones.add(zone.path);
      centroids.add(zone.centroid);
      areas.add(zone.area);
    }

    final Path ringPath = ringOutline.toPath(startAtTopCentre: true);
    // Metrics are cached with the geometry rather than recomputed per frame:
    // building a PathMeasure walks the whole contour, while extracting a
    // sub-path from an existing one is comparatively cheap. This is the
    // difference between the ring costing microseconds and costing frames.
    final PathMetric metric = ringPath.computeMetrics().first;

    return PlateGeometry._(
      size: size,
      dish: dishOutline.toPath(),
      ring: ringPath,
      zones: List<Path>.unmodifiable(zones),
      zoneCentroids: List<Offset>.unmodifiable(centroids),
      zoneAreas: List<double>.unmodifiable(areas),
      dishArea: totalArea,
      ringMetric: metric,
      ringLength: metric.length,
    );
  }

  /// Protein takes the largest compartment, then the carb, then the greens.
  static const List<double> defaultAreaFractions = <double>[0.40, 0.34, 0.26];

  /// Superellipse exponent. 2 is an ellipse; 2.7 is a platter.
  static const double defaultExponent = 2.7;

  /// Distance from the dish edge out to the ring, in logical pixels.
  static const double defaultRingGap = 13;

  /// Amplitude of the three-lobe modulation, as a fraction of the radius.
  static const double defaultOrganicAmplitude = 0.012;

  /// Divider bow, as a fraction of the dish's semi-major axis.
  static const double defaultDividerBow = 0.055;

  /// Boundary samples. 240 keeps the outline smooth past a 3x device ratio.
  static const int defaultSamples = 240;

  /// The box this geometry was solved for.
  final Size size;

  /// The dish outline.
  final Path dish;

  /// The ring the macro arcs are extracted from. Starts at top centre.
  final Path ring;

  /// The three compartment paths, in build order.
  final List<Path> zones;

  /// Where a label sits inside each compartment.
  final List<Offset> zoneCentroids;

  /// The measured area of each compartment, in square logical pixels.
  final List<double> zoneAreas;

  /// The measured area of the whole dish.
  final double dishArea;

  /// The cached measure of [ring].
  final PathMetric ringMetric;

  /// Total perimeter of [ring].
  final double ringLength;

  /// The share of the dish each compartment actually occupies.
  List<double> get measuredAreaFractions =>
      zoneAreas.map((double a) => a / dishArea).toList(growable: false);

  /// Extracts the run of the ring between two arc-length fractions.
  ///
  /// This is [PathMetric.extractPath] against the cached measure — the arcs
  /// are genuine sub-paths of the dish's own perimeter, not a circle drawn
  /// nearby and hoped to line up.
  ///
  /// [mirror] reflects the run about the ring's start so the arcs grow
  /// right-to-left under RTL, matching the direction the compartments are
  /// read in.
  Path arc(double startFraction, double endFraction, {bool mirror = false}) {
    double from = startFraction.clamp(0.0, 1.0) * ringLength;
    double to = endFraction.clamp(0.0, 1.0) * ringLength;
    if (to <= from) return Path();
    if (mirror) {
      final double flippedFrom = ringLength - to;
      final double flippedTo = ringLength - from;
      from = flippedFrom;
      to = flippedTo;
    }
    return ringMetric.extractPath(from, to);
  }

  @override
  String toString() => 'PlateGeometry(${size.width.toStringAsFixed(0)}x'
      '${size.height.toStringAsFixed(0)}, ring ${ringLength.toStringAsFixed(1)}px)';
}

/// A sampled closed outline, with the profile queries the split needs.
final class _Outline {
  _Outline._(this.top, this.bottom, this.minX, this.maxX);

  /// Samples a modulated superellipse into an upper and a lower profile.
  ///
  /// Both profiles run left to right, so a vertical strip's height at any x is
  /// one interpolation from each.
  factory _Outline.superellipse({
    required Offset centre,
    required double a,
    required double b,
    required double exponent,
    required double organicAmplitude,
    required int samples,
  }) {
    final List<Offset> top = <Offset>[];
    final List<Offset> bottom = <Offset>[];
    final double k = 2 / exponent;

    // Signed power, so the curve keeps its sign through each quadrant.
    double sp(double v, double p) =>
        v.isNegative ? -math.pow(-v, p).toDouble() : math.pow(v, p).toDouble();

    for (int i = 0; i <= samples; i++) {
      final double t = math.pi * i / samples; // 0 -> pi, the upper half
      // Three lobes: slow enough to read as a thrown edge, not a ripple.
      final double m = 1 + organicAmplitude * math.sin(3 * t + math.pi / 5);
      final double x = centre.dx + a * m * sp(math.cos(t), k);
      final double y = centre.dy - b * m * sp(math.sin(t), k);
      top.add(Offset(x, y));
    }
    for (int i = 0; i <= samples; i++) {
      final double t = math.pi + math.pi * i / samples; // pi -> 2pi
      final double m = 1 + organicAmplitude * math.sin(3 * t + math.pi / 5);
      final double x = centre.dx + a * m * sp(math.cos(t), k);
      final double y = centre.dy - b * m * sp(math.sin(t), k);
      bottom.add(Offset(x, y));
    }

    // Upper samples run right to left; flip so both profiles ascend in x.
    final List<Offset> topAscending = top.reversed.toList(growable: false);
    return _Outline._(
      topAscending,
      bottom,
      math.min(topAscending.first.dx, bottom.first.dx),
      math.max(topAscending.last.dx, bottom.last.dx),
    );
  }

  /// Upper boundary, ascending in x.
  final List<Offset> top;

  /// Lower boundary, ascending in x.
  final List<Offset> bottom;

  /// Left extreme.
  final double minX;

  /// Right extreme.
  final double maxX;

  /// Area by the trapezoid rule over vertical strips.
  double get area => _areaUpTo(maxX);

  /// The y of the upper boundary at [x], linearly interpolated.
  double topAt(double x) => _sample(top, x);

  /// The y of the lower boundary at [x], linearly interpolated.
  double bottomAt(double x) => _sample(bottom, x);

  static double _sample(List<Offset> profile, double x) {
    if (x <= profile.first.dx) return profile.first.dy;
    if (x >= profile.last.dx) return profile.last.dy;
    int lo = 0;
    int hi = profile.length - 1;
    while (hi - lo > 1) {
      final int mid = (lo + hi) >> 1;
      if (profile[mid].dx <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final Offset p0 = profile[lo];
    final Offset p1 = profile[hi];
    final double span = p1.dx - p0.dx;
    if (span.abs() < 1e-12) return p0.dy;
    final double u = (x - p0.dx) / span;
    return p0.dy + (p1.dy - p0.dy) * u;
  }

  double _areaUpTo(double x, {int steps = 512}) {
    final double end = x.clamp(minX, maxX);
    if (end <= minX) return 0;
    final double dx = (end - minX) / steps;
    double sum = 0;
    double previous = bottomAt(minX) - topAt(minX);
    for (int i = 1; i <= steps; i++) {
      final double xi = minX + dx * i;
      final double height = bottomAt(xi) - topAt(xi);
      sum += (previous + height) / 2 * dx;
      previous = height;
    }
    return sum;
  }

  /// The x where the cumulative area reaches [fraction] of the whole.
  ///
  /// Bisection rather than a closed form: the modulation makes the integral
  /// non-analytic, and forty halvings resolve the boundary far finer than a
  /// physical pixel.
  double xAtAreaFraction(double fraction) {
    assert(fraction > 0 && fraction < 1, 'fraction must be strictly inside');
    final double target = area * fraction;
    double lo = minX;
    double hi = maxX;
    for (int i = 0; i < 40; i++) {
      final double mid = (lo + hi) / 2;
      if (_areaUpTo(mid) < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// Builds the compartment between [left] and [right].
  ///
  /// [bowLeft] and [bowRight] say which sides are shared dividers rather than
  /// the dish's own rim; only a shared divider is bowed, so the outer ends of
  /// the tray stay true to the dish outline.
  _ZoneShape zoneBetween(
    double left,
    double right, {
    required double bow,
    required bool bowLeft,
    required bool bowRight,
  }) {
    final List<Offset> polygon = <Offset>[];
    final Path path = Path();

    void addTop() {
      final List<Offset> run = _runBetween(top, left, right);
      polygon.addAll(run);
      path.moveTo(run.first.dx, run.first.dy);
      for (final Offset p in run.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    }

    void addDivider(double x, {required bool downward, required bool bowed}) {
      final double yTop = topAt(x);
      final double yBottom = bottomAt(x);
      if (!bowed) {
        path.lineTo(x, downward ? yBottom : yTop);
        polygon.add(Offset(x, downward ? yBottom : yTop));
        return;
      }
      // Mirrored control points: whatever area the curve takes from one
      // compartment above the midpoint, it gives back below it.
      //
      // The two compartments either side of a divider trace the same curve in
      // opposite directions, and reversing a cubic reverses its control points
      // too. Negating the bow on the upward pass is what makes the two edges
      // coincide exactly; without it they mirror and leave a lens-shaped gap
      // down every divider.
      final double y0 = downward ? yTop : yBottom;
      final double y1 = downward ? yBottom : yTop;
      final double signedBow = downward ? bow : -bow;
      final Offset c1 = Offset(x + signedBow, y0 + (y1 - y0) * 0.28);
      final Offset c2 = Offset(x - signedBow, y0 + (y1 - y0) * 0.72);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, x, y1);
      for (int i = 1; i <= 12; i++) {
        polygon.add(_cubicAt(Offset(x, y0), c1, c2, Offset(x, y1), i / 12));
      }
    }

    addTop();
    addDivider(right, downward: true, bowed: bowRight);
    final List<Offset> bottomRun =
        _runBetween(bottom, left, right).reversed.toList(growable: false);
    for (final Offset p in bottomRun) {
      path.lineTo(p.dx, p.dy);
    }
    polygon.addAll(bottomRun);
    addDivider(left, downward: false, bowed: bowLeft);
    path.close();

    return _ZoneShape(
      path: path,
      area: _shoelace(polygon).abs(),
      centroid: _centroid(polygon),
    );
  }

  static List<Offset> _runBetween(List<Offset> profile, double left, double right) {
    final List<Offset> run = <Offset>[Offset(left, _sample(profile, left))];
    for (final Offset p in profile) {
      if (p.dx > left && p.dx < right) run.add(p);
    }
    run.add(Offset(right, _sample(profile, right)));
    return run;
  }

  static Offset _cubicAt(Offset p0, Offset c1, Offset c2, Offset p1, double t) {
    final double u = 1 - t;
    final double w0 = u * u * u;
    final double w1 = 3 * u * u * t;
    final double w2 = 3 * u * t * t;
    final double w3 = t * t * t;
    return Offset(
      w0 * p0.dx + w1 * c1.dx + w2 * c2.dx + w3 * p1.dx,
      w0 * p0.dy + w1 * c1.dy + w2 * c2.dy + w3 * p1.dy,
    );
  }

  static double _shoelace(List<Offset> polygon) {
    double sum = 0;
    for (int i = 0; i < polygon.length; i++) {
      final Offset p = polygon[i];
      final Offset q = polygon[(i + 1) % polygon.length];
      sum += p.dx * q.dy - q.dx * p.dy;
    }
    return sum / 2;
  }

  static Offset _centroid(List<Offset> polygon) {
    double cx = 0;
    double cy = 0;
    double signedArea = 0;
    for (int i = 0; i < polygon.length; i++) {
      final Offset p = polygon[i];
      final Offset q = polygon[(i + 1) % polygon.length];
      final double cross = p.dx * q.dy - q.dx * p.dy;
      signedArea += cross;
      cx += (p.dx + q.dx) * cross;
      cy += (p.dy + q.dy) * cross;
    }
    if (signedArea.abs() < 1e-9) return polygon.first;
    signedArea /= 2;
    return Offset(cx / (6 * signedArea), cy / (6 * signedArea));
  }

  /// Builds the closed outline as a path.
  ///
  /// [startAtTopCentre] rotates the contour so arc-length zero sits at the top
  /// of the dish. A ring that begins wherever the sampler happened to start
  /// would put the first macro arc at an arbitrary point on the rim.
  Path toPath({bool startAtTopCentre = false}) {
    final List<Offset> loop = <Offset>[
      ...top,
      ...bottom.reversed,
    ];
    final List<Offset> ordered;
    if (startAtTopCentre) {
      int best = 0;
      double bestScore = double.infinity;
      final double midX = (minX + maxX) / 2;
      for (int i = 0; i < loop.length; i++) {
        // Nearest sample to the top centre, preferring the upper profile.
        final double score =
            (loop[i].dx - midX).abs() + (loop[i].dy - top.first.dy).abs() * 0.01;
        if (loop[i].dy < (top.first.dy + bottom.first.dy) / 2 &&
            score < bestScore) {
          bestScore = score;
          best = i;
        }
      }
      ordered = <Offset>[...loop.sublist(best), ...loop.sublist(0, best)];
    } else {
      ordered = loop;
    }

    final Path path = Path()..moveTo(ordered.first.dx, ordered.first.dy);
    for (final Offset p in ordered.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }
}

final class _ZoneShape {
  const _ZoneShape({
    required this.path,
    required this.area,
    required this.centroid,
  });

  final Path path;
  final double area;
  final Offset centroid;
}

/// Holds the solved geometry for one box size and direction.
///
/// The painter asks for geometry every frame and gets the same instance back
/// until the box actually changes, so the bisections and the PathMeasure are
/// paid for once per layout instead of 120 times a second.
final class PlateGeometryCache {
  /// Creates an empty cache.
  PlateGeometryCache();

  PlateGeometry? _cached;
  Size? _cachedSize;
  bool? _cachedMirror;

  /// The geometry for [size], solving it only when something has changed.
  ///
  /// [mirror] reverses the compartment areas so the tray itself flips under
  /// RTL. Mapping a compartment to a different slot is not enough on its own:
  /// the slots are different sizes, so without this the protein — the largest
  /// share — would land in the smallest well whenever the app runs in Arabic.
  PlateGeometry of(Size size, {bool mirror = false}) {
    final PlateGeometry? existing = _cached;
    if (existing != null && _cachedSize == size && _cachedMirror == mirror) {
      return existing;
    }
    final List<double> fractions = mirror
        ? PlateGeometry.defaultAreaFractions.reversed.toList(growable: false)
        : PlateGeometry.defaultAreaFractions;
    final PlateGeometry solved =
        PlateGeometry.forSize(size, areaFractions: fractions);
    _cached = solved;
    _cachedSize = size;
    _cachedMirror = mirror;
    return solved;
  }

  /// Drops the cached geometry.
  void clear() {
    _cached = null;
    _cachedSize = null;
    _cachedMirror = null;
  }
}
