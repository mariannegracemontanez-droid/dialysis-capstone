import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/center_model.dart';
import 'package:super_admin_app/utils/center_capacity.dart';
import 'package:super_admin_app/widgets/center_details_dialog.dart';

CenterModel _center({required int machines, Object? shifts, int slots = 7}) {
  return CenterModel.fromJson({
    'id': 'c',
    'name': 'Center',
    'machine': machines,
    'shifts': shifts,
    'slots_available': slots,
  });
}

void main() {
  group('total capacity = machines × saved shifts', () {
    test('1, 2 and 3 shifts', () {
      expect(totalCenterCapacity(machines: 10, shifts: 1), 10);
      expect(totalCenterCapacity(machines: 10, shifts: 2), 20);
      expect(totalCenterCapacity(machines: 10, shifts: 3), 30);
    });

    test('zero or negative inputs never give a negative capacity', () {
      expect(totalCenterCapacity(machines: 0, shifts: 3), 0);
      expect(totalCenterCapacity(machines: 5, shifts: 0), 0);
      expect(totalCenterCapacity(machines: -1, shifts: 3), 0);
    });

    test('CenterModel uses the saved shift count', () {
      expect(_center(machines: 4, shifts: 1).totalCapacity, 4);
      expect(_center(machines: 4, shifts: 2).totalCapacity, 8);
      expect(_center(machines: 4, shifts: 3).totalCapacity, 12);
      expect(_center(machines: 4, shifts: '3').totalCapacity, 12);
    });
  });

  group('saved shifts vs the default', () {
    test('a saved value is kept, including 0', () {
      expect(savedShiftsOrDefault(1), 1);
      expect(savedShiftsOrDefault(3), 3);
      expect(savedShiftsOrDefault('3'), 3);
      expect(savedShiftsOrDefault(3.0), 3);
      expect(savedShiftsOrDefault(0), 0);
    });

    test('the default (2) applies only when the value is missing', () {
      for (final raw in [null, '', '  ', 'abc']) {
        expect(savedShiftsOrDefault(raw), defaultShiftsPerDay, reason: '$raw');
      }
      expect(defaultShiftsPerDay, 2);
      expect(_center(machines: 4).shifts, 2);
      expect(_center(machines: 4).totalCapacity, 8);
    });
  });

  group('Available (Est.) = total capacity − reserved', () {
    test('uses the same capacity for 1, 2 and 3 shifts', () {
      for (final (shifts, expected) in [(1, 6), (2, 16), (3, 26)]) {
        final center = _center(machines: 10, shifts: shifts);
        expect(
          estimatedAvailableSlots(
            totalCapacity: center.totalCapacity,
            reservedPatients: 4,
          ),
          expected,
          reason: '$shifts shifts',
        );
      }
    });

    test('reserved equal to or above capacity gives 0, never negative', () {
      expect(
        estimatedAvailableSlots(totalCapacity: 30, reservedPatients: 30),
        0,
      );
      expect(
        estimatedAvailableSlots(totalCapacity: 10, reservedPatients: 14),
        0,
      );
    });

    test('no reserved patients leaves the full capacity', () {
      expect(
        estimatedAvailableSlots(totalCapacity: 30, reservedPatients: 0),
        30,
      );
    });

    test('the saved Available Slots value is separate and untouched', () {
      final center = _center(machines: 10, shifts: 3, slots: 7);
      expect(center.totalCapacity, 30);
      expect(center.availableSlots, 7);
    });
  });

  testWidgets('details modal shows capacity for a 3-shift centre', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final center = _center(machines: 10, shifts: 3, slots: 7);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CenterDetailsDialog(
            center: center,
            reservedPatients: 12,
            estimatedAvailable: estimatedAvailableSlots(
              totalCapacity: center.totalCapacity,
              reservedPatients: 12,
            ),
          ),
        ),
      ),
    );

    expect(find.text('30'), findsOneWidget); // Total Capacity: 10 × 3
    expect(find.text('18'), findsOneWidget); // Available (Est.): 30 − 12
    expect(find.text('7'), findsOneWidget); // saved Available Slots
    expect(find.text('3'), findsOneWidget); // Shifts
  });
}
