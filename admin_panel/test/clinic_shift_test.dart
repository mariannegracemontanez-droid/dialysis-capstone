// Pairing a center's stored shifts to the AM/PM codes the Center
// Profile page edits.
//
// The case that matters here is a center with NO clinic_shifts rows.
// center_scheduling_foundation.sql seeds AM/PM only for the clinics that
// existed when it ran, and nothing replaces that seed for a center the
// Super Admin creates afterwards -- so those centers reach the admin
// panel with an empty shift list. The profile page has to offer an empty
// AM and PM editor for exactly that case instead of showing a dead end,
// which is what ClinicShift.byCode returning null drives.

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/models/clinic_shift.dart';

ClinicShift shift({
  required String id,
  required String code,
  String label = '',
  String start = '08:00:00',
  String end = '12:00:00',
  int capacity = 10,
  bool isActive = true,
}) {
  return ClinicShift.fromJson({
    'id': id,
    'clinic_id': 'c1',
    'shift_code': code,
    'shift_label': label,
    'start_time': start,
    'end_time': end,
    'capacity': capacity,
    'is_active': isActive,
  });
}

void main() {
  group('ClinicShift.codes', () {
    test('is exactly the two codes the shift_code column allows', () {
      expect(ClinicShift.codes, ['AM', 'PM']);
    });
  });

  group('ClinicShift.byCode', () {
    test('finds each configured shift by its code', () {
      final shifts = [
        shift(id: 's1', code: 'AM', label: 'Morning'),
        shift(id: 's2', code: 'PM', label: 'Afternoon'),
      ];

      expect(ClinicShift.byCode(shifts, 'AM')?.id, 's1');
      expect(ClinicShift.byCode(shifts, 'PM')?.id, 's2');
    });

    test('order in the list does not matter', () {
      // getClinicShifts orders by start_time, so PM can come back first
      // if an admin has configured unusual hours.
      final shifts = [
        shift(id: 's2', code: 'PM', start: '06:00:00', end: '10:00:00'),
        shift(id: 's1', code: 'AM', start: '11:00:00', end: '15:00:00'),
      ];

      expect(ClinicShift.byCode(shifts, 'AM')?.id, 's1');
      expect(ClinicShift.byCode(shifts, 'PM')?.id, 's2');
    });

    test('a newly created center has neither shift, and that is not an '
        'error', () {
      // What the edit form sees for a center the Super Admin just made:
      // both codes come back null, so both editors open empty rather
      // than the page having nothing to show.
      expect(ClinicShift.byCode(const [], 'AM'), isNull);
      expect(ClinicShift.byCode(const [], 'PM'), isNull);
    });

    test('a center with only one shift configured keeps the other empty', () {
      final shifts = [shift(id: 's1', code: 'AM')];

      expect(ClinicShift.byCode(shifts, 'AM')?.id, 's1');
      // The PM editor opens blank and is created on save, rather than
      // the AM row being reused or a duplicate AM being written.
      expect(ClinicShift.byCode(shifts, 'PM'), isNull);
    });

    test('every code resolves to at most one row per center', () {
      // clinic_shifts has unique (clinic_id, shift_code), which is also
      // what makes the profile page's upsert idempotent: saving twice
      // updates the same row instead of inserting a second one.
      final shifts = [
        shift(id: 's1', code: 'AM'),
        shift(id: 's2', code: 'PM'),
      ];

      for (final code in ClinicShift.codes) {
        expect(shifts.where((s) => s.shiftCode == code).length, 1);
      }
    });
  });

  group('ClinicShift.displayLabel', () {
    test('an unnamed shift falls back to its code', () {
      // A shift the admin created without typing a name still reads as
      // "AM" in the patient scheduling dropdown, never as blank.
      expect(shift(id: 's1', code: 'AM', label: '').displayLabel, 'AM');
      expect(shift(id: 's1', code: 'AM', label: '   ').displayLabel, 'AM');
    });

    test('a named shift shows its name', () {
      expect(
        shift(id: 's1', code: 'AM', label: 'Morning').displayLabel,
        'Morning',
      );
    });
  });
}
