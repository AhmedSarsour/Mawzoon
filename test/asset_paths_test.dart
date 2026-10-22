import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/features/curated_menu/data/signature_plate_catalog.dart';

/// Every non-null `imageAsset` in either catalogue must exist on disk, under
/// a folder declared in `pubspec.yaml`. This fails the build on a typo'd
/// path instead of showing a guest a broken image (A1).
void main() {
  test('signature plate imageAsset paths exist under assets/food/plates/', () {
    for (final plate in SignaturePlateCatalog.all) {
      final String? asset = plate.imageAsset;
      if (asset == null) continue;
      expect(
        asset.startsWith('assets/food/plates/'),
        isTrue,
        reason: '${plate.id}: $asset is not under assets/food/plates/',
      );
      expect(
        File(asset).existsSync(),
        isTrue,
        reason: '${plate.id}: $asset does not exist on disk',
      );
    }
  });

  test(
    'ingredient imageAsset paths exist under assets/food/components/',
    () {
      for (final option in MawzoonCatalog.all) {
        final String? asset = option.imageAsset;
        if (asset == null) continue;
        expect(
          asset.startsWith('assets/food/components/'),
          isTrue,
          reason: '${option.id}: $asset is not under assets/food/components/',
        );
        expect(
          File(asset).existsSync(),
          isTrue,
          reason: '${option.id}: $asset does not exist on disk',
        );
      }
    },
  );

  // The spec's naming rule (id, dots to underscores) is what lets a photo be
  // dropped in without hunting for its filename. Enforced, not remembered.
  test('ingredient photos follow the <id, dots→underscores>.webp rule', () {
    for (final option in MawzoonCatalog.all) {
      final String? asset = option.imageAsset;
      if (asset == null) continue;
      expect(
        asset,
        'assets/food/components/${option.id.replaceAll('.', '_')}.webp',
        reason: '${option.id} is pointed at a misnamed file',
      );
    }
  });
}
