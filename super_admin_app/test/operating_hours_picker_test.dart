import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/utils/operating_hours.dart';

void main() {
  group('formatOperatingTime / formatOperatingHours', () {
    test('uses the stored 12-hour form', () {
      expect(
        formatOperatingTime(const TimeOfDay(hour: 7, minute: 0)),
        '7:00 AM',
      );
      expect(
        formatOperatingTime(const TimeOfDay(hour: 0, minute: 5)),
        '12:05 AM',
      );
      expect(
        formatOperatingTime(const TimeOfDay(hour: 12, minute: 30)),
        '12:30 PM',
      );
      expect(
        formatOperatingTime(const TimeOfDay(hour: 17, minute: 45)),
        '5:45 PM',
      );
      expect(
        formatOperatingHours(
          const TimeOfDay(hour: 7, minute: 0),
          const TimeOfDay(hour: 17, minute: 0),
        ),
        '7:00 AM - 5:00 PM',
      );
    });

    test('what is saved parses back to the same times', () {
      for (var minutes = 0; minutes < 24 * 60; minutes += 37) {
        final open = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
        const close = TimeOfDay(hour: 23, minute: 59);
        final range = parseOperatingHoursRange(
          formatOperatingHours(open, close),
        );
        expect(range, isNotNull);
        expect(range!.open, open);
        expect(range.close, close);
      }
    });
  });

  group('parseOperatingHoursRange reads existing stored values', () {
    test('legacy formats', () {
      final cases = {
        '7:00 AM - 5:00 PM': (7, 0, 17, 0),
        '8AM–4PM': (8, 0, 16, 0),
        '08:00 to 20:30': (8, 0, 20, 30),
        '10:00 PM until 2:00 AM': (22, 0, 2, 0),
      };
      cases.forEach((stored, expected) {
        final range = parseOperatingHoursRange(stored);
        expect(range, isNotNull, reason: stored);
        expect(range!.open, TimeOfDay(hour: expected.$1, minute: expected.$2));
        expect(range.close, TimeOfDay(hour: expected.$3, minute: expected.$4));
      });
    });

    test('blank or unreadable values give null (kept as-is by the form)', () {
      for (final stored in [
        null,
        '',
        '   ',
        'by appointment',
        '25:00 - 26:00',
      ]) {
        expect(parseOperatingHoursRange(stored), isNull, reason: '$stored');
      }
    });
  });

  group('validateOperatingTimes', () {
    const seven = TimeOfDay(hour: 7, minute: 0);
    const five = TimeOfDay(hour: 17, minute: 0);

    test('requires both times', () {
      expect(validateOperatingTimes(null, five), isNotNull);
      expect(validateOperatingTimes(seven, null), isNotNull);
    });

    test('rejects identical times', () {
      expect(validateOperatingTimes(seven, seven), isNotNull);
    });

    test('accepts day and overnight ranges', () {
      expect(validateOperatingTimes(seven, five), isNull);
      expect(validateOperatingTimes(five, seven), isNull);
    });
  });
}
