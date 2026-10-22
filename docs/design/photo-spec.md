# Food photo spec

Two asset folders, declared in `pubspec.yaml`:

- `assets/food/plates/` — signature-plate card photos (`SignaturePlate.imageAsset`).
- `assets/food/components/` — single-ingredient cut-outs (`IngredientOption.imageAsset`),
  for the architect's ingredient chips (K6) and the future plate-fill animation (F1).

## Plates (`assets/food/plates/`)

- 1:1 square, 1200×1200px, WebP.
- Shot top-down, in the dark stoneware bowl the app already renders.
- Warm key light from the top-left — matches `PlateCanvasPainter`'s light direction. A photo
  lit from elsewhere will look wrong next to the painted plate rim.

## Components (`assets/food/components/`)

- **Cut-out on a transparent background.** WebP with alpha, 1024×1024px.
- Shot top-down, same key light as the plates.
- No baked-in shadow: the plate painter draws its own (bottom-right, matching the top-left
  light). A shadow shot on white would show as a gray smudge on the tinted compartment.
- Current files are AI placeholders (2026-09-26), to be replaced by real photos; same names,
  no code change.
- The transparency is what the future F1 "food flies onto the plate" animation needs — don't
  ship these with a background and plan to crop later.

## Naming

`<id, dots→underscores>.webp`. The id is the option/plate's own `id` field.

Examples:
- `SignaturePlateCatalog.emberStandard` (id `signature.ember_standard`) →
  `signature_ember_standard.webp`
- `MawzoonCatalog.herbGrilledBreast` (id `protein.herb_grilled_breast`) →
  `protein_herb_grilled_breast.webp`

## Dropping in a file

1. Export at the size above, WebP.
2. Rename to the pattern above.
3. Drop into the matching folder, then set `imageAsset` on the catalog entry (it is `null`
   until you do, so a file alone shows nothing).
4. Run `flutter test test/asset_paths_test.dart` (or the full suite) — it fails the build if a
   declared `imageAsset` path doesn't exist on disk, instead of showing a guest a broken image.
