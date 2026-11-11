import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/payment_transaction.dart';
import 'package:super_admin_app/widgets/payment_transactions_section.dart';

Map<String, dynamic> _row({
  required String id,
  required String status,
  String env = 'sandbox',
  String provider = 'internal_simulator',
  String mode = 'equal_distribution',
  int amount = 100000,
  String created = '2026-10-10T08:00:00Z',
  List<Map<String, dynamic>>? allocations,
}) {
  final allocationStatus = switch (status) {
    'simulated_paid' => 'simulated',
    'paid' => env == 'sandbox' ? 'simulated' : 'pending_payout',
    'failed' || 'cancelled' => 'void',
    _ => 'awaiting_payment',
  };
  return {
    'id': id,
    'reference_code': 'CN-SBX-$id',
    'created_at': created,
    'allocation_type': mode,
    'amount_centavos': amount,
    'payment_method': 'GCASH',
    'payment_provider': provider,
    'payment_environment': env,
    'payment_status': status,
    'donor_id': null,
    'name': null,
    'donation_allocations': allocations ??
        [
          {'clinic_id': 'c', 'clinic_name_snapshot': 'Gamma', 'amount_centavos': 33333, 'allocation_status': allocationStatus, 'sort_order': 3},
          {'clinic_id': 'a', 'clinic_name_snapshot': 'Alpha', 'amount_centavos': 33334, 'allocation_status': allocationStatus, 'sort_order': 1},
          {'clinic_id': 'b', 'clinic_name_snapshot': 'Beta', 'amount_centavos': 33333, 'allocation_status': allocationStatus, 'sort_order': 2},
        ],
  };
}

void main() {
  group('PaymentTransaction', () {
    test('parses allocations in server order and totals them exactly', () {
      final t = PaymentTransaction.fromJson(_row(id: '1', status: 'simulated_paid'));
      expect(t.allocations.map((a) => a.clinicName), ['Alpha', 'Beta', 'Gamma']);
      expect(t.allocatedCentavos, t.amountCentavos);
      expect(t.isSandbox, isTrue);
      expect(t.donorLabel, 'Anonymous Donor');
      expect(t.paymentStatusLabel, 'Completed (simulated)');
      expect(t.paymentTypeLabel, 'Simulated payment');
      expect(t.providerLabel, 'Payment simulator');
      expect(t.isCompleted, isTrue);
      expect(t.countsAsCollectedFunds, isFalse);
    });

    test('only a confirmed live payment is labelled Paid / Live payment', () {
      final live = PaymentTransaction.fromJson(_row(id: '9', status: 'paid', env: 'production', provider: 'paymongo'));
      expect(live.paymentStatusLabel, 'Paid');
      expect(live.paymentTypeLabel, 'Live payment');
      expect(live.countsAsCollectedFunds, isTrue);
      final test = PaymentTransaction.fromJson(_row(id: '8', status: 'paid', provider: 'paymongo'));
      expect(test.paymentStatusLabel, 'Completed (test mode)');
      expect(test.paymentTypeLabel, 'PayMongo test mode');
      expect(test.countsAsCollectedFunds, isFalse);
    });

    test('simulated allocations are never labelled as payouts', () {
      final t = PaymentTransaction.fromJson(_row(id: '1', status: 'simulated_paid'));
      for (final a in t.allocations) {
        expect(a.statusLabel, contains('no funds transferred'));
        expect(a.statusLabel.toLowerCase(), isNot(contains('paid out')));
      }
    });
  });

  group('PaymentTransactionSummary', () {
    final rows = [
      PaymentTransaction.fromJson(_row(id: '1', status: 'simulated_paid')),
      PaymentTransaction.fromJson(_row(id: '2', status: 'paid', provider: 'paymongo')),
      PaymentTransaction.fromJson(_row(id: '3', status: 'failed')),
      PaymentTransaction.fromJson(_row(id: '4', status: 'cancelled')),
      PaymentTransaction.fromJson(_row(id: '5', status: 'pending')),
      PaymentTransaction.fromJson(_row(id: '6', status: 'paid', env: 'production', provider: 'paymongo', amount: 50000,
          allocations: [{'clinic_id': 'a', 'clinic_name_snapshot': 'Alpha', 'amount_centavos': 50000, 'allocation_status': 'pending_payout', 'sort_order': 1}])),
      PaymentTransaction.fromJson(_row(id: '7', status: 'failed', env: 'production', provider: 'paymongo')),
    ];
    final s = PaymentTransactionSummary.of(rows);

    test('sandbox amounts are never counted as collected funds', () {
      expect(s.collectedCentavos, 50000); // only the confirmed production payment
      // Completed checkouts are activity: 2 simulated/test + 1 live.
      expect(s.completedCount, 3);
      expect(s.simulatedCompletedCount, 2);
      expect(s.completedCentavos, 250000);
      expect(s.completedCentavos - s.collectedCentavos, 200000); // simulated part, never collected
    });

    test('failed and cancelled payments are excluded from successful totals', () {
      expect(s.failedOrCancelledCount, 3);
      expect(s.openCount, 1);
      expect(s.count, 7);
    });
  });

  group('PaymentTransactionFilter', () {
    final a = PaymentTransaction.fromJson(_row(id: '1', status: 'simulated_paid', created: '2026-10-01T10:00:00Z'));
    final b = PaymentTransaction.fromJson(_row(
      id: '2', status: 'failed', mode: 'specific_center', amount: 5000, created: '2026-10-12T10:00:00Z',
      allocations: [{'clinic_id': 'z', 'clinic_name_snapshot': 'Zeta', 'amount_centavos': 5000, 'allocation_status': 'void', 'sort_order': 1}],
    ));

    test('filters by mode, status, environment and recipient center', () {
      expect(const PaymentTransactionFilter(mode: 'specific_center').matches(a), isFalse);
      expect(const PaymentTransactionFilter(mode: 'specific_center').matches(b), isTrue);
      expect(const PaymentTransactionFilter(paymentStatus: 'failed').matches(b), isTrue);
      expect(const PaymentTransactionFilter(environment: 'production').matches(a), isFalse);
      expect(const PaymentTransactionFilter(clinicId: 'b').matches(a), isTrue);
      expect(const PaymentTransactionFilter(clinicId: 'b').matches(b), isFalse);
    });

    test('search matches reference, donor label or recipient name', () {
      expect(const PaymentTransactionFilter(query: 'cn-sbx-2').matches(b), isTrue);
      expect(const PaymentTransactionFilter(query: 'cn-sbx-2').matches(a), isFalse);
      expect(const PaymentTransactionFilter(query: 'zeta').matches(b), isTrue);
      expect(const PaymentTransactionFilter(query: 'anonymous').matches(a), isTrue);
      expect(const PaymentTransactionFilter(query: '   ').matches(a), isTrue);
    });

    test('date range includes the whole last day', () {
      final f = PaymentTransactionFilter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 12));
      expect(f.matches(a), isTrue);
      expect(f.matches(b), isTrue);
      expect(PaymentTransactionFilter(from: DateTime(2026, 10, 5)).matches(a), isFalse);
    });
  });

  test('formatCentavosPhp', () {
    expect(formatCentavosPhp(100000), '₱1,000.00');
    expect(formatCentavosPhp(33334), '₱333.34');
  });

  group('PaymentTransactionsSection', () {
    Future<void> pump(WidgetTester tester, List<PaymentTransaction> rows) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 2000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaymentTransactionsSection(loader: () async => rows),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps simulated payments out of collected funds; no ENV / status columns', (tester) async {
      await pump(tester, [
        PaymentTransaction.fromJson(_row(id: '1', status: 'simulated_paid')),
        PaymentTransaction.fromJson(_row(id: '2', status: 'failed')),
      ]);

      final collected = find.byKey(const ValueKey('tx-tile-collected'));
      expect(find.descendant(of: collected, matching: find.text('₱0.00')), findsOneWidget);
      final activity = find.byKey(const ValueKey('tx-tile-activity'));
      expect(find.descendant(of: activity, matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: activity, matching: find.textContaining('1 simulated, not collected')), findsOneWidget);
      expect(find.byKey(const ValueKey('tx-simulated-note')), findsOneWidget);
      expect(find.text('₱1,000.00'), findsWidgets);
      // The removed columns and the old sandbox labels are gone from the table.
      expect(find.text('ENV'), findsNothing);
      expect(find.text('PAYMENT STATUS'), findsNothing);
      expect(find.text('SANDBOX'), findsNothing);
      expect(find.textContaining('Sandbox completed'), findsNothing);
      // Read-only: no way to mark anything as paid.
      expect(find.textContaining('Mark as paid'), findsNothing);
      expect(find.textContaining('Approve'), findsNothing);
    });

    testWidgets('search narrows the list by reference', (tester) async {
      await pump(tester, [
        PaymentTransaction.fromJson(_row(id: '1', status: 'simulated_paid')),
        PaymentTransaction.fromJson(_row(id: '2', status: 'failed')),
      ]);
      await tester.enterText(find.byKey(const ValueKey('tx-search')), 'CN-SBX-2');
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 transactions'), findsOneWidget);
      final table = find.byType(DataTable);
      expect(find.descendant(of: table, matching: find.text('CN-SBX-2')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('CN-SBX-1')), findsNothing);
    });

    testWidgets('opens the recipient allocation breakdown', (tester) async {
      await pump(tester, [PaymentTransaction.fromJson(_row(id: '1', status: 'simulated_paid'))]);

      await tester.ensureVisible(find.byKey(const ValueKey('tx-view-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tx-view-1')));
      await tester.pumpAndSettle();

      expect(find.text('Donation CN-SBX-1'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('₱333.34'), findsOneWidget);
      expect(find.text('₱333.33'), findsNWidgets(2));
      expect(find.textContaining('(matches donation total)'), findsOneWidget);
      expect(find.text('Simulated — no funds transferred'), findsNWidgets(3));
      // Status and payment type live in the details, with the underlying state intact.
      expect(find.descendant(of: find.byKey(const ValueKey('tx-detail-status')), matching: find.text('Completed (simulated)')),
          findsOneWidget);
      expect(find.text('Simulated payment'), findsOneWidget);
      expect(find.textContaining('No funds were transferred'), findsOneWidget);
    });

    testWidgets('failed and cancelled keep their status in the details', (tester) async {
      await pump(tester, [
        PaymentTransaction.fromJson(_row(id: '3', status: 'failed')),
        PaymentTransaction.fromJson(_row(id: '4', status: 'cancelled')),
      ]);
      for (final (id, label) in [('3', 'Failed'), ('4', 'Cancelled')]) {
        await tester.ensureVisible(find.byKey(ValueKey('tx-view-$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('tx-view-$id')));
        await tester.pumpAndSettle();
        expect(find.descendant(of: find.byKey(const ValueKey('tx-detail-status')), matching: find.text(label)), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('shows an empty state', (tester) async {
      await pump(tester, const []);
      expect(find.text('No GCash checkout transactions yet.'), findsOneWidget);
    });
  });
}
