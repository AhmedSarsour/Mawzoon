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

There is no `lib/main.dart` yet — this milestone is the domain core and its
state machine. Once the UI layer lands:

```bash
flutter devices
flutter run -d <device-id>
```

For the motion work, run in profile mode on a physical device. Debug-mode
frame timings on Impeller are not representative, and the animation budget
here is 120 FPS:

```bash
flutter run --profile -d <device-id>
```

## Project layout

```
lib/
  core/                     pure Dart, zero Flutter imports
    localization/           AppLanguage, LocalizedText (ar/en pairs)
    menu/                   PlateSegment, IngredientOption, MawzoonCatalog
    nutrition/              MacroProfile, PortionScale, NutritionalSummary,
                            BalanceBand
    validation/             allergen screening, dietary advisories
  features/
    plate_builder/          the Plate Architect: selection, sealed state
      domain/               PlateSelection, PlateBuilderState, events
      application/          PlateBuilderController (ValueNotifier)
    curated_menu/           the Curated Track: chef-balanced signature plates
      domain/               SignaturePlate
      data/                 SignaturePlateCatalog
    cart_checkout/          (empty — next milestone)
  ui_primitives/            (empty — next milestone)
test/                       mirrors lib/ one-for-one
```

`core/` importing anything from `package:flutter` is a design regression. It is
pure Dart so the nutrition engine can be tested, reasoned about and reused
without a widget tree in sight.
