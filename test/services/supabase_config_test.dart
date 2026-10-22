import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/services/supabase_service.dart';

Map<String, dynamic> _claims(String jwt) {
  final String payload = jwt.split('.')[1];
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))))
      as Map<String, dynamic>;
}

void main() {
  group('SupabaseConfig', () {
    test('the shipped key is the anon role, never service_role', () {
      // A service-role key in an app binary bypasses every RLS policy.
      expect(_claims(SupabaseConfig.anonKey)['role'], 'anon');
    });

    test('the key belongs to the project the URL points at', () {
      final String ref = Uri.parse(SupabaseConfig.url).host.split('.').first;
      expect(_claims(SupabaseConfig.anonKey)['ref'], ref);
    });
  });
}
