import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/utils/ph_contact_number.dart';

TextEditingValue _type(String text) => const PhLocalDigitsInputFormatter()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

void main() {
  group('validatePhLocalDigits', () {
    test('accepts exactly 10 digits not starting with 0', () {
      expect(validatePhLocalDigits('9171234567'), isNull);
      expect(validatePhLocalDigits(' 9171234567 '), isNull);
    });

    test('rejects missing, short, long, leading-0 and non-digit input', () {
      for (final input in [
        '',
        '917123456',
        '91712345678',
        '0917123456',
        '917-123-456',
        '917 123 4567',
        '+639171234567',
        'abcdefghij',
      ]) {
        expect(validatePhLocalDigits(input), isNotNull, reason: input);
      }
    });
  });

  test('composePhContactNumber stores +63 followed by the digits', () {
    expect(composePhContactNumber('9171234567'), '+639171234567');
  });

  test('a number saved by Create Account reopens as the same 10 digits', () {
    // Create Account saves composePhContactNumber(...); the Edit account
    // modal pre-fills from phLocalDigitsFromStored(...).
    final saved = composePhContactNumber('9171234567');
    expect(phLocalDigitsFromStored(saved), '9171234567');
    expect(validatePhLocalDigits(phLocalDigitsFromStored(saved)!), isNull);
  });

  group('phLocalDigitsFromStored (existing records)', () {
    test('recognises common stored forms', () {
      for (final stored in [
        '+639171234567',
        '+63 917 123 4567',
        '639171234567',
        '09171234567',
        '0917-123-4567',
        '(0917) 123 4567',
        '9171234567',
      ]) {
        expect(phLocalDigitsFromStored(stored), '9171234567', reason: stored);
      }
    });

    test('returns null for values that are not PH mobile numbers', () {
      for (final stored in [
        null,
        '',
        'N/A',
        '8123-4567',
        '(02) 8123 4567',
        '0917123456',
        '+1 415 555 0100',
        'call 0917 123 4567',
      ]) {
        expect(phLocalDigitsFromStored(stored), isNull, reason: '$stored');
      }
    });
  });

  test('formatPhContactForDisplay', () {
    expect(formatPhContactForDisplay('09171234567'), '+63 917 123 4567');
    expect(formatPhContactForDisplay('(02) 8123 4567'), '(02) 8123 4567');
    expect(formatPhContactForDisplay(null), '');
  });

  group('PhLocalDigitsInputFormatter', () {
    test('drops a leading 0 after the fixed +63', () {
      expect(_type('0917').text, '917');
      expect(_type('00917').text, '917');
    });

    test('keeps digits only and caps at 10', () {
      expect(_type('917-123 45a67').text, '9171234567');
      expect(_type('917123456789').text, '9171234567');
    });

    test('a pasted full number becomes its local digits', () {
      expect(_type('+63 917 123 4567').text, '9171234567');
      expect(_type('09171234567').text, '9171234567');
    });
  });
}
