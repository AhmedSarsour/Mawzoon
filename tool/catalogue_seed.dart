// Generates the server's copy of the menu from the Dart catalogue:
//   supabase/seed/module11_catalogue.sql      (apply: psql "$(cat ~/.config/mawzoon/db_url)" -1 -f …)
//   supabase/tests/module11_parity.sql        (server price/draw == Dart, every combo)
//   lib/core/menu/catalogue_fingerprint.g.dart (what the app sends with each order)
// Run after any menu, price or recipe change:  dart run tool/catalogue_seed.dart
// test/tool/catalogue_seed_test.dart fails the build if these files are stale.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mawzoon/core/config/launch_switches.dart';
import 'package:mawzoon/core/measure/quantity.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/curated_menu/data/signature_plate_catalog.dart';
import 'package:mawzoon/features/curated_menu/domain/signature_plate.dart';
import 'package:mawzoon/features/manager_suite/domain/plate_recipe.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';

const String seedPath = 'supabase/seed/module11_catalogue.sql';
const String parityPath = 'supabase/tests/module11_parity.sql';
const String fingerprintPath = 'lib/core/menu/catalogue_fingerprint.g.dart';

String _q(String s) => "'${s.replaceAll("'", "''")}'";

String volumeOf(PortionScale scale) => switch (scale) {
      PortionScale.standardBalance => 'STANDARD',
      PortionScale.athleticLoad => 'ATHLETIC',
    };

String _orderType(FulfilmentMode mode) => switch (mode) {
      FulfilmentMode.delivery => 'DELIVERY',
      FulfilmentMode.pickup => 'PICKUP',
    };

/// A decimal with at most [places] places, or throw: the SQL column would round it.
String _decimal(double value, int places) {
  final double scaled = value * _pow10(places);
  if ((scaled - scaled.round()).abs() > 1e-9) {
    throw StateError('$value has more than $places decimal places');
  }
  return value.toString();
}

int _pow10(int n) => n == 0 ? 1 : 10 * _pow10(n - 1);

/// The catalogue rows as SQL, without the fingerprint (which hashes this text).
String _catalogueBody() {
  final StringBuffer b = StringBuffer();
  final List<IngredientOption> components = MawzoonCatalog.all;
  final String componentIds =
      components.map((IngredientOption o) => _q(o.id)).join(', ');
  final String plateIds =
      SignaturePlateCatalog.all.map((SignaturePlate p) => _q(p.id)).join(', ');

  b.writeln('delete from public.signature_plates where id not in ($plateIds);');
  b.writeln('insert into public.menu_components '
      '(component_id, segment, surcharge_minor_units, base_portion_grams) values');
  b.writeln(
    components
        .map(
          (IngredientOption o) => '  (${_q(o.id)}, ${_q(o.segment.name)}, '
              '${o.surchargeMinorUnits}, ${_decimal(o.basePortionGrams, 1)})',
        )
        .join(',\n'),
  );
  b.writeln(
      'on conflict (component_id) do update set segment = excluded.segment, '
      'surcharge_minor_units = excluded.surcharge_minor_units, '
      'base_portion_grams = excluded.base_portion_grams;');
  b.writeln(
    'delete from public.menu_components where component_id not in ($componentIds);',
  );

  b.writeln(
    'insert into public.signature_plates (id, protein_id, carb_id, fiber_id) values',
  );
  b.writeln(
    SignaturePlateCatalog.all
        .map(
          (SignaturePlate p) =>
              '  (${_q(p.id)}, ${_q(p.protein.id)}, ${_q(p.carb.id)}, ${_q(p.fiber.id)})',
        )
        .join(',\n'),
  );
  b.writeln('on conflict (id) do update set protein_id = excluded.protein_id, '
      'carb_id = excluded.carb_id, fiber_id = excluded.fiber_id;');

  b.writeln(
    'insert into public.portion_scale_factors (volume, segment, factor) values',
  );
  b.writeln(
    <String>[
      for (final PortionScale scale in PortionScale.values)
        for (final PlateSegment segment in PlateSegment.values)
          '  (${_q(volumeOf(scale))}, ${_q(segment.name)}, '
              '${_decimal(scale.factorFor(segment), 3)})',
    ].join(',\n'),
  );
  b.writeln(
    'on conflict (volume, segment) do update set factor = excluded.factor;',
  );

  // Stock is live data: the seed sets what an ingredient *is*, never how much is on hand.
  b.writeln('insert into public.raw_ingredients '
      '(id, name_ar, name_en, unit, storage_area, shelf_life_days) values');
  b.writeln(
    RawStore.all
        .map(
          (RawIngredient i) =>
              '  (${_q(i.id)}, ${_q(i.name.ar)}, ${_q(i.name.en)}, '
              '${_q(i.unit.name)}, ${_q(i.area.name)}, ${i.shelfLifeDays ?? 'null'})',
        )
        .join(',\n'),
  );
  b.writeln('on conflict (id) do update set name_ar = excluded.name_ar, '
      'name_en = excluded.name_en, unit = excluded.unit, '
      'storage_area = excluded.storage_area, shelf_life_days = excluded.shelf_life_days;');

  b.writeln('delete from public.recipe_lines;');
  b.writeln('insert into public.recipe_lines '
      '(component_id, ingredient_id, amount_minor_units) values');
  b.writeln(
    <String>[
      for (final PlateRecipe recipe in MawzoonRecipes.all)
        for (final RecipeLine line in recipe.lines)
          '  (${_q(recipe.componentId)}, ${_q(line.ingredient.id)}, '
              '${line.amount.minorUnits})',
    ].join(',\n'),
  );
  b.writeln(';');
  // Ingredients dropped from the menu are kept: past orders' draws still point at them.

  const int vatBasisPoints = PriceBreakdown.vatBasisPoints;
  b.writeln(
    '-- pricing: base, athletic uplift, delivery fee, VAT (basis points)',
  );
  b.writeln('-- ${PriceBreakdown.basePlatePrice.minorUnits}, '
      '${PriceBreakdown.athleticLoadUplift.minorUnits}, '
      '${PriceBreakdown.standardDeliveryFee.minorUnits}, $vatBasisPoints');
  return b.toString();
}

/// SHA-256 of the catalogue rows, first 16 hex chars.
String catalogueFingerprint() =>
    sha256.convert(utf8.encode(_catalogueBody())).toString().substring(0, 16);

String buildSeed() {
  final String fingerprint = catalogueFingerprint();
  return '''
-- GENERATED by tool/catalogue_seed.dart from the Dart catalogue. Do not edit.
-- Apply after every change: psql "\$(cat ~/.config/mawzoon/db_url)" -X -q -1 -f $seedPath
${_catalogueBody()}insert into public.pricing (id, base_plate_minor_units, athletic_uplift_minor_units,
  delivery_fee_minor_units, vat_basis_points, delivery_enabled, card_payment_enabled,
  catalogue_fingerprint)
values (true, ${PriceBreakdown.basePlatePrice.minorUnits}, ${PriceBreakdown.athleticLoadUplift.minorUnits}, ${PriceBreakdown.standardDeliveryFee.minorUnits}, ${PriceBreakdown.vatBasisPoints}, ${LaunchSwitches.delivery}, ${LaunchSwitches.cardPayment}, ${_q(fingerprint)})
on conflict (id) do update set base_plate_minor_units = excluded.base_plate_minor_units,
  athletic_uplift_minor_units = excluded.athletic_uplift_minor_units,
  delivery_fee_minor_units = excluded.delivery_fee_minor_units,
  vat_basis_points = excluded.vat_basis_points,
  delivery_enabled = excluded.delivery_enabled,
  card_payment_enabled = excluded.card_payment_enabled,
  catalogue_fingerprint = excluded.catalogue_fingerprint;
''';
}

String buildFingerprintDart() => '''
// GENERATED by tool/catalogue_seed.dart. Do not edit.

/// Hash of the menu, prices and recipes this build was compiled with. Sent with
/// every order; the server refuses an order whose fingerprint differs from its own.
const String catalogueFingerprint = '${catalogueFingerprint()}';
''';

String _priceRow(ProteinOption p, CarbOption c, FiberOption f,
    PortionScale scale, FulfilmentMode mode,) {
  final PriceBreakdown price = PriceBreakdown.forPlate(
    selection: PlateSelection(protein: p, carb: c, fiber: f, scale: scale),
    mode: mode,
  );
  return '  (${_q(p.id)}, ${_q(c.id)}, ${_q(f.id)}, ${_q(volumeOf(scale))}, '
      '${_q(_orderType(mode))}, ${price.total.minorUnits}, '
      '${price.tax.minorUnits})';
}

/// Every plate a guest can build × both volumes × both fulfilment modes, priced
/// by Dart's PriceBreakdown; and every component's draw at both volumes.
String buildParity() {
  final List<String> prices = <String>[
    for (final ProteinOption p in MawzoonCatalog.proteins)
      for (final CarbOption c in MawzoonCatalog.carbs)
        for (final FiberOption f in MawzoonCatalog.fibers)
          for (final PortionScale scale in PortionScale.values)
            for (final FulfilmentMode mode in FulfilmentMode.values)
              _priceRow(p, c, f, scale, mode),
  ];
  final List<String> draws = <String>[
    for (final IngredientOption option in MawzoonCatalog.all)
      for (final PortionScale scale in PortionScale.values)
        ...?MawzoonRecipes.forOption(option)
            ?.drawAt(scale, segment: option.segment)
            .entries
            .map(
              (MapEntry<RawIngredient, Quantity> e) => '  (${_q(option.id)}, '
                  '${_q(volumeOf(scale))}, ${_q(e.key.id)}, ${e.value.minorUnits})',
            ),
  ];
  return '''
-- GENERATED by tool/catalogue_seed.dart. Do not edit.
-- Server pricing and stock draws must equal Dart's for every combination.
-- Run after applying the seed: psql "\$(cat ~/.config/mawzoon/db_url)" -X -q -v ON_ERROR_STOP=1 -f $parityPath
begin;
create temp table expected_price (protein text, carb text, fiber text,
  volume public.volume_type, order_type public.order_type, total integer, tax integer)
  on commit drop;
insert into expected_price values
${prices.join(',\n')};

create temp table expected_draw (component text, volume public.volume_type,
  ingredient text, amount bigint) on commit drop;
insert into expected_draw values
${draws.join(',\n')};

do \$\$
declare bad record;
begin
  if (select catalogue_fingerprint from public.pricing) <> ${_q(catalogueFingerprint())} then
    raise exception 'FAIL: live catalogue fingerprint differs from this build — apply the seed';
  end if;
  select e.*, q.total_minor_units as server, q.tax_minor_units as server_tax into bad
    from expected_price e
    cross join lateral private.quote_plate(e.protein, e.carb, e.fiber, e.volume, e.order_type) q
   where q.total_minor_units <> e.total or q.tax_minor_units <> e.tax limit 1;
  if found then raise exception 'FAIL: price parity %', row_to_json(bad); end if;

  select coalesce(e.component, s.component) as component, coalesce(e.volume, s.volume) as volume,
         coalesce(e.ingredient, s.ingredient_id) as ingredient, e.amount as dart, s.amount as server
    into bad
    from expected_draw e
    full join (
      select c.component_id as component, v.volume, d.ingredient_id, d.amount_minor_units as amount
        from public.menu_components c
        cross join (values ('STANDARD'::public.volume_type), ('ATHLETIC')) v (volume)
        cross join lateral private.component_draw(c.component_id, v.volume) d
    ) s on s.component = e.component and s.volume = e.volume and s.ingredient_id = e.ingredient
   where e.amount is distinct from s.amount limit 1;
  if found then raise exception 'FAIL: draw parity %', row_to_json(bad); end if;
end \$\$;

select 'PARITY OK: ${prices.length} prices, ${draws.length} draw lines' as result;
rollback;
''';
}

void main() {
  File(seedPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(buildSeed());
  File(parityPath).writeAsStringSync(buildParity());
  File(fingerprintPath).writeAsStringSync(buildFingerprintDart());
  stdout.writeln('fingerprint ${catalogueFingerprint()}');
}
