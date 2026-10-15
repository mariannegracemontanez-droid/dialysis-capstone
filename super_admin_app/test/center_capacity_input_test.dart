import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/utils/center_capacity_input.dart';

void main() {
  group('validateShiftsInput (Add Centre)', () {
    test('accepts whole numbers of at least 1', () {
      for (final input in ['1', '2', '3', ' 4 ']) {
        expect(validateShiftsInput(input), isNull, reason: input);
      }
    });

    test('rejects blank, zero, negative, fractional and non-numbers', () {
      for (final input in ['', '  ', '0', '-1', '1.5', 'abc']) {
        expect(validateShiftsInput(input), isNotNull, reason: input);
      }
    });
  });

  group('parseWholeNumberInput', () {
    test('non-negative whole numbers', () {
      expect(parseWholeNumberInput('0'), 0);
      expect(parseWholeNumberInput(' 12 '), 12);
      expect(parseWholeNumberInput('12.0'), 12);
    });

    test('null for anything else', () {
      for (final input in ['', '-3', '2.5', 'x']) {
        expect(parseWholeNumberInput(input), isNull, reason: input);
      }
    });
  });

  group('suggestedAvailableSlots', () {
    test('is machines × shifts', () {
      expect(suggestedAvailableSlots('5', '2'), 10);
      expect(suggestedAvailableSlots('4', '3'), 12);
      expect(suggestedAvailableSlots('0', '2'), 0);
    });

    test('gives no suggestion while either value is invalid', () {
      expect(suggestedAvailableSlots('', '2'), isNull);
      expect(suggestedAvailableSlots('5', 'abc'), isNull);
      expect(suggestedAvailableSlots('5.5', '2'), isNull);
    });
  });
}
