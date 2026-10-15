import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/center_model.dart';
import 'package:super_admin_app/utils/center_status.dart';

const _noon = TimeOfDay(hour: 12, minute: 0);
const _night = TimeOfDay(hour: 23, minute: 0);

CenterModel _center({Object? status, String? hours}) => CenterModel.fromJson({
  'id': 'c1',
  'name': 'Center',
  'status': status,
  'operating_hours': hours,
});

void main() {
  group('record status (Active / Inactive) from clinics.status', () {
    test('legacy and current values map without rewriting anything', () {
      for (final value in [
        'open',
        'busy',
        'full',
        'OPEN',
        ' Busy ',
        '',
        null,
      ]) {
        expect(
          centerRecordStatusOf(value),
          CenterRecordStatus.active,
          reason: '$value',
        );
      }
      for (final value in ['closed', 'CLOSED', ' closed ']) {
        expect(
          centerRecordStatusOf(value),
          CenterRecordStatus.inactive,
          reason: value,
        );
      }
    });

    test('activation writes open, deactivation writes the closed marker', () {
      expect(CenterRecordStatus.active.storedValue, 'open');
      expect(CenterRecordStatus.inactive.storedValue, 'closed');
      // Round-trips back to the same record status.
      for (final status in CenterRecordStatus.values) {
        expect(centerRecordStatusOf(status.storedValue), status);
      }
    });

    test('labels are Active and Inactive', () {
      expect(CenterRecordStatus.active.label, 'Active');
      expect(CenterRecordStatus.inactive.label, 'Inactive');
    });
  });

  group('availability (Open / Closed)', () {
    test('only Open and Closed exist', () {
      expect(CenterAvailability.values.map((a) => a.label), ['Open', 'Closed']);
    });

    test('active centre follows its operating hours', () {
      for (final legacy in ['open', 'busy', 'full']) {
        expect(
          centerAvailabilityOf(
            storedStatus: legacy,
            operatingHours: '7:00 AM - 5:00 PM',
            now: _noon,
          ),
          CenterAvailability.open,
          reason: legacy,
        );
        expect(
          centerAvailabilityOf(
            storedStatus: legacy,
            operatingHours: '7:00 AM - 5:00 PM',
            now: _night,
          ),
          CenterAvailability.closed,
          reason: legacy,
        );
      }
    });

    test('an inactive centre is never Open', () {
      expect(
        centerAvailabilityOf(
          storedStatus: 'closed',
          operatingHours: '12:00 AM - 11:59 PM',
          now: _noon,
        ),
        CenterAvailability.closed,
      );
    });

    test('missing or unreadable hours are Closed, never assumed open', () {
      for (final hours in [null, '', 'by appointment']) {
        expect(
          centerAvailabilityOf(
            storedStatus: 'open',
            operatingHours: hours,
            now: _noon,
          ),
          CenterAvailability.closed,
          reason: '$hours',
        );
      }
    });
  });

  group('CenterModel', () {
    test('exposes record status separately from availability', () {
      final inactive = _center(status: 'closed', hours: '7:00 AM - 5:00 PM');
      expect(inactive.isActive, isFalse);
      expect(inactive.recordStatus, CenterRecordStatus.inactive);
      expect(inactive.availability(now: _noon), CenterAvailability.closed);

      final busy = _center(status: 'busy', hours: '7:00 AM - 5:00 PM');
      expect(busy.isActive, isTrue);
      expect(busy.availability(now: _noon), CenterAvailability.open);
    });

    test('does not invent operating hours or a contact number', () {
      final center = _center(status: 'open');
      expect(center.operatingHours, isEmpty);
      expect(center.contactNumber, isEmpty);
      expect(center.availability(now: _noon), CenterAvailability.closed);
    });
  });
}
