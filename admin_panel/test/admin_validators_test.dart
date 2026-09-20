// Rules for the Admin panel's shared field validation.
//
// These exist because the bugs they cover were real: the Edit Patient
// form accepted a blank email and a letters-only phone number, the blood
// pressure form accepted a systolic of 0 (and a transposed 80/120), the
// weight form promised "greater than zero" while accepting it, and the
// login form posted an empty password to Supabase. Each case below is one
// of those.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/utils/admin_validators.dart';

void main() {
  group('required text', () {
    test('whitespace does not count as filled in', () {
      expect(
        AdminValidators.requiredText('   ', label: 'home address'),
        'Please enter the home address.',
      );
    });

    test('accepts a real value and names the field when too long', () {
      expect(
        AdminValidators.requiredText('12 Maysan Road', label: 'home address'),
        isNull,
      );
      expect(
        AdminValidators.requiredText(
          'x' * 30,
          label: 'home address',
          maxLength: 20,
        ),
        contains('home address'),
      );
    });
  });

  group('email', () {
    test('rejects an address with no domain dot', () {
      expect(AdminValidators.email('admin@localhost'), isNotNull);
    });

    test('rejects blank when required, allows it when not', () {
      expect(AdminValidators.email(''), 'Please enter the email address.');
      expect(AdminValidators.email('', required: false), isNull);
    });

    test('accepts an ordinary address', () {
      expect(AdminValidators.email('nurse@curenurture.ph'), isNull);
    });
  });

  group('phone', () {
    test('rejects letters', () {
      expect(AdminValidators.phone('not a number'), isNotNull);
    });

    test('accepts the formats staff actually type', () {
      expect(AdminValidators.phone('0917 123 4567'), isNull);
      expect(AdminValidators.phone('+63 (917) 123-4567'), isNull);
    });

    test('rejects too few digits', () {
      expect(AdminValidators.phone('12345'), contains('7 to 15 digits'));
    });
  });

  group('whole number', () {
    test('tells a decimal apart from a non-number', () {
      expect(
        AdminValidators.wholeNumber('3.5', label: 'capacity'),
        'The capacity must be a whole number.',
      );
      expect(
        AdminValidators.wholeNumber('abc', label: 'capacity'),
        contains('numbers only'),
      );
    });

    test('names a negative as negative rather than out of range', () {
      expect(
        AdminValidators.wholeNumber('-1', label: 'capacity'),
        'The capacity cannot be negative.',
      );
    });

    test('honours an optional field', () {
      expect(
        AdminValidators.wholeNumber(
          '',
          label: 'sessions per week',
          min: 1,
          max: 6,
          required: false,
        ),
        isNull,
      );
      expect(
        AdminValidators.wholeNumber(
          '7',
          label: 'sessions per week',
          min: 1,
          max: 6,
          required: false,
        ),
        contains('cannot be more than 6'),
      );
    });
  });

  group('blood pressure', () {
    test('rejects a zero systolic', () {
      expect(
        AdminValidators.bloodPressure(systolic: '0', diastolic: '80'),
        isNotNull,
      );
    });

    test('catches a transposed reading', () {
      final error = AdminValidators.bloodPressure(
        systolic: '80',
        diastolic: '120',
      );

      expect(error, contains('higher than the diastolic'));
      expect(error, contains('80/120'));
    });

    test('accepts a normal reading', () {
      expect(
        AdminValidators.bloodPressure(systolic: '120', diastolic: '80'),
        isNull,
      );
    });
  });

  group('weight', () {
    test('rejects zero, which the old message promised but allowed', () {
      expect(
        AdminValidators.weightKg('0', label: 'weight before dialysis'),
        'The weight before dialysis must be greater than zero.',
      );
    });

    test('accepts a decimal weight', () {
      expect(
        AdminValidators.weightKg('62.4', label: 'weight before dialysis'),
        isNull,
      );
    });
  });

  group('time range', () {
    const eight = TimeOfDay(hour: 8, minute: 0);
    const noon = TimeOfDay(hour: 12, minute: 0);
    const one = TimeOfDay(hour: 13, minute: 0);
    const five = TimeOfDay(hour: 17, minute: 0);

    test('start must precede end', () {
      expect(
        AdminValidators.timeRange(start: noon, end: eight, label: 'AM shift'),
        'The AM shift start time must be earlier than its end time.',
      );
    });

    test('identical times are rejected separately', () {
      expect(
        AdminValidators.timeRange(start: noon, end: noon, label: 'AM shift'),
        contains('cannot be the same'),
      );
    });

    test('a valid range passes', () {
      expect(
        AdminValidators.timeRange(start: eight, end: noon, label: 'AM shift'),
        isNull,
      );
    });

    test('the seeded AM and PM shifts do not overlap', () {
      expect(
        AdminValidators.nonOverlappingRanges(
          firstStart: eight,
          firstEnd: noon,
          firstLabel: 'AM shift',
          secondStart: one,
          secondEnd: five,
          secondLabel: 'PM shift',
        ),
        isNull,
      );
    });

    test('an overlap names both shifts', () {
      final error = AdminValidators.nonOverlappingRanges(
        firstStart: eight,
        firstEnd: one,
        firstLabel: 'AM shift',
        secondStart: noon,
        secondEnd: five,
        secondLabel: 'PM shift',
      );

      expect(error, contains('AM shift'));
      expect(error, contains('PM shift'));
    });

    test('a shift outside operating hours is caught', () {
      expect(
        AdminValidators.rangeWithin(
          start: const TimeOfDay(hour: 6, minute: 0),
          end: noon,
          outerStart: eight,
          outerEnd: five,
          label: 'AM shift',
          outerLabel: 'center operating hours',
        ),
        contains('runs outside'),
      );

      expect(
        AdminValidators.rangeWithin(
          start: eight,
          end: noon,
          outerStart: eight,
          outerEnd: five,
          label: 'AM shift',
          outerLabel: 'center operating hours',
        ),
        isNull,
      );
    });
  });

  group('time parsing and formatting', () {
    test('reads the shapes clinic_shifts and the UI store', () {
      expect(
        AdminValidators.parseTime('08:00:00'),
        const TimeOfDay(hour: 8, minute: 0),
      );
      expect(
        AdminValidators.parseTime('13:30'),
        const TimeOfDay(hour: 13, minute: 30),
      );
      expect(
        AdminValidators.parseTime('5:00 PM'),
        const TimeOfDay(hour: 17, minute: 0),
      );
      expect(
        AdminValidators.parseTime('12:00 AM'),
        const TimeOfDay(hour: 0, minute: 0),
      );
    });

    test('returns null rather than guessing at free text', () {
      expect(AdminValidators.parseTime('whenever'), isNull);
      expect(AdminValidators.parseTime('25:00'), isNull);
      expect(AdminValidators.parseTime(''), isNull);
    });

    test('a written range round-trips', () {
      const start = TimeOfDay(hour: 7, minute: 0);
      const end = TimeOfDay(hour: 17, minute: 0);

      final written = AdminValidators.formatRange(start, end);
      expect(written, '7:00 AM - 5:00 PM');

      final read = AdminValidators.parseRange(written);
      expect(read?.start, start);
      expect(read?.end, end);
    });

    test('legacy free-text hours are reported as unreadable, not guessed', () {
      expect(AdminValidators.parseRange('Mon-Sat, call ahead'), isNull);
    });

    test('sql time is what a Postgres time column round-trips', () {
      expect(
        AdminValidators.toSqlTime(const TimeOfDay(hour: 8, minute: 5)),
        '08:05:00',
      );
    });
  });

  group('past date', () {
    test('rejects a future date of birth', () {
      expect(
        AdminValidators.pastDate(
          DateTime.now().add(const Duration(days: 1)),
          label: 'date of birth',
        ),
        'The date of birth cannot be in the future.',
      );
    });

    test('accepts a plausible one', () {
      expect(
        AdminValidators.pastDate(DateTime(1970, 5, 2), label: 'date of birth'),
        isNull,
      );
    });
  });

  test('firstError reports the first failing rule only', () {
    expect(
      AdminValidators.firstError([
        () => null,
        () => AdminValidators.requiredText('', label: 'home address'),
        () => AdminValidators.requiredText('', label: 'phone number'),
      ]),
      'Please enter the home address.',
    );

    expect(AdminValidators.firstError([() => null, () => null]), isNull);
  });
}
