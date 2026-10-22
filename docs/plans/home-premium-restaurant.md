# Home screen → "Premium Restaurant" (Direction A), dark theme follows (Direction B)

## Context

The previous plan (`docs/plans/home-ceramic-overhaul.md`) shipped the ceramic plate, the
porcelain role, the empty-state hints, the photo slots, the counted-noun helper, the wide chef
cards and the sliding tab. Ahmed then supplied two approved references:
`assets/white_mode.png` (Direction A, the main target) and `assets/dark_mode.png` (Direction B,
the dark theme). The goal is to move the existing screen toward them **without touching logic,
navigation, state or workflows**. The screen should read as a chef-curated meal, not a
nutrition form.

**Decisions made (2026-09-24), do not re-litigate:**
1. **Photos: Ahmed shoots real ones.** Build the slots, the asset spec and the fallbacks now;
   the files arrive later. No AI or stock food photos in the app, because guests would be
   ordering from pictures of food the kitchen didn't make.
2. **Tall chef cards, like the reference.** This replaces the wide cards from K1. The thumb
   zone grows from 50% to 62% of the screen.
3. **Olive order button + olive selected tab.** Ember stops being the CTA colour on this
   screen. `ColorScheme.primary` stays ember, so the app's stock Material widgets don't change.

**Closes old C4:** reference A's plate is the *complete* state, and our existing per-macro
ring already blends to olive on balance. So keep the ring. Mark C4 "resolved, keep existing"
in the old plan file.

**Amendments (2026-09-25), after Ahmed reviewed M0 — supersede the K4/S2/D1 text below:**
4. **K4 is a carousel, not a rail.** One chef card centered and large; the previous/next cards
   peek at reduced scale on either side. Swiping (or a tap on a side card) animates that card
   to the center while it grows, and the old center card shrinks and moves aside. This replaces
   the plan's original "horizontal list of tall cards" — the sizing and selection behaviour in
   K4 below are superseded by this.
5. **S2 track switch: a capsule ~72% of the width, centred** (Ahmed: "capsule shaped, ~70%
   width, ~30% margin"). It keeps the sliding olive pill inside a capsule track; that matches
   reference A and the approved M0. An earlier draft of this amendment proposed two separate
   buttons and dropping `SlidingSegmentedPill`; that was a misreading and is withdrawn.
   D1's shared-pill extraction was **dropped on purpose**: `VolumeToggle` does not slide (it
   redraws per cell), so the two are not copies of one control. `VolumeToggle` only changed its
   selected fill to porcelain.

## Status (2026-09-25)
Shipped: A1, L1, K4 (carousel), K5, D1 (dock + volume pill colours), S2, D2, A2, P2, P1.
Not built: K6 (optional). P1's on-device `--profile` raster check (Verification 5) is **not
done yet**: it needs a real mid-range Android. Goldens for plate + order_home regenerated and
eyeballed. Suite: 1 analyzer error and 14 failing tests, both the known baseline.
Things a later session must know:
- `CuratedTrack` is a `PageView` (`viewportFraction` 0.64). Centred = chosen: `onPageChanged`
  reports it, and tapping the already-centred card reports it directly (first tap, since the
  plate opens on card 0 unloaded). It fits the height it is given (no scroll) up to 300.
- P2 also added `PlateCanvasPainter.compartmentLabelInk`: the richer wash pulled some label
  tones under 3:1 (the old wash already did for a couple), so the label ink is pulled toward
  `ink` only as far as needed.
- P1 is drawn inside `PlateCanvasPainter`, every spring frame, on purpose: images arrive
  decoded and downsized (`componentImagesFor(decodeWidth:)` wraps them in `ResizeImage`,
  220pt x DPR), so a frame costs three texture blits. Photo opacity = `model.fills[i]`. The
  band is the zone's bottom `bandFraction` (0.36), grown to fit the label text, capped at 0.6,
  in `colors.porcelain` at 0.94 x fill. The label moves into the band; its ink is
  `bandLabelInk` (every current tone already clears 3:1 there; the helper is a safety net).
  If the profile check fails, the fallback is a separate `CustomPaint` layer for photos that
  repaints only on data change.
- Still open (from D2): the checkout sheet's pay button is ember. Not changed.

Global rules still apply: brand hexes in `MawzoonBrand` are immutable, no new brand colours,
colours via `context.colors.*`, spacing via `context.space.*`, text via `MawzoonText` +
`context.type.*`.

## Changes (stable IDs)

Each change lists: before → after · why (the effect it leans on) · UX impact · Flutter
approach · complexity (S/M/L) · who builds it.

### M0 — Mockup artifact (gate) · S · Opus
- **Before:** only Ahmed's two reference PNGs.
- **After:** a published mockup with 4 frames: light curated, light architect, dark curated,
  and a **rejected** frame showing the heart icon, the leaf/paper decoration, the
  "الأكثر طلبًا" badge and the chef-hat tab icon, each with the reason it's rejected. Uses
  real tokens, real Arabic and RTL.
- **Why:** global rule: show the design before building it.
- **Approach:** HTML artifact. Photo areas use the gradient fallback, labelled as a photo slot.
- **Gate:** no UI code until Ahmed has seen M0.
- **Status:** approved by Ahmed (2026-09-25). Mockup: https://claude.ai/artifact/5gJFg9tNrn8849WjFxgPTZ

### A1 — Asset pipeline + photo spec · S · Sonnet
- **Before:** no `assets:` in `pubspec.yaml`. The two reference PNGs sit in `assets/`, where a
  folder-wide asset entry would bundle them into the app.
- **After:**
  - `git mv assets/*.png docs/design/references/`.
  - Create `assets/food/plates/` and `assets/food/components/`.
  - Declare both folders in `pubspec.yaml`. Each gets a `.gitkeep`; a README for them goes in
    `docs/design/photo-spec.md`.
  - Add `String? imageAsset` to `IngredientOption` in `lib/core/menu/ingredient_option.dart`.
    It's a plain String: core has no Flutter dependency.
  - `SignaturePlate.imageAsset` already exists.
- **Photo spec (`docs/design/photo-spec.md`):**
  - Plates: 1:1, 1200px, WebP, top-down, dark stoneware bowl, warm key light from the top
    left. That matches the plate painter's light direction.
  - Components: **cut-out on a transparent background**, WebP with alpha, 1024px, shot top-down.
    The cut-outs are what the future F1 animation needs.
  - Naming: `<id with dots→underscores>.webp`, e.g. `signature_ember_standard.webp`.
- **Why:** photos are the biggest single lift in the reference (appetite, picture-superiority
  effect). The asset contract has to exist before the files do.
- **Test:** every non-null `imageAsset` in both catalogues exists on disk and sits under a
  declared asset folder. This fails the build on a typo'd path instead of showing a broken
  image to a guest.

### A2 — Wire photos into cards and the plate · S · Sonnet
- **Before:** C3 built `TriPartitionPlate.componentImages`, but nothing fills it.
  `SignaturePlateCard` renders `Image.asset` without an `errorBuilder`.
- **After:**
  - `_PlateStage` (`order_home_screen.dart:248`) also receives `state.selection`. It builds
    `{segment: AssetImage(option.imageAsset!)}` for every chosen option that has a photo.
  - Every `Image.asset` gets `errorBuilder: (_, __, ___) => const _PlatePhotoFallback()`.
- **UX impact:** photos appear the moment files are dropped in, with no further code.

### L1 — Thumb zone 0.50 → 0.62 · S · Sonnet
- **Before:** `OrderHomeScreen.thumbZoneFraction = 0.5` (`order_home_screen.dart:85`). The
  tests hard-code `_phone.height / 2` (`order_home_screen_test.dart:140-190`).
- **After:**
  - Set `0.62`, and update the doc comment: the reason is tall photo cards, and the rarely used
    track switch is the only control at the top of the reach arc.
  - Rewrite the three thumb-zone tests to compute the midpoint as
    `_phone.height * (1 - OrderHomeScreen.thumbZoneFraction)`, not a hard-coded half.
  - Add a floor: the plate must stay at least 150pt tall on the 390×844 phone.
- **Why:** tall cards need the room. Thumb reach on a 6.1" phone covers roughly the bottom
  two-thirds (Hoober's thumb-zone research). The fraction stays a single tested constant.
- **UX impact:** the plate shrinks to about a third of the screen, which matches the reference.

### K4 — Tall chef card (replaces K1 layout) · M · Sonnet
- **Before:** a wide 288×136 row, with a 96px photo beside the text and pill badges.
- **After (reference A):**
  - Photo on top: full card width, 4:3, top corners only rounded.
  - Then the name (`sectionTitle`, 1 line), the tagline (`dishDescription`, `inkSoft`, 1 line),
    and one quiet meta line: `arabicKilocalories(kcal) · {g} غ بروتين`. In English:
    `{kcal} kcal · {g}g protein`.
  - Card: `porcelain` fill + `elevation.porcelain` + `surfaceRadius`.
  - Selected: the existing 1.5px `olive` ring.
  - Size: `cardWidth` about 200; `rowHeight` **measured** with an `IntrinsicHeight` probe,
    exactly as K1 did.
- **Removes** the K2 pill badges from the card. The reference uses a plain meta line, which
  cuts chrome on the card (fewer competing pills, less visual noise) and puts attention on the
  photo. **Keep** the `_MacroBadge` code only if something else uses it; otherwise delete it.
- **Keep:** the `Expanded` tagline pattern, `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)`,
  `TactileFeedbackWell` and the semantics label.
- **Why:** an editorial menu card. The photo is what the eye lands on first.
- **UX impact:** fewer cards visible at once (about 1.7 instead of 1.3 wide ones peeking),
  but each one persuades more.

### K5 — Honest "مميز" badge · S · Sonnet
- **After:** add `LocalizedText? badge` to `SignaturePlate`. Set it on
  `SignaturePlateCatalog.emberStandard` (documented as "the house default") to
  `LocalizedText(ar: 'مميز', en: "Chef's pick")`.
- **Rendering:** a small overlay pill, top-start of the photo. The fill is `MawzoonBrand.warmMaize`
  as a *fill* (allowed as a fill, like other raw brand values), with a text colour chosen by
  `bestInkOn`.
- **Rejected:** "الأكثر طلبًا" (most ordered) from reference B. It would be a claim with no data
  behind it (fake social proof).
- **Why:** a single highlight makes one plate stand out (Von Restorff effect) and gives the
  guest a default to follow (default effect). One badge only.

### K6 — Photo thumbs on the architect's ingredient chips · S · Sonnet (optional, last)
- **After:** `IngredientChip` (`plate_architect_track.dart:270`) shows a 40px round thumbnail
  from `option.imageAsset` when there is one. It shows nothing when there isn't: no
  placeholder circle, which would be clutter.

### S2 — Olive selected tab · S · Sonnet
- **Before:** S1's sliding pill is porcelain.
- **After:** the pill is filled `olive`, the active label is `onOlive` at w700, and the
  inactive label stays `inkFaint`. **No chef-hat icon:** an icon on the selected half only
  would shift that label's position each time the selection changes.
- **Risk to watch in M0:** an olive tab and an olive CTA compete for attention. The brief ranks
  secondary controls last. If M0 shows the tab winning, drop the tab to `olive` at 85% alpha
  or to a porcelain pill with an olive label.

### D1 — Dock surface + shared segmented pill · M · Sonnet
- **Before:** the dock card uses `structure`. `VolumeToggle` (`volume_toggle.dart`) and
  `_TrackSwitch` are two separate segmented controls.
- **After:**
  - Extract `SlidingSegmentedPill<T>` into `lib/ui_primitives/controls/`. It takes `values`,
    `selected`, `onChanged`, `labelBuilder`, `selectedFill` and `selectedInk`. This is the
    second copy of the same control, so it's the extraction point (global rule).
  - `_TrackSwitch` uses it with olive.
  - `VolumeToggle` uses it with a porcelain pill + `ink`, as in reference A's dock.
  - The dock card uses `porcelain` + `elevation.porcelain`.
- **Keep:** the `VolumeToggle` public API, its nominal-kcal line, and the reduced-motion
  zero-duration behaviour. S1's three tests move onto the primitive, and the screen keeps one
  smoke test.

### D2 — Olive order button · S · Sonnet
- **Before:** `BalanceLockAction` (`macro_capsule.dart:266`) turns `ember` when ready.
- **After:** ready fill is `olive`, and the label and price use `onOlive`. `BalanceBadge`
  needs a variant that still shows on olive: an `onOlive` check inside a thin `onOlive`
  ring, as in reference A.
- **Don't touch:** the spring overshoot, the inert-until-ready behaviour, and
  `ColorScheme.primary`.
- **Open item, not in scope:** the checkout sheet's pay button is still ember. Flag it to
  Ahmed after shipping; don't change it silently.

### P2 — Richer filled compartments without photos · S · Sonnet
- **Before:** the filled wash alpha is `0.10 + 0.09 * fill` (`plate_canvas_painter.dart`,
  `_paintCompartments`). It reads faint next to reference B.
- **After:** dark `0.22 + 0.14 * fill`, light `0.14 + 0.10 * fill`.
- **Test:** the label's tone on the composited fill (use `Color.alphaBlend` over the well tone)
  must still clear 3:1.

### P1 — Plate compartments with photos · M · **Opus**
- **After:** when a compartment has an image:
  - Draw the photo clipped to the zone, then a porcelain **label band** over the bottom ~36%
    of the zone (zone ∩ rect). The grams/kcal label sits centred in that band, as in
    reference A.
  - The photo's opacity follows `model.fills[i]`, so the food fades in with the existing
    spring, not a new tween.
  - Without an image, today's rendering stays exactly as it is.
- **Why Opus:**
  - Perf. `PlateCanvasPainter` repaints on every spring frame, so decide deliberately between
    drawing images there (cheap blits) and a middle layer that repaints only on data change.
    Check with the raster thread in `--profile`.
  - Correctness. The band must mirror correctly under RTL, stay legible at 2.0× text, and not
    break the C2 empty-state path.
  - Tests need real decoding (`runAsync` + `Future.delayed`; see C3 notes in the old plan).

### F1 — Future, not in this plan: food lands on the plate
Ahmed's note: animated food in the header. Recorded so the choices made now keep it possible:
- **Where it earns its place:** tapping a chef card, where each component flies from the card
  photo into its compartment. The animation shows where something came from, marks a peak
  moment and confirms the action: all three reasons animation is allowed here.
- **It needs:** the component cut-outs from A1's spec, and a `Hero`-style overlay flight from
  the card rect to `zoneCentroids`.
- **It must:** respect reduced motion (skip the flight, just fill), and never block the next tap.
- It gets its own plan and should be built on Opus.

## Rejected (shown in M0's rejected frame)
- **Heart / favourite icon:** there is no favourites feature, so a heart that does nothing is a
  broken promise, and building favourites would change business logic.
- **Leaf line-art + paper texture:** decoration that competes with the food, against "no
  clutter".
- **"الأكثر طلبًا":** see K5.
- **Chef-hat icon on the selected tab:** see S2.

## Execution order
M0 (gate) → A1 → L1 → K4 → K5 → D1 → S2 → D2 → A2 → P2 → P1 (Opus) → K6.
Commit after each ID, but only if Ahmed asks for commits.

## Edge cases
1. **RTL/LTR:** photo badge corner, meta-line order, pill slide direction and label band all
   mirror. Test both `AppLanguage`s.
2. **Dark theme:** every change is visible in `order_curated_dark` and `order_architect_dark`.
   The olive CTA's `onOlive` label must clear 4.5:1 (it's already tested).
3. **Text scale 1.3× and 2.0×:** the tall card keeps its clamp. The name and tagline ellipsis.
   The meta line ellipsizes and never wraps into the photo.
4. **320×640 phone:** at 62% the plate gets about 240pt minus the header. The L1 floor must
   hold, or the plate aspect shrinks gracefully. The "survives a small phone" test must stay
   green.
5. **A missing photo file:** `errorBuilder` shows the fallback, never a broken-image icon, and
   the A1 test catches a wrong path in CI.
6. **Half the photos shipped:** cards and compartments mix photo and fallback without layout
   shift. The photo box has a fixed aspect either way.
7. **A large image file:** decode at display size (`cacheWidth` = box width × DPR) so twenty
   1200px WebPs don't blow memory.
8. **Reduced motion:** the pills snap, P1's photo fade snaps to the final opacity, and F1 is
   skipped.
9. **Balance lock on the olive CTA:** the spring still fires once on the crossing only. It must
   not re-fire when a component is swapped on a complete plate (the existing test).
10. **Selected card that has the badge:** the olive ring and the badge must not overlap.
11. **Architect ↔ curated switch:** the photo map updates from `state.selection`. Clearing a
    segment removes its photo and restores the C2 watermark.
12. **Contrast:** extend `mawzoon_colors_test.dart` with `onOlive`/olive (already there), the
    badge ink on `warmMaize`, and the label ink on the P1 porcelain band.

## Acceptance criteria (proposed)
- `flutter analyze`: still exactly **1 error** (the pre-existing `test/widget_test.dart`).
- `flutter test --reporter=failures-only`: still exactly the **14 pre-existing failures**
  (13 goldens in checkout/kitchen/manager + `widget_test.dart`), and nothing new.
- New tests: asset paths exist (A1); thumb-zone tests use the constant (L1); tall card at
  1.0×/2.0× with no overflow (K4); badge renders only on `emberStandard` (K5); segmented
  primitive: retarget, reduced motion and semantics (D1); CTA is olive when ready (D2); P1
  draws an image and a band when a photo resolves, and neither without one. **Each proven
  non-vacuous: break it, watch it fail, restore it, and say so.**
- Goldens: plate + order_home regenerated **and eyeballed** against the references (light,
  dark, English).

## Execution notes (for the implementing model)
- **First step of execution:** copy this file to
  `docs/plans/home-premium-restaurant.md`. Plans live in `docs/plans/`, and that repo copy is
  the one to update as IDs ship. Mark old-plan C4 "resolved: keep existing ring (reference A
  = complete state)".
- **Read before assuming:**
  - `SignaturePlateCard`, `_MacroBadges` and `_PlatePhotoFallback` in
    `lib/features/curated_menu/presentation/curated_track.dart`.
  - `_TrackSwitch` (`order_home_screen.dart:~395`), `VolumeToggle`, and `BalanceLockAction` /
    `BalanceBadge` (`macro_capsule.dart:266-431`).
  - `PlateBuilderState.selection` (`plate_builder_state.dart:73`), which gives the chosen
    options for A2. `SegmentContribution` does **not** carry the option, so don't look for
    it there.
- **Reuse, don't rebuild:** `arabicKilocalories` (`lib/core/localization/arabic_count.dart`),
  `colors.porcelain`/`kcalTint`, `elevation.porcelain`, `bestInkOn`, `TactileFeedbackWell`
  (it already emits `Semantics(selected:)`), `MediaQuery.withClampedTextScaling`, and
  `PlateGeometry.zoneCentroids`.
- **ThemeExtension footgun:** any new colour field goes in the ctor, both factories,
  `copyWith`, `lerp`, `==` and `hashCode`, or theme animation snaps. This plan shouldn't need
  any new colour.
- **Image decode in widget tests** needs `tester.runAsync` + a real `Future.delayed`. Extra
  pumps are not enough.
- **Golden fonts are tofu boxes**, so goldens check shape and colour, not type. Check text
  fit with `IntrinsicHeight` probes and the 2.0× test instead.
- **Isolating failures:** `git stash push -q -- <each path written out>`. In zsh, a single
  variable holding several paths is not split, so write every path out.
- Don't bulk-upgrade packages. Pin any new package with a comment; none should be needed.
- Update the repo plan file in the same pass as each ID ships.

## Verification
1. `flutter analyze` and count errors: expect 1, the pre-existing one.
2. Targeted tests after each ID:
   `flutter test test/features/order_home test/features/curated_menu test/ui_primitives --reporter=failures-only`.
3. At the end, run the full `flutter test --reporter=failures-only` and diff the failing list
   against the 14 known failures.
4. Run `--update-goldens` for `test/ui_primitives/plate` and `test/features/order_home`, then
   Read each PNG and compare it against `docs/design/references/*`.
5. P1 only: `flutter run --profile` on a mid-range Android. Toggle compartments and check the
   raster thread stays under 8ms/frame.
6. Drop one real photo into `assets/food/plates/` before closing A2. That tests the end-to-end
   path with a real file, not only the fallback.
