# موزون · Mawzoon

Tasty & balanced meals.

The ordering app for Mawzoon — a restaurant built on one idea: a plate can be
calorie- and macro-precise *and* taste like something you'd actually crave.
Air-fried, not deep-fried. Flame-seared, not steamed into submission.

## The tri-partitioned plate

Every meal is three compartments on one elongated platter:

| Compartment | Arabic | Options |
|---|---|---|
| Protein | البروتين | 6 |
| Smart Carb | الكربوهيدرات الذكية | 6 |
| Vital Fiber | الألياف الحيوية | 2 |

72 buildable plates, every one of them costed and counted.

That structure is the product's whole mental model. It orders the physical
tray, the three arcs of the macro ring, the three steps of the builder and the
three rows of the ingredient carousel.

## Two ways to order

A hungry guest is a cognitively depleted guest, so there are exactly two paths
and no third:

- **The Curated Track** — six chef-balanced signature plates, one tap each,
  with a binary volume toggle: Standard Balance (~550 kcal) or Athletic Load
  (~780 kcal). No sliders, no configuration.
- **The Plate Architect** — pick one component per compartment on a single
  screen. Macros update live; nothing is gated behind a "next" button.

## Anti-guilt by construction

Calories are framed as fuel, never as a budget being overspent. The domain
layer enforces this rather than leaving it to a designer's discretion: a plate
is described as `lighter`, `balanced` or `heartier` relative to the house band,
and all three readings are written in the same neutral register. There is no
failure state for a plate's energy. The *only* hard stop in the whole
validation layer is a declared allergen, which is a safety matter.

## Precision

Energy is never stored, only derived — a nutrition panel and a macro capsule
cannot disagree because there is exactly one source of truth. The engine uses
the modified Atwater system (protein 4, net carbohydrate 4, fibre 2, fat
9 kcal/g) rather than the naive 4/4/9 shortcut, which on a high-fibre plate is
a 25–30 kcal difference — exactly the margin a guest tracking macros notices.

Every one of the six signature plates is asserted by test to land inside its
house energy band at *both* portion scales. A chef's plate that drifts out of
band fails the build instead of reaching a guest.

Glycemic load is computed the published way — each component's glycemic index
weighted by the digestible carbohydrate it actually contributes — and banded
against the published meal-level thresholds rather than thresholds fitted to
this menu. A plate's protein, fat and fibre do blunt its glycemic response, so
a bounded adjustment is reported too, clearly labelled as the coarse
directional heuristic it is, with the published figure always kept beside it.

## Status

| Layer | State |
|---|---|
| `core/` — nutrition engine, catalogue, validation | done, tested |
| `features/plate_builder/` — sealed state machine, controller | done, tested |
| `features/curated_menu/` — signature plates | done, tested |
| `core/` — glycemic engine | done, tested |
| `ui_primitives/` — design tokens, AppTheme, MawzoonText | done, tested |
| `ui_primitives/` — tri-partition canvas, macro capsule | next |
| `features/cart_checkout/` | not started |

319 tests, `flutter analyze` clean.

## Getting started

See [SETUP.md](SETUP.md). Short version:

```bash
flutter pub get
flutter analyze
flutter test
```

The domain layer is pure Dart with no Flutter import, so the full suite runs
with no device, emulator or platform shell.

## Bilingual from the ground up

Arabic is the primary language, not a translation layer bolted onto an English
original. Every user-facing noun in the domain is a `LocalizedText` carrying
both renderings, and a test asserts that every catalogue entry has real Arabic
script in both its name and its description — an English string sitting in an
`ar` field cannot pass.
