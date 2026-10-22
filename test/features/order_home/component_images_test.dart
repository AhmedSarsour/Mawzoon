import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/order_home/presentation/component_images.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';

void main() {
  test('null when nothing chosen has a photo', () {
    // Options with no photo yet: the painted-wash fallback path.
    const PlateSelection s = PlateSelection(
      protein: MawzoonCatalog.smashedLeanBeef,
      carb: MawzoonCatalog.sweetPotatoWedges,
      scale: PortionScale.standardBalance,
    );
    expect(componentImagesFor(s), isNull);
  });

  test('half the photos shipped: only the photographed segment is mapped', () {
    const PlateSelection s = PlateSelection(
      protein: MawzoonCatalog.herbGrilledBreast,
      carb: MawzoonCatalog.sweetPotatoWedges,
      scale: PortionScale.standardBalance,
    );
    final Map<PlateSegment, ImageProvider>? images = componentImagesFor(s);
    expect(images?.keys, <PlateSegment>[PlateSegment.protein]);
    expect(
      images![PlateSegment.protein],
      const AssetImage(
        'assets/food/components/protein_herb_grilled_breast.webp',
      ),
    );
  });

  test('decodes at the requested width, not the file size', () {
    const PlateSelection s = PlateSelection(
      protein: MawzoonCatalog.herbGrilledBreast,
      scale: PortionScale.standardBalance,
    );
    final ImageProvider? p =
        componentImagesFor(s, decodeWidth: 660)?[PlateSegment.protein];
    expect(p, isA<ResizeImage>());
    expect((p! as ResizeImage).width, 660);
  });

  test('clearing a segment removes its photo', () {
    const PlateSelection s = PlateSelection(
      protein: null,
      carb: MawzoonCatalog.sweetPotatoWedges,
      scale: PortionScale.standardBalance,
    );
    expect(componentImagesFor(s), isNull);
  });
}
