import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/center_donation_history_entry.dart';
import 'package:super_admin_app/models/donation_history_status.dart';
import 'package:super_admin_app/models/donation_record.dart';

/// A `donations` row as the Donation app's create_donation_checkout() writes it.
Map<String, dynamic> _checkout({
  required String id,
  required String paymentStatus,
  required String status,
  String mode = 'specific_center',
  String? clinicId = 'c-dell',
  String? clinicName = 'Dell Center',
  num amount = 250,
  String? name,
  String? email,
  String? donorId,
  String created = '2026-11-10T03:00:00Z',
}) =>
    {
      'id': id,
      'reference_code': 'CN-SBX-$id',
      'amount': amount,
      'amount_centavos': (amount * 100).round(),
      'status': status,
      'payment_status': paymentStatus,
      'payment_environment': 'sandbox',
      'payment_method': 'GCASH',
      'allocation_type': mode,
      'clinic_id': mode == 'equal_distribution' ? null : clinicId,
      'clinics': mode == 'equal_distribution' ? null : {'name': clinicName},
      'donor_id': donorId,
      'name': name,
      'email': email,
      'created_at': created,
    };

/// An older (pre-checkout) donation row.
Map<String, dynamic> _legacy({
  required String id,
  required String status,
  num amount = 1000,
  String? clinicId = 'c-dell',
  String mode = 'specific_center',
  String created = '2026-09-01T03:00:00Z',
}) =>
    {
      'id': id,
      'amount': amount,
      'status': status,
      'allocation_type': mode,
      'clinic_id': clinicId,
      'clinics': clinicId == null ? null : {'name': 'Dell Center'},
      'donor_id': 'u-1',
      'name': 'Original Donor',
      'email': 'donor@example.invalid',
      'created_at': created,
    };

void main() {
  group('status labels match Donation Transactions', () {
    test('checkout rows use payment_status, never the legacy status column', () {
      String label(String paymentStatus, String status) =>
          donationHistoryStatusLabel(status: status, paymentStatus: paymentStatus, paymentEnvironment: 'sandbox');
      // A completed simulated payment keeps status 'pending' in the database.
      expect(label('simulated_paid', 'pending'), 'Completed (simulated)');
      expect(label('pending', 'pending'), 'Pending');
      expect(label('processing', 'pending'), 'Processing');
      // Failed / cancelled checkouts carry status 'rejected'; they are not "Rejected" donations.
      expect(label('failed', 'rejected'), 'Failed');
      expect(label('cancelled', 'rejected'), 'Cancelled');
      expect(label('paid', 'pending'), 'Completed (test mode)');
    });

    test('older donations keep their original labels', () {
      expect(donationHistoryStatusLabel(status: 'verified'), 'Received');
      expect(donationHistoryStatusLabel(status: 'rejected'), 'Rejected');
      expect(donationHistoryStatusLabel(status: 'pending'), 'Pending');
    });

    test('only a verified, non-sandbox donation counts as received', () {
      expect(countsAsReceived(status: 'verified'), isTrue);
      expect(countsAsReceived(status: 'verified', paymentEnvironment: 'production'), isTrue);
      expect(countsAsReceived(status: 'verified', paymentEnvironment: 'sandbox'), isFalse);
      expect(countsAsReceived(status: 'pending', paymentEnvironment: 'sandbox'), isFalse); // simulated_paid row
      expect(countsAsReceived(status: 'rejected', paymentEnvironment: 'sandbox'), isFalse);
      expect(donationHistoryTone(status: 'pending', paymentStatus: 'simulated_paid', paymentEnvironment: 'sandbox'),
          DonationHistoryTone.simulated);
      expect(donationHistoryTone(status: 'verified'), DonationHistoryTone.received);
    });
  });

  group('Overall Donation History, All Centers (DonationRecord)', () {
    final rows = [
      _checkout(id: 'A1', paymentStatus: 'simulated_paid', status: 'pending', name: 'Reg Donor', email: 'reg@example.invalid', donorId: 'u-9'),
      _checkout(id: 'A2', paymentStatus: 'failed', status: 'rejected', mode: 'random_center'),
      _checkout(id: 'A3', paymentStatus: 'pending', status: 'pending'),
      _checkout(id: 'A4', paymentStatus: 'simulated_paid', status: 'pending', mode: 'equal_distribution', amount: 300),
      _legacy(id: 'L1', status: 'verified'),
      _legacy(id: 'L2', status: 'rejected'),
    ];
    final records = [for (final r in rows) DonationRecord.fromJson(r)];

    test('every Donation-app checkout is a visible record, with its reference', () {
      expect(records, hasLength(6));
      expect(records.where((d) => d.reference != null).map((d) => d.reference),
          ['CN-SBX-A1', 'CN-SBX-A2', 'CN-SBX-A3', 'CN-SBX-A4']);
      expect(records.last.reference, isNull); // older donation
    });

    test('statuses, amounts, donors and centers come straight from the row', () {
      final a1 = records[0];
      expect(a1.historyStatusLabel, 'Completed (simulated)');
      expect(a1.amount, 250);
      expect(a1.donorName, 'Reg Donor');
      expect(a1.email, 'reg@example.invalid');
      expect(a1.clinicName, 'Dell Center');
      expect(records[1].historyStatusLabel, 'Failed');
      expect(records[1].isAnonymous, isTrue);
      expect(records[2].historyStatusLabel, 'Pending');
      expect(records[3].allocationType, 'equal_distribution');
      expect(records[3].clinicId, isNull);
      expect(records[4].historyStatusLabel, 'Received');
      expect(records[5].historyStatusLabel, 'Rejected');
    });

    test('simulated payments are never counted as received / verified funds', () {
      final received = records.where((d) => d.isReceived).toList();
      expect(received.map((d) => d.id), ['L1']);
      final receivedTotal = received.fold<double>(0, (s, d) => s + d.amount);
      expect(receivedTotal, 1000); // the simulated ₱250 + ₱300 never add to it
      expect(records.where((d) => d.status == 'verified' && d.reference != null), isEmpty);
    });
  });

  group('Overall Donation History, one center selected (centerHistoryFromRows)', () {
    test('a specific/random checkout appears once, at its full amount (no double count)', () {
      final direct = [_checkout(id: 'S1', paymentStatus: 'simulated_paid', status: 'pending', amount: 200)];
      // The same checkout's single allocation row, parent clinic_id set.
      final shares = [
        {
          'donation_id': 'S1',
          'amount': 200,
          'created_at': '2026-11-10T03:00:00Z',
          'donations': {'status': 'pending', 'clinic_id': 'c-dell', 'payment_environment': 'sandbox',
              'payment_status': 'simulated_paid', 'reference_code': 'CN-SBX-S1'},
        },
      ];
      final entries = centerHistoryFromRows(direct, shares);
      expect(entries, hasLength(1));
      expect(entries.single.reference, 'CN-SBX-S1');
      expect(entries.single.amount, 200);
      expect(entries.single.statusLabel, 'Completed (simulated)');
      expect(entries.single.isReceived, isFalse);
    });

    test('equal-split checkouts list this center\'s share with the parent reference and status', () {
      final shares = [
        {
          'donation_id': 'E1',
          'amount': 33.34,
          'created_at': '2026-11-10T04:00:00Z',
          'donations': {'status': 'pending', 'clinic_id': null, 'payment_environment': 'sandbox',
              'payment_status': 'simulated_paid', 'reference_code': 'CN-SBX-E1', 'name': null, 'email': null},
        },
        {
          'donation_id': 'E2',
          'amount': 10,
          'created_at': '2026-11-10T05:00:00Z',
          'donations': {'status': 'rejected', 'clinic_id': null, 'payment_environment': 'sandbox',
              'payment_status': 'cancelled', 'reference_code': 'CN-SBX-E2'},
        },
        // An older equal-split share (no checkout fields) still appears as before.
        {
          'donation_id': 'L9',
          'amount': 50,
          'created_at': '2026-09-01T05:00:00Z',
          'donations': {'status': 'verified', 'clinic_id': null},
        },
      ];
      final entries = centerHistoryFromRows(const [], shares);
      expect(entries.map((e) => e.donationId), ['E2', 'E1', 'L9']); // newest first
      final e1 = entries.firstWhere((e) => e.donationId == 'E1');
      expect(e1.amount, 33.34);
      expect(e1.allocationType, 'equal_distribution');
      expect(e1.reference, 'CN-SBX-E1');
      expect(e1.statusLabel, 'Completed (simulated)');
      expect(entries.firstWhere((e) => e.donationId == 'E2').statusLabel, 'Cancelled');
      final l9 = entries.firstWhere((e) => e.donationId == 'L9');
      expect(l9.statusLabel, 'Received');
      expect(l9.isReceived, isTrue);
      // Only the older verified share is money received.
      expect(entries.where((e) => e.isReceived).map((e) => e.donationId), ['L9']);
    });

    test('a center\'s total share of one split donation is not repeated', () {
      final shares = [
        for (final (id, amount) in [('E1', 33.34), ('E3', 25.0)])
          {
            'donation_id': id,
            'amount': amount,
            'created_at': '2026-11-10T04:00:00Z',
            'donations': {'status': 'pending', 'clinic_id': null, 'payment_environment': 'sandbox',
                'payment_status': 'simulated_paid', 'reference_code': 'CN-SBX-$id'},
          },
      ];
      final entries = centerHistoryFromRows(const [], shares);
      expect(entries.map((e) => e.donationId).toSet(), hasLength(entries.length));
      expect(entries.fold<double>(0, (s, e) => s + e.amount), closeTo(58.34, 1e-9));
    });
  });
}
