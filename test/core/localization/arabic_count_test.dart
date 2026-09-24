import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/arabic_count.dart';

void main() {
  group('arabicKilocalories', () {
    final Map<int, String> table = <int, String>{
      0: 'سعرة',
      1: 'سعرة واحدة',
      2: 'سعرتان',
      3: '3 سعرات',
      10: '10 سعرات',
      11: '11 سعرة',
      99: '99 سعرة',
      100: '100 سعرة',
      101: '101 سعرة',
      102: '102 سعرة',
      103: '103 سعرات',
      111: '111 سعرة',
      555: '555 سعرة',
      1000: '1000 سعرة',
    };

    table.forEach((int n, String expected) {
      test('$n → "$expected"', () {
        expect(arabicKilocalories(n), expected);
      });
    });
  });
}
