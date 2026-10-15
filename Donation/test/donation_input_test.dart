import 'package:donation_app/pages/donation_page.dart';
import 'package:donation_app/pages/login_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDonationAmount', () {
    test('accepts whole and centavo amounts', () {
      expect(parseDonationAmount('500'), 500);
      expect(parseDonationAmount(' 1250.50 '), 1250.5);
      expect(parseDonationAmount('99.9'), 99.9);
      expect(parseDonationAmount('.75'), 0.75);
      expect(parseDonationAmount('0'), 0); // rejected later by amount <= 0
    });

    test('accepts the largest amount the column can store', () {
      expect(parseDonationAmount('9999999999.99'), maxDonationAmount);
      expect(parseDonationAmount('10000000000'), isNull);
    });

    test('rejects values double.tryParse used to let through', () {
      for (final input in ['NaN', 'Infinity', '-Infinity', '1e3', '0x10']) {
        expect(parseDonationAmount(input), isNull, reason: input);
      }
    });

    test('rejects negatives, sub-centavo amounts and non-numbers', () {
      for (final input in ['', ' ', '-5', '10.555', '1,000', 'abc', '.']) {
        expect(parseDonationAmount(input), isNull, reason: input);
      }
    });
  });

  group('isNonDonorRole', () {
    test('turns away staff and patients, in either superadmin spelling', () {
      for (final role in ['superadmin', 'super_admin', 'admin', 'patient']) {
        expect(isNonDonorRole(role), isTrue, reason: role);
      }
      expect(isNonDonorRole(' SuperAdmin '), isTrue);
    });

    test('lets donor accounts through', () {
      expect(isNonDonorRole(null), isFalse);
      expect(isNonDonorRole('donor'), isFalse);
      expect(isNonDonorRole(''), isFalse);
    });
  });
}
