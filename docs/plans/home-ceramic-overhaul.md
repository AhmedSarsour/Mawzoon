# Home overhaul — ceramic platter, editorial chef cards, sliding tabs

Status: **closed. All IDs shipped; C4 resolved as "keep existing ring".** K1/K2's card
layout and S1's pill colour are superseded by `docs/plans/home-premium-restaurant.md`.
Mockup:
https://claude.ai/artifact/PXH4tpZB3YoaGA424esRoo (frames 1–3 = build this; frame 4 = the
literal spec, rejected).

Source brief: a pasted "luxury culinary" spec (60-30-10, ceramic plate, horizontal chef
cards, sliding segmented control). This plan adapts it to the existing theme system rather
than pasting raw hexes into widgets.

## Decisions already made (do not re-litigate)

- **Ahmed: use the original colours for now** (may study new ones later). No new brand
  hexes; every new tone is derived from existing `MawzoonColors` roles.
- **Brand hexes stay.** `MawzoonBrand` is documented as immutable. The spec's olive
  `#4E7A58`, terracotta `#C85A32`, maize `#DCA038`, linen `#F9F8F5` are NOT adopted.
- **Accents as text use the AA-tuned `MawzoonColors` roles** (`ember`, `olive`, `protein`,
  `carb`). Raw brand values only for fills/marks (halo, food tints, CTA fill in dark).
  Spec raw ember on linen = 3.16:1, maize = 2.17:1 — both fail AA.
- **Fonts stay** IBM Plex Sans Arabic / Plus Jakarta Sans (spec said Cairo). Sizes/weights
  from the spec map onto existing `context.type` styles; add a style only if none fits.
- **Units:** `45 غ بروتين`, not `45g بروتين` (Latin unit inside Arabic breaks bidi).
- **Layout contract unchanged:** plate in the top half, all controls in the bottom
  `thumbZoneFraction`. Existing test asserts it.
- **Open question for Ahmed (blocks C3 copy only):** plate pill copy. Spec says
  `اختر البروتين / اختر الكارب / اختر الألياف`; code's term is `الكربوهيدرات الذكية`.
  Global rule: never rename a user-facing term without asking. Default until answered:
  spec copy, stored as a new `LocalizedText platePrompt` on `PlateSegment`.

## Changes (stable IDs)

### T1 — `porcelain` colour role — ✅ SHIPPED
Added `porcelain` + `kcalTint` to `MawzoonColors` (ctor, both factories, `copyWith`,
`lerp`, `==`, `hashCode`) and `porcelain` to `MawzoonElevation` (cast shadow + a 0.5px
`spreadRadius` hairline-rim `BoxShadow`, no blur, standing in for the spec's border).
**Dark `kcalTint` changed from the spec's `#2C302D`** — the new contrast test caught
`inkFaint` on it at 4.10:1 (below AA 4.5:1); moved to `#202422` (4.81:1). Light stayed
`#F4EEE5` as specced.
Tests: extended `mawzoon_colors_test.dart` (`porcelain`/`kcalTint` added to the surfaces
every text role is checked against — this is what caught the contrast bug above — plus
targeted `copyWith`/`lerp` tests) and added `mawzoon_elevation_test.dart` (new file, no
prior coverage existed). `lerp` tests proven non-vacuous: reverted the two fields to a
snap-assign, watched both fail, restored, reran green.

### T2 — Ambient glow — ✅ ALREADY EXISTS, no change made
Checked first, per this note's own instruction. `AmbientGlow`
(`lib/ui_primitives/motion/ambient_glow.dart`) is already exactly this: a 16s-breathing
radial gradient centred behind the plate, radius 62% of width, wired in via
`TriPartitionPlate` → `AmbientGlow(color: colors.ember)`. It fades to alpha 0 rather than
to an opaque `canvas` hex, which reads the same over the canvas and needs no new colour
literal (`#F2ECE1`/`#1A1C1A` were never adopted, per "use the original colours").
`PlateCanvasPainter.AmbientWarmthPainter` is dead code — unused, and the layer-count
tests (`tri_partition_plate_test.dart`) already assert it does *not* appear in the tree.
Left as-is; not this plan's job to delete unrelated dead code.

### C1 — Ceramic platter painting — ✅ SHIPPED
What exists now (read it before touching the plate):
- `PlateGeometry.dividers` — the 2 shared edges as open paths, left→right, same bow
  as the zones. Tested: `each groove runs exactly along the edge two zones share`.
- `PlateCeramicPainter` (static layer, own `RepaintBoundary` in `TriPartitionPlate`):
  cast shadow, lip glaze (ring filled + stroked `lipOverhang`), well gradient, rim
  depth shadow/highlight, lip→well hairline. Tones come from private `_CeramicTones`
  (derived from `structure`, `structureElevated`, `ink`) — add new ceramic tones there.
- `PlateCanvasPainter` no longer paints the dish; empty zones get no wash/outline;
  `_paintGrooves` draws dark + light lines over the compartments, under the ring.
- Layer-count tests now expect 2 boundaries (3 with ambient).
- Perf: blurs live only in the static layer. Don't add `MaskFilter` to
  `PlateCanvasPainter` — it repaints every spring frame.

Original brief, kept for reference:
In `PlateCanvasPainter.paint` (`lib/ui_primitives/plate/plate_canvas_painter.dart`):
1. Outer lip: cast shadow below (`drawShadow` → replace with blurred path shadow offset
   y+12), glaze = vertical linear gradient (light `#FFFFFF`→`#EAE4DA`).
2. Well: inset path (`g.ring` / inner dish — verify which path `PlateGeometry` exposes),
   gradient darker at top edge (light falls from above).
3. Inner-rim depth: blurred stroke along the well, clipped to it, offset y+3.
4. Dividers → debossed grooves: same S-curve path drawn twice — dark line
   (`rgba(90,70,40,.22)`) then light line (`rgba(255,255,255,.9)`) offset ~1.2px. No
   black lines.
5. Keep the area-true split from `PlateGeometry` untouched. Do not change geometry math.
*Why Opus:* painter perf (blur `MaskFilter` per frame is expensive — cache into a
`Picture` or only repaint the static layer when size/brightness changes) and it's easy
to break the existing golden and animation model subtly.

### C2 — Empty-state watermarks + pill labels — ✅ SHIPPED
Copy question sidestepped, not answered: `PlateSegment.invitation` already existed with
real Arabic copy (`اختر مصدر البروتين` etc.) for exactly this purpose, so C2 uses that
field verbatim instead of adding a new `platePrompt`/spec copy. No user-facing term was
renamed or introduced. The spec-vs-code wording question (`اختر الكارب` vs the fuller
existing phrasing) is still open if Ahmed wants to revisit the *wording* later, but it no
longer blocks anything.
- `PlateCanvasData.emptyPrompts` (new field, `List<String>` len 3): `tri_partition_plate.dart`
  fills it from `segment.invitation.resolve(appLanguage)` for unfilled segments.
- `_PlateSilhouettes` (`plate_canvas_painter.dart`): 3 fixed unit-scale `Path`s (protein
  cut, grain cluster, leaf), picked by ordinal, scaled to ~42% of the zone's width (capped
  34px), alpha 0.07 dark / 0.10 light via `colors.ink`.
- `_paintPromptPill`: porcelain RRect (T1's `colors.porcelain` + `colors.hairline` stroke)
  under the compartment name, text via `TextPainter`. **Hides itself, doesn't shrink**,
  when `pillWidth > room` — this is edge case 4 in practice: at the app's usual widths the
  vital-fibre third (26% of the tray) is often too narrow for its own longer invitation
  string, so its pill legitimately won't show while protein/carb's do. Not a bug.
- Reuses the existing `isFilled` hard-cut (same as the wash/outline already did) rather
  than a new tween, per this plan's own note.
- Tests: `tri_partition_plate_test.dart` new group "empty-compartment prompt pill" —
  wide layout draws an `rrect` (`paints` matcher), narrow layout doesn't, filled plate
  never does. All 3 proven non-vacuous (disabled the width guard / short-circuited the
  paint method, watched each fail, restored, reran green).

### C3 — Filled state food imagery — ✅ SHIPPED
`PlateCanvasData.compartmentImages` takes `List<ui.Image?>`, not `ImageProvider?` — a
`CustomPainter` paints synchronously and can't await a decode, so the decode has to
happen above the painter. The public knob is on the widget instead:
`TriPartitionPlate.componentImages` (`Map<PlateSegment, ImageProvider>?`, defaults
`null` — no behaviour change for every existing caller). `_TriPartitionPlateState`
resolves each provider via `ImageStream`/`ImageStreamListener` (tracked per segment so a
provider swap or dispose unsubscribes the right one, not a stale one) and hands the
decoded `ui.Image`s down through `_data()`.
Painter: `_paintCompartmentImage` clips to the zone, `paintImage(..., fit: BoxFit.cover)`,
then a 6% black wash — replaces the tone wash only; the definition stroke stays either way.
No asset files added, per the instruction — `componentImages` is unset everywhere in the
app today, so this ships as dead-until-wired plumbing.
Test: `tri_partition_plate_test.dart` group "component imagery (C3)", using an inlined
1×1 PNG (`MemoryImage`) since no test asset exists. **Real image decode needs the test's
`runAsync` zone plus a real wall-clock wait** (`Future.delayed` before the next `pump`) —
without it the `ImageStreamListener` never fires inside `flutter test`'s fake-async zone
and the test hangs/fails silently for the wrong reason; do not "fix" this by shortening
or removing that delay if a future test here looks slow. Proven non-vacuous: forced the
image branch off, watched the paint-call assertion fail, restored, reran green.

### C4 — Perimeter balance halo — ✅ RESOLVED: keep the existing ring
The ring already exists: `PlateCanvasPainter._paintRing` draws one arc per filled
macro, sized by **energy share**, in macro tones, blending to olive on balance lock
(`BalanceLockChoreography`). Ahmed's approved reference (`docs/design/references/
white_mode.png`) shows the *complete* plate, which is exactly the existing ring after
it blends to olive — so nothing to build. Superseded by
`docs/plans/home-premium-restaurant.md`.
Note: the tray split is **0.40/0.34/0.26** (`PlateGeometry.defaultAreaFractions`),
not the brief's 45/35/20 — don't change it.

### K1 — Horizontal chef card — ✅ SHIPPED
`SignaturePlateCard` rewritten to `Row` → 96×96 photo (16px corner, start side) + column
(name, tagline, badges). Two **deliberate deviations from the spec's exact numbers**,
both because there is no scale token at that value and adding one for a single card
wasn't worth it: card radius uses `context.space.surfaceRadius` (18, not 22) and photo
radius is a literal 16 (no token near it either way). Card fill is `colors.porcelain`
(T1), shadow is `context.elevation.porcelain` (T1). Selected state is a 1.5px
`colors.olive` ring (transparent when unselected, so toggling it doesn't shift layout) —
replaces the old ember-border + elevation-level swap.
`CuratedTrack.cardWidth` → 288 (as specced). `rowHeight` → **136, not ~124** — measured
(not guessed): an `IntrinsicHeight` probe of the real card at base text scale came back
`130`, so 124 would already have clipped it; 136 leaves headroom for the 2.0× text-scale
case below. `SignaturePlate.imageAsset` (`String?`) added; every catalogue entry leaves
it `null`, so every card renders `_PlatePhotoFallback` (radial gradient, no text) today.
**Found and fixed two real overflow bugs while wiring this up**, not just theoretical
edge cases:
1. The first draft used `mainAxisAlignment: spaceBetween` with three fixed-size
   children and no flex child at all — that overflows the instant the three together
   need more height than the row has. Fixed by making the tagline `Expanded`: the
   flexible element has to be an actual flex child, not just vertically spaced.
2. At 2.0× text scale, `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)` wraps
   the card. The card's height is fixed by the carousel's `itemExtent` — text can grow
   until it fills that budget, not past it, or it can only overflow. The rest of the app
   is unaffected; the clamp is local to this one card.
Test: `test/features/curated_menu/presentation/curated_track_test.dart` (new file, no
prior coverage existed for this widget). Non-vacuous: widened the clamp to 3.0, watched
the 2.0× test fail with the exact overflow this was written to catch, restored, reran
green.

### K2 — Macro badges — ✅ SHIPPED
`_PlateFigures` (Latin-only "175 kcal / P42") replaced by `_MacroBadges` — two pill
capsules via a new `_MacroBadge`: kcal on `colors.kcalTint`/`colors.ink`, protein on
`colors.protein.withValues(alpha: 0.10)`/`colors.protein`. **Bilingual, not just the
plan's Arabic wording** — Arabic uses `arabicKilocalories()` (K3) + `"$g غ بروتين"`;
English uses `"$kcal kcal"` + `"${g}g protein"`, matching how every other bilingual pair
in this codebase already works (`LocalizedText`, `plate_segment.dart`). No isolated LTR
run needed here, unlike the old widget's comment — that was working around a Latin
*word* ("kcal") next to a number; every word beside a digit now is in the paragraph's
own language, and digits alone don't need bidi isolation.
`Wrap`, not `Row`: this is what stopped the first 2.0×-scale overflow (the second capsule
now drops to its own line instead of extending past the card's width) — the K1 write-up
above covers the second (vertical) overflow this uncovered.

### K3 — Arabic counted-noun helper (pure function) — ✅ SHIPPED
`lib/core/localization/arabic_count.dart`: `String arabicKilocalories(int n)` returns
the whole display string (word, or `"$n word"`), not just the word — callers don't
re-decide when to show the digit. `core/localization` carries no Flutter dependency
(same as `localized_text.dart` beside it), so K2 can call this from anywhere.
Table test at `test/core/localization/arabic_count_test.dart` covers all 14 values from
this plan's original table (0,1,2,3,10,11,99,100,101,102,103,111,555,1000). Non-vacuous:
narrowed the `3..10` plural band to `3..9`, watched the `10` case fail, restored, reran
green.

### S1 — Sliding segmented control — ✅ SHIPPED
`_TrackSwitch` rewritten: `colors.track` pill container, one `AnimatedAlign` (inside
`Positioned.fill` inside a `Stack`) carries the porcelain pill (T1 shadow) between the
two halves — `AlignmentDirectional`, so it mirrors under RTL automatically, no manual
left/right branching. 320ms `Curves.easeOutCubic`; `Duration.zero` under
`MediaQuery.maybeDisableAnimationsOf`. Active label is `ink` + `FontWeight.w700`,
inactive `inkFaint` — matches the plan; hint copy untouched. Per-cell decoration
(the old selected fill + hairline border) removed — the sliding pill is now the only
selection signal, so a cell and a competing decoration can't say different things.
`TactileFeedbackWell` (and its built-in `Semantics(selected:)`) kept per half.
Tests: new "sliding track switch (S1)" group in `order_home_screen_test.dart` — tap
retargets the `AnimatedAlign` immediately then reaches it after settling; reduced motion
sets `duration: Duration.zero`; the selected tab's semantics node reports `isSelected`.
Non-vacuous: forced `duration` to always be 320ms (reduced-motion case failed) and
forced `index` to always be 0 (tap-retarget case failed), restored each, reran green.

## Edge cases

1. **RTL vs LTR:** halo start, photo side, pill slide direction, protein zone side all
   mirror. Test both `AppLanguage`s.
2. **Dark theme:** every new colour has a dark value; golden for both.
3. **Text scale 1.3× / 2.0×:** card title 1 line ellipsis, tagline 2 lines max, badges
   wrap not overflow; segmented labels ellipsis. Thumb-zone test must still pass.
4. **Narrow phone (320pt):** card 288 + gutter still peeks next card; plate shrinks,
   pill labels hide if zone narrower than label + 16 (fiber zone is only 20%).
5. **Long English names** ("Smokehouse & Bulgur") in LTR.
6. **Image missing / fails to load:** fallback gradient, no broken-image icon; plate
   compartment falls back to tone fill.
7. **Reduced motion:** tab pill and halo jump, no slide.
8. **Rapid tab toggling:** pill must retarget mid-animation, not queue.
9. **Curated → architect edit:** halo recomputes from actual filled segments; clearing a
   segment shrinks halo and restores watermark.
10. **Scale change (`setScale`)** changes kcal/protein badges; plural helper re-evaluates.
11. **kcal = 0 or null summary:** badge hidden, not "0 سعرة".
12. **Painter perf:** no per-frame blur recomputation; check with `flutter run --profile`
    raster thread on a mid Android.
13. **Contrast:** extend the existing theme contrast test to `porcelain` + badge pairs.

## Acceptance criteria

- Analyzer: 0 errors, 0 new warnings.
- `test/ui_primitives/plate/*`, `test/features/order_home/*`, `test/features/curated_menu/*`
  pass; goldens regenerated **and visually reviewed** against the mockup (light, dark, RTL).
- New tests: K3 table test; halo length = area-fraction sum; contrast for new pairs;
  segmented control reduced-motion. Each proven non-vacuous (break it, watch fail, restore).
- Thumb-zone layout test unchanged and green.

## Execution notes (for the implementing model)

- **Read before assuming:** `PlateGeometry` public fields (`dish`, `ring`, `zones`,
  `zoneCentroids`, `ringMetric`, `ringLength`), `PlateCanvasData`, `plate_animation_model.dart`
  and `MawzoonElevation` — use what exists; don't recompute geometry in the painter.
- Colours only via `context.colors.*`; no hex literals in widgets (existing idiom).
  Spacing via `context.space.*`, text via `MawzoonText` + `context.type.*`.
- `MawzoonColors` is a `ThemeExtension`: new fields must be added to constructor, both
  factories, `copyWith` **and** `lerp`, or theme animation silently snaps.
- Blur on canvas: `Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)`.
  Split painter into static layer (lip, well, grooves — repaint only on size/brightness)
  and dynamic layer (fills, halo) — two `CustomPaint`s or `isComplex/willChange` flags.
- `Path.computeMetrics()` → `extractPath(start, start+len)` for the halo; handle the
  wrap past the path's end with two extracts.
- Goldens: use the repo's existing golden setup and font loading (see
  `test/ui_primitives/plate/plate_golden_test.dart`); don't introduce a new golden lib.
- **Known broken before this plan (not ours):** `test/widget_test.dart` (refers to
  `MyApp`, 1 analyzer error) and 13 goldens in cart_checkout / kitchen_display /
  manager_suite. Still exactly 14 failures / 1 analyzer error after every ID above —
  reverify with a git-stash isolation (see below) before assuming a 15th is also
  pre-existing; don't assume.
- Tests: there is no `.claude/scripts/quiet-test.sh`; use `--reporter=failures-only`.
- `MacroCapsule` (dock) was never touched — out of scope, C4 is what would touch it.
- All plate + order_home goldens are regenerated through S1 (10 + 4 files). If C4 ships
  later, regenerate `test/ui_primitives/plate/goldens/*` and
  `test/features/order_home/goldens/*` again and eyeball them — the ring is the one
  thing C4 would change that these goldens cover.
- **Real image decode in a widget test needs `tester.runAsync` + a real
  `Future.delayed`**, not just extra `pump()` calls — see C3 above. Cost me a debug
  session; don't rediscover it.
- **Isolating "is this failure mine?"**: `git stash push -q -- <files>`, rerun, `git
  stash pop -q`. A shell variable holding multiple paths does not word-split the way
  you'd expect in zsh — write every path out in the command rather than interpolating a
  variable.
- Update this file in the same pass: mark shipped IDs, delete wrong guidance. Every ID
  above practiced what it preaches.
