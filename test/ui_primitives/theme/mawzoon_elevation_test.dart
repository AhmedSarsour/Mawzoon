import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/ui_primitives/theme/mawzoon_elevation.dart';

void main() {
  group('porcelain shadow', () {
    test('carries a cast layer and a hairline rim layer', () {
      final MawzoonElevation dark = MawzoonElevation.of(Brightness.dark);
      final MawzoonElevation light = MawzoonElevation.of(Brightness.light);
      expect(dark.porcelain, hasLength(2));
      expect(light.porcelain, hasLength(2));
    });

    test('is tuned differently for dark and light', () {
      final MawzoonElevation dark = MawzoonElevation.of(Brightness.dark);
      final MawzoonElevation light = MawzoonElevation.of(Brightness.light);
      expect(dark.porcelain.first.color, isNot(light.porcelain.first.color));
    });
  });

  group('ThemeExtension contract', () {
    test('copyWith replaces only the named level', () {
      final MawzoonElevation e = MawzoonElevation.of(Brightness.light);
      final MawzoonElevation tweaked =
          e.copyWith(porcelain: const <BoxShadow>[]);
      expect(tweaked.porcelain, isEmpty);
      expect(tweaked.platter, e.platter);
    });

    test('lerp interpolates porcelain rather than snapping it', () {
      final MawzoonElevation dark = MawzoonElevation.of(Brightness.dark);
      final MawzoonElevation light = MawzoonElevation.of(Brightness.light);
      final MawzoonElevation mid = dark.lerp(light, 0.5);
      expect(mid.porcelain.first.color, isNot(dark.porcelain.first.color));
      expect(mid.porcelain.first.color, isNot(light.porcelain.first.color));
    });

    test('lerp against a foreign extension returns this unchanged', () {
      final MawzoonElevation dark = MawzoonElevation.of(Brightness.dark);
      expect(dark.lerp(null, 0.5), same(dark));
    });
  });
}
