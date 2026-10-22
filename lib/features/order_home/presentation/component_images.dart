import 'package:flutter/widgets.dart';

import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/plate_segment.dart';
import '../../plate_builder/domain/plate_selection.dart';

/// The photo for each chosen component that has one, keyed by compartment.
///
/// `null` when nothing has a photo, so the plate takes today's no-photo path
/// without allocating a map. A segment with no photo is simply absent; the
/// plate falls back to the tone wash for that compartment alone (A2).
///
/// [decodeWidth] is in physical pixels. The photos ship at 1200px, but a
/// compartment is never more than about half the plate wide: decoding at
/// full size would keep ~5.8MB per photo in memory for nothing.
Map<PlateSegment, ImageProvider>? componentImagesFor(
  PlateSelection selection, {
  int? decodeWidth,
}) {
  final Map<PlateSegment, ImageProvider> images =
      <PlateSegment, ImageProvider>{};
  final List<IngredientOption?> chosen = <IngredientOption?>[
    selection.protein,
    selection.carb,
    selection.fiber,
  ];
  for (final IngredientOption? option in chosen) {
    final String? asset = option?.imageAsset;
    if (option != null && asset != null) {
      images[option.segment] = ResizeImage.resizeIfNeeded(
        decodeWidth,
        null,
        AssetImage(asset),
      );
    }
  }
  return images.isEmpty ? null : images;
}
