# Plate Architect prototype

`plate-architect.html` is a single-file, dependency-free mockup of the hero
plate. Open it in any browser — no build step, no server.

It is not a sketch of the app: it runs a JavaScript port of the same
arithmetic and the same geometry the Dart code uses, so the figures it shows
are the figures `lib/core/` computes and the shape it draws is the shape
`lib/ui_primitives/plate/plate_geometry.dart` solves.

| Prototype | Dart equivalent |
|---|---|
| `kcalOf`, `ATWATER` | `core/nutrition/macro_profile.dart` |
| `glycemicLoad`, `glycemicBand` | `core/nutrition/glycemic.dart` |
| `CATALOG`, `SIGNATURES` | `core/menu/mawzoon_catalog.dart`, `curated_menu/` |
| `buildOutline`, `xAtAreaFraction`, `traceZone` | `plate_geometry.dart` |
| `buildRingMetrics`, `traceRing` | `PathMetric.extractPath` |
| `Spring` | `plate_animation_model.dart` |

Keeping the two in step is manual. When the Dart engine changes, this file
has to change with it or it becomes a confident liar — which is worse than no
prototype at all. The golden images under
`test/ui_primitives/plate/goldens/` are the authoritative render.
