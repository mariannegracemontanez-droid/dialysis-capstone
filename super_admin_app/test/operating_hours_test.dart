import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/utils/operating_hours.dart';

/// Focused checks for the shared operating-hours parser (R12), which replaced
/// two implementations that read the same stored string differently.
///
/// Every case is evaluated at a fixed [TimeOfDay] rather than the wall clock,
/// so these do not depend on when they are run.
void main() {
  const noon = TimeOfDay(hour: 12, minute: 0);
  const evening = TimeOfDay(hour: 23, minute: 0);
  const afterMidnight = TimeOfDay(hour: 1, minute: 0);
  const preDawn = TimeOfDay(hour: 3, minute: 0);

  group('separators - all forms read the same range', () {
    // The dashboard parser previously failed every one of these except the
    // plain hyphen, and reported the center as closed.
    const sameRange = [
      '8:00 AM - 5:00 PM',
      '8:00 AM – 5:00 PM', // en dash
      '8:00 AM — 5:00 PM', // em dash
      '8:00 AM to 5:00 PM',
      '8:00 AM until 5:00 PM',
    ];

    for (final hours in sameRange) {
      test('"$hours" is open at noon and closed at 11 PM', () {
        expect(isWithinOperatingHours(hours, now: noon), isTrue);
        expect(isWithinOperatingHours(hours, now: evening), isFalse);
      });
    }
  });

  test('24-hour times without AM/PM are supported', () {
    expect(isWithinOperatingHours('08:00 - 17:00', now: noon), isTrue);
    expect(isWithinOperatingHours('08:00 - 17:00', now: evening), isFalse);
  });

  test('a missing AM/PM on the closing time is read as 24-hour', () {
    // "8:00 AM - 17:00" -> 08:00 to 17:00.
    expect(isWithinOperatingHours('8:00 AM - 17:00', now: noon), isTrue);
  });

  test('minutes may be omitted', () {
    expect(isWithinOperatingHours('8 AM - 5 PM', now: noon), isTrue);
  });

  group('overnight ranges cross midnight', () {
    const overnight = '10:00 PM - 2:00 AM';

    test('11 PM is inside', () {
      expect(isWithinOperatingHours(overnight, now: evening), isTrue);
    });

    test('1 AM is inside', () {
      expect(isWithinOperatingHours(overnight, now: afterMidnight), isTrue);
    });

    test('3 AM is outside', () {
      expect(isWithinOperatingHours(overnight, now: preDawn), isFalse);
    });

    test('noon is outside', () {
      expect(isWithinOperatingHours(overnight, now: noon), isFalse);
    });
  });

  test('an equal open and close time means always open', () {
    expect(isWithinOperatingHours('8:00 AM - 8:00 AM', now: noon), isTrue);
    expect(isWithinOperatingHours('8:00 AM - 8:00 AM', now: preDawn), isTrue);
  });

  group('unusable values are never reported as open', () {
    for (final hours in <String?>[
      null,
      '',
      '   ',
      'Open all day', // no separator, no times
      '8:00 AM', // only one side
      '99:99 PM - 5:00 PM', // out of range
    ]) {
      test('${hours == null ? 'null' : '"$hours"'} is not open', () {
        expect(isWithinOperatingHours(hours, now: noon), isFalse);
      });
    }
  });

  test('boundary times are inclusive', () {
    const hours = '8:00 AM - 5:00 PM';
    expect(
      isWithinOperatingHours(hours, now: const TimeOfDay(hour: 8, minute: 0)),
      isTrue,
    );
    expect(
      isWithinOperatingHours(hours, now: const TimeOfDay(hour: 17, minute: 0)),
      isTrue,
    );
    expect(
      isWithinOperatingHours(hours, now: const TimeOfDay(hour: 7, minute: 59)),
      isFalse,
    );
    expect(
      isWithinOperatingHours(hours, now: const TimeOfDay(hour: 17, minute: 1)),
      isFalse,
    );
  });
}
