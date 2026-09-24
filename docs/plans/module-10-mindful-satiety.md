# Module 10 — Mindful Satiety Loop (plan)

Status: **shipped — all IDs M10-01…12.** Mockup: https://claude.ai/artifact/53wWEdvJfYxkXSYNZjm1wS

Code: `lib/features/mindful_satiety/{domain,data,application,presentation}`,
wiring in `lib/main.dart` and `order_home_screen.dart`, platform patch in `tool/patch_platforms.dart`.

## Decisions (resolved: D1 yes, D2 option (a), D3 `متوازن تماماً`)

- **D1 · Packages.** Nothing in `pubspec.yaml` can schedule a notification or persist data.
  Proposed: `flutter_local_notifications`, `timezone`, `flutter_timezone`, `shared_preferences`.
  Add with `flutter pub add`, then pin the resolved version with a `# why` comment (house rule).
- **D2 · Platform setup.** The repo is source-only (no `android/`, `ios/` — see SETUP.md).
  `flutter_local_notifications` needs AndroidManifest receivers, the `POST_NOTIFICATIONS`
  permission and core-library desugaring in `android/app/build.gradle`. Those live in
  generated folders we don't commit. Options: (a) idempotent `tool/patch_platforms.dart`
  run once after `flutter create`, called from SETUP.md; (b) start committing `android/`
  and `ios/`. Recommended: (a). **Until D2 is done the in-app card (M10-07) is the only
  path that works — which is why it exists.**
- **D3 · Arabic copy.** "Perfectly Balanced" = `متوازن تماماً` (proposed) vs `موزون تماماً`
  (brand pun, but reads as the app name). Copy table below.

## Items (stable IDs)

| ID | What | Why |
|---|---|---|
| M10-01 | `SatietyLevel` + `EnergyLevel` enums, `MealReflection` value | The two answers + a frozen snapshot of the plate the guest actually ate. |
| M10-02 | `reflectionDueAt(placedAt, mode)` pure function | "45 min post-meal" needs an anchor; we only know placement time + fulfilment mode. |
| M10-03 | `ReflectionJournal` (capped at 30, newest first) | Recent appetite matters more than old appetite; bounded size = bounded cost. |
| M10-04 | `SatietyCorrelation.insightsFor(journal)` pure engine | The "learn from answers" part. Pure = testable without a device. |
| M10-05 | `ReflectionStore` interface + `SharedPreferencesReflectionStore` + `InMemoryReflectionStore` | Local only. Interface so tests never touch plugins. |
| M10-06 | `ReflectionNotifier` interface + `LocalReflectionNotifier` + `FakeReflectionNotifier` | Same reason. One notification slot → a new order replaces the old one structurally. |
| M10-07 | Pending-reflection card on `OrderHomeScreen` | Works with notifications denied or D2 not done. |
| M10-08 | `ReflectionSheet` (satiety → energy, auto-save) | The primitive. Two taps total, no submit button. |
| M10-09 | Insight line under the portion `VolumeToggle` | Where the portion decision is made. One tap applies it; never auto-applied. |
| M10-10 | `ReflectionController` (ChangeNotifier) wired in `main.dart` | Mirrors `ManagerSuiteController` wiring. |
| M10-11 | Restraint tests (no digits, banned words) | "No streaks / no calorie ledger" enforced by tests, not memory. |
| M10-12 | README status table + SETUP.md notification section | README currently stops at Module 06; bring 08, 09, 10 in. |

## Behaviour spec

### Timing (M10-02)
- Due = `placedAt` + fulfilment upper bound (delivery 45 min, pickup 15 min) + 45 min.
  So delivery → +90 min, pickup → +60 min. Add a `Duration readyWithin` to `FulfilmentMode`
  next to the existing `estimate` text rather than parsing the Arabic string.
- **Quiet hours 22:00–07:00 local:** no OS notification. The pending card still appears
  in-app when opened. Low stimulation includes not waking anyone.
- **Expiry:** a pending reflection expires 4 h after due. After that the answer is a guess
  and would poison the correlation. Expired = dropped silently, nothing stored.
- One pending reflection at a time. A new order replaces the pending one (cancel notification
  id `1001`, overwrite pending). No queue, no backlog of questions.

### Notification (M10-06)
- Title `موزون` / `Mawzoon`. Body `كيف يشعر جسمك الآن؟` / `How does your body feel?`. No emoji.
- Android: channel `mindful_reflection`, `Importance.low` (no sound, no heads-up), no badge.
  Use **inexact** scheduling (`AndroidScheduleMode.inexactAllowWhileIdle`) — a few minutes'
  drift is fine and avoids the restricted exact-alarm permission.
- iOS: request **provisional** authorization (quiet delivery to Notification Center, no
  prompt). `presentSound: false`, `presentBadge: false`, interruption level `passive`.
- Android 13+: ask the runtime permission **once**, right after the guest's first placed order
  (the moment the benefit makes sense). Store that we asked. Never ask again.
- Payload = reflection id. Tap → app opens → sheet. Handle cold start via
  `getNotificationAppLaunchDetails()`.

### Sheet (M10-08)
- Shows: the dish names from the snapshot (recognition over recall), eyebrow
  "عن وجبتك قبل قليل", the question, satiety row (3 equal chips).
- Energy row appears only after satiety is picked (progressive disclosure).
- Tapping an energy chip saves immediately, shows one calm confirmation line, closes.
  Tier-3 press + `MawzoonHaptics.selection()` only; no celebration animation.
- "ليس الآن" always visible. Skip = discard pending, store nothing, no follow-up.
- All three chips look identical at rest — no colour hints the "right" answer
  (social-desirability bias). Selected = olive fill, same for every option.
- **No digits anywhere on the sheet.** No kcal, no macro grams, no counts, no dates.

### Correlation engine (M10-04)
Pure, takes `ReflectionJournal` + `Set<InsightKind> dismissed`, returns `List<SatietyInsight>`
(sealed: `PortionInsight`, `CarbReleaseInsight`). Single pass, O(n) time with n ≤ 30,
O(1) space per bucket (windowed majority vote — simple, explainable, needs no training data).

- **Portion:** last 6 reflections on the *current* scale. Need n ≥ 3.
  - athleticLoad and ≥ 2/3 `heavilySatiated` → suggest standardBalance.
  - standardBalance and ≥ 2/3 `light` → suggest athleticLoad.
  - heavy on standard / light on athletic → nothing (no smaller/larger portion exists).
- **Carb release:** bucket by the snapshot's `GlycemicBalance` (steady / balanced / quick).
  Insight only if quick-bucket n ≥ 3 with ≥ 2/3 `sluggish` **and** steady+balanced n ≥ 2 with
  ≤ 1/3 sluggish. The contrast is required — sluggish everywhere means the day, not the carb.
- **Dismiss:** hides that kind until 5 new reflections arrive (store count at dismissal).
- Output copy never contains numbers or calories.

### Storage (M10-05)
- One key `mawzoon.reflection.v1`, JSON `{version, pending, journal, dismissed, askedPermission}`.
- Decode failure → empty state, never throw. Unknown enum name (from a future version) → skip
  that entry, keep the rest.
- Local only. Nothing leaves the device. Uninstall = data gone. State that in the README.

## Copy (D3)

| Key | Arabic | English |
|---|---|---|
| question | كيف يشعر جسمك الآن؟ | How does your body feel? |
| eyebrow | عن وجبتك قبل قليل | About your meal earlier |
| satiety label | الشبع | Fullness |
| light | خفيف | Light |
| balanced | متوازن تماماً | Perfectly Balanced |
| heavy | ممتلئ جداً | Heavily Satiated |
| energy label | الطاقة | Energy |
| calm / energized / sluggish | هادئ / نشيط / خامل | Calm / Energized / Sluggish |
| skip | ليس الآن | Not now |
| saved | شكراً. سنتذكّر هذا في طلبك القادم. | Thanks. We'll remember this next time. |
| portion → standard | آخر أطباقك الرياضية كانت أثقل مما تحب. جرّب التوازن القياسي؟ | Your last Athletic Load plates felt heavier than you like. Try Standard Balance? |
| portion → athletic | آخر أطباقك القياسية تركتك خفيفاً. جرّب الحِمل الرياضي؟ | Your last Standard Balance plates left you light. Try Athletic Load? |
| carb | تشعر بطاقة أهدأ مع الكربوهيدرات بطيئة الإطلاق. | You feel steadier with slow-release carbs. |

Portion names come from `PortionScale.label` — interpolate, don't retype them.

## Edge cases

1. Notifications denied / D2 not done → card on home is the only path; must work fully.
2. App opened before due → no card. After due, before expiry → card. After expiry → nothing.
3. Due falls in quiet hours → no OS notification; card still shows when opened.
4. Two orders 5 min apart → second replaces first (one notification id).
5. Order placed, app killed, device rebooted → scheduled notification must survive reboot
   (Android boot receiver — part of D2).
6. Clock changed / timezone travel → schedule with `tz.local`; expiry compares against the
   injected clock; a due time already in the past at schedule time → skip OS notification, card only.
7. Tap notification after expiry → app opens to home, no sheet, no error.
8. Tap notification on cold start → sheet opens after first frame (needs `MenuScope`).
9. Language switched after scheduling → notification is in the old language. Accept; document.
10. Guest picks satiety then closes the sheet → nothing stored (half an answer is not an answer);
    pending stays until expiry.
11. Recipe recalibrated (Module 09) after the order → use the **snapshot** taken at placement,
    never recompute from today's `RecipeBook`.
12. Curated plate vs architect plate → both are a `PlateSelection`; no difference.
13. Journal at 30 → oldest dropped (FIFO).
14. Corrupt / future-version JSON → empty or partial state, no crash.
15. Reduced motion → confirmation line appears without fade.
16. Journal with mixed scales → portion rule only reads the current scale's entries.
17. Insight dismissed → gone until 5 more reflections; not re-shown on restart.
18. RTL: chips order right-to-left in Arabic; use `EdgeInsetsDirectional` everywhere.
19. Screen reader: each chip is a button with its label; selected state announced.

## Acceptance criteria (proposed)

Done when: `flutter analyze` 0 errors; full suite green; engine tests cover every rule
threshold (n = 2 vs 3, exactly 2/3, contrast missing); restraint test proven non-vacuous
(add a digit to the sheet, watch it fail, revert); a widget test drives card → sheet →
two taps → journal has one entry; README + SETUP updated.

## What shipped differently / notes for the next session

- Home screen widget tests must pump in 50 ms steps (`_settle` in `reflection_widget_test.dart`):
  the ambient glow never settles, and one long `pump` draws a single frame.
- The controller arms one `Timer` for the next boundary (due, then expiry) so the home card
  appears/disappears without polling. Tests must `dispose()` the controller.
- `tool/patch_platforms.dart` was verified against Flutter 3.41 templates: debug APK and iOS
  simulator builds both succeed after patching.
- Not verified on a device: the notification actually arriving 90 min later, provisional
  delivery on iOS, the reboot receiver. Needs a manual check on a real phone.

## Execution notes (for the implementing model)

- **Verify, don't assume:** `flutter_local_notifications` API changed across majors
  (`zonedSchedule` params, `AndroidScheduleMode`, `DarwinNotificationDetails.interruptionLevel`,
  provisional permission flag). Read the resolved version's source in `~/.pub-cache`.
- **Snapshot fields:** read `NutritionalSummary` (`lib/core/nutrition/nutritional_summary.dart`)
  and `GlycemicProfile` (`lib/core/nutrition/glycemic.dart`) for the real getter that yields a
  `GlycemicBalance`. Snapshot at placement in `OrderHomeScreen` after `showCheckoutSheet`
  returns (`order_home_screen.dart` ~L126), using the summary the guest saw (via `MenuScope` book).
- **Reuse:** `showModalBottomSheet` styled like `checkout_sheet.dart` (not `showSpringSheet`:
  matches the checkout sheet that's already tested), `TactileFeedbackWell`, `MawzoonText`,
  `context.colors/space/type`, `LocalizedText`. The sheet names the dishes instead of drawing a
  `TriPartitionPlate` — the plate widget is a 2.24:1 animated hero, wrong at thumbnail size. Pattern for controller + wiring: `ManagerSuiteController` in `main.dart`.
- **Inject the clock** (`DateTime Function() now`) into controller and engine callers. No
  `DateTime.now()` inside domain code.
- **Plugins in tests:** never instantiate plugin-backed classes in tests — use the in-memory /
  fake implementations. `SharedPreferences.setMockInitialValues` only for the store's own test.
- Domain code goes in `lib/features/mindful_satiety/{domain,application,presentation,data}`,
  tests mirror it under `test/features/mindful_satiety/`.
- Tests: run targeted with `flutter test test/features/mindful_satiety -r failures-only`;
  full suite once at the end.
- **Restraint test (M10-11):** walk the sheet's and insight line's rendered `Text`/`RichText`
  and fail on `[0-9٠-٩]`; also scan every copy constant for banned words
  (`streak`, `سلسلة`, `kcal`, `سعرة`, `calorie`, `score`, `نقاط`).
- **Do M10-04 (engine) on Opus.** The thresholds and the contrast rule are easy to get subtly
  wrong (off-by-one at exactly 2/3, integer division, reading the wrong scale's window) and a
  wrong rule silently gives bad advice about someone's eating. Everything else is Sonnet-safe.
