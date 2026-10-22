import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/catalogue_fingerprint.g.dart' as app;

import '../../tool/catalogue_seed.dart';

const String _fix = 'Run `dart run tool/catalogue_seed.dart`, then apply '
    'supabase/seed/module11_catalogue.sql to the database.';

void main() {
  group('server catalogue is generated from the Dart one', () {
    test('seed SQL is current', () {
      expect(File(seedPath).readAsStringSync(), buildSeed(), reason: _fix);
    });

    test('parity test SQL is current', () {
      expect(File(parityPath).readAsStringSync(), buildParity(), reason: _fix);
    });

    test('the app sends the fingerprint of the menu it was built with', () {
      expect(
        File(fingerprintPath).readAsStringSync(),
        buildFingerprintDart(),
        reason: _fix,
      );
      expect(app.catalogueFingerprint, catalogueFingerprint(), reason: _fix);
    });
  });
}
