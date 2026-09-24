# Setting up Mawzoon locally

This repository is deliberately **source-only**. It contains `pubspec.yaml`,
`lib/` and `test/` — no `android/`, `ios/`, `web/` or other generated platform
runners. Those are machine- and toolchain-specific, so they are generated once
on your own machine rather than committed.

Everything below assumes the Flutter SDK is already on your `PATH`.

## 1. Verify the toolchain

```bash
flutter --version
```

The project targets **Flutter ≥ 3.22 / Dart ≥ 3.4**. It is developed and
verified against Flutter 3.47.5 (Dart 3.13.4). Dart 3 is a hard requirement:
the domain layer is built on sealed classes and exhaustive switch expressions.

## 2. Resolve dependencies

```bash
flutter pub get
```

`pubspec.lock` is committed so the resolved dependency set is reproducible. If
your local Flutter is older than the one that produced it and resolution
fails, delete the lockfile and let pub re-resolve:

```bash
rm pubspec.lock && flutter pub get
```

## 3. Run the checks — before generating anything

The whole domain layer is pure Dart with no UI dependency, so the test suite
runs without a device, an emulator or a platform shell:

```bash
flutter analyze   # expects: No issues found!
flutter test      # expects: All tests passed!
```

Doing this *first* confirms the checkout is sound before any generated files
enter the picture.

## 4. Generate the platform runners

Run `flutter create` **inside the existing directory**. The trailing `.`
matters: it fills in the missing platform folders without touching
`pubspec.yaml`, `lib/` or `test/`.

```bash
flutter create . \
  --project-name mawzoon \
  --org com.mawzoon \
  --platforms=android,ios
```

Add `,web,macos` if you want those targets too. The generated directories are
listed in `.gitignore` and stay untracked.

If `flutter create` reports that it would overwrite a file you care about,
stop and check the diff rather than forcing it.

Then add what the post-meal notification needs (boot receiver, desugaring,
iOS notification delegate). Safe to run twice; it fails loudly if a template
has changed:

```bash
dart run tool/patch_platforms.dart
```

Without this step the app still works: the post-meal question waits on the
home screen instead of arriving as a notification.

## 5. Arabic typography on device

The app is bilingual with Arabic as the primary language. Two things to get
right when the UI layer lands:

- **Fonts.** Latin metrics use Plus Jakarta Sans, Arabic uses IBM Plex Sans
  Arabic, both pulled through `google_fonts` at runtime on first launch. If
  you want them bundled offline instead, drop the `.ttf` files into
  `assets/fonts/` and declare them in `pubspec.yaml` under `flutter: fonts:`.
- **Diacritics.** Arabic needs `height: 1.8` and an explicit `StrutStyle`, or
  harakat clip against the line box. Test with fully-vocalised text, not just
  unvocalised menu copy — unvocalised Arabic will look fine and hide the bug.

## 6. Running the app

There are three entry points, one per device and audience. They are separate
targets rather than routes on purpose: a guest must not be able to deep-link
into the kitchen board or the back office.

| Target | Command | Who uses it |
| --- | --- | --- |
| Guest app | `flutter run` | Guests ordering on a phone |
| Kitchen display | `flutter run -t lib/main_kitchen.dart` | The line, on a landscape tablet |
| Back office | `flutter run -t lib/main_manager.dart` | Managers: stock, sold-out rails, recipe calibration |

```bash
flutter devices
flutter run -d <device-id>                              # guest
flutter run -d <device-id> -t lib/main_kitchen.dart     # kitchen
flutter run -d <device-id> -t lib/main_manager.dart     # manager
```

The quickest way to see all three without an emulator is desktop or web:
`flutter create . --platforms=macos` (or `web`), then `flutter run -d macos`.

For the motion work, run in profile mode on a physical device. Debug-mode
frame timings on Impeller are not representative, and the animation budget
here is 120 FPS:

```bash
flutter run --profile -d <device-id>
```

### Goldens

Golden images are tagged `golden` and were generated on Linux. Font
rasterisation differs between operating systems, so on macOS or Windows they
may report pixel differences that are not bugs. Either skip them or regenerate
them locally, then look at the new images before committing:

```bash
flutter test -x golden          # everything except pixel comparisons
flutter test --update-goldens   # regenerate on this machine
```

## Project layout

```
lib/
  core/                       pure Dart, zero Flutter imports
    feedback/                 HapticCue (named by intent)
    localization/             AppLanguage, LocalizedText (ar/en pairs)
    measure/                  Quantity: integer g / ml / pieces
    menu/                     IngredientOption, MawzoonCatalog, RecipeBook,
                              RecipeCalibration, StockStatus, MenuAvailability
    nutrition/                MacroProfile, PortionScale, NutritionalSummary
    pricing/                  Money (integer minor units)
    validation/               allergen screening, dietary advisories
  features/
    plate_builder/            the Plate Architect: selection, sealed state
    curated_menu/             chef-balanced signature plates
    order_home/               the dual-track ordering screen
    cart_checkout/            order draft, two-tap checkout sheet
    kitchen_display/          KDS: station tickets, urgency, packaging queue
    manager_suite/            raw store, recipes (BOM), inventory ledger,
                              calibrator and inventory screens
  ui_primitives/              theme, motion, plate canvas, controls,
                              MenuScope (the menu handed down the tree)
  main.dart                   guest entry point
  main_kitchen.dart           kitchen entry point
  main_manager.dart           back-office entry point
test/                         mirrors lib/
```

`core/` importing anything from `package:flutter` is a design regression. It is
pure Dart so the nutrition engine, the store and the calibration rules can be
tested, reasoned about and reused without a widget tree in sight.
