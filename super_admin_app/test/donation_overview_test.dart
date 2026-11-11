import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/donation_overview.dart';
import 'package:super_admin_app/widgets/donation_overview_section.dart';

Map<String, dynamic> _row({
  required String status,
  String? env,
  String? paymentStatus,
  num? amount,
  int? centavos,
  String created = '2026-11-05T08:00:00Z',
}) =>
    {
      'status': status,
      'payment_environment': env,
      'payment_status': paymentStatus,
      'amount': amount,
      'amount_centavos': centavos,
      'created_at': created,
    };

void main() {
  final now = DateTime(2026, 11, 10);

  final rows = [
    // Legacy, Admin-verified (real money).
    _row(status: 'verified', amount: 1000, created: '2026-11-02T08:00:00Z'),
    _row(status: 'verified', amount: 250.50, created: '2026-09-15T08:00:00Z'),
    // Legacy, awaiting verification / rejected.
    _row(status: 'pending', amount: 300),
    _row(status: 'rejected', amount: 90),
    // Simulated checkouts: completed (status stays 'pending' by design), open, failed, cancelled.
    _row(status: 'pending', env: 'sandbox', paymentStatus: 'simulated_paid', amount: 200, centavos: 20000),
    _row(status: 'pending', env: 'sandbox', paymentStatus: 'pending', amount: 50, centavos: 5000),
    _row(status: 'rejected', env: 'sandbox', paymentStatus: 'failed', amount: 70, centavos: 7000),
    _row(status: 'rejected', env: 'sandbox', paymentStatus: 'cancelled', amount: 80, centavos: 8000),
    // A confirmed live payment is 'verified' -> collected.
    _row(status: 'verified', env: 'production', paymentStatus: 'paid', amount: 500, centavos: 50000, created: '2026-10-20T08:00:00Z'),
    // Outside the 6-month window: counted in totals, not in the trend.
    _row(status: 'verified', amount: 40, created: '2025-12-01T08:00:00Z'),
  ];

  group('DonationOverview.fromRows', () {
    final o = DonationOverview.fromRows(rows, now: now);

    test('collected funds = verified donations only, to the centavo', () {
      expect(o.collectedCentavos, 100000 + 25050 + 50000 + 4000);
      expect(o.collectedCount, 4);
    });

    test('simulated payments are activity, never collected funds', () {
      expect(o.simulatedCompletedCount, 1);
      expect(o.simulatedCompletedCentavos, 20000);
      // A simulated row can never land in the collected bucket, even if mislabelled verified.
      final odd = DonationOverview.fromRows(
          [_row(status: 'verified', env: 'sandbox', paymentStatus: 'simulated_paid', centavos: 999)], now: now);
      expect(odd.collectedCentavos, 0);
      expect(odd.simulatedCompletedCentavos, 999);
    });

    test('pending, failed, cancelled and rejected keep their own buckets', () {
      expect(o.awaitingVerificationCount, 1);
      expect(o.awaitingVerificationCentavos, 30000);
      expect(o.openCheckoutCount, 1);
      expect(o.failedOrCancelledCount, 2);
      expect(o.rejectedCount, 1);
      expect(o.transactionCount, rows.length);
    });

    test('monthly trend: 6 months ending this month, buckets add up', () {
      expect(o.trend.length, 6);
      expect(o.trend.first.month, DateTime(2026, 6));
      expect(o.trend.last.month, DateTime(2026, 11));
      final nov = o.trend.last;
      expect(nov.collectedCentavos, 100000);
      expect(nov.simulatedCount, 1);
      expect(nov.transactions, 7); // every row created 2026-11-xx
      expect(nov.otherCount, nov.transactions - nov.collectedCount - nov.simulatedCount);
      expect(o.trend.firstWhere((p) => p.month == DateTime(2026, 9)).collectedCentavos, 25050);
      expect(o.trend.firstWhere((p) => p.month == DateTime(2026, 10)).collectedCentavos, 50000);
      // The December 2025 donation is outside the window.
      expect(o.trend.fold<int>(0, (s, p) => s + p.transactions), rows.length - 1);
    });

    test('year boundary', () {
      final jan = DonationOverview.fromRows([_row(status: 'verified', amount: 1, created: '2026-10-01T08:00:00Z')],
          now: DateTime(2027, 1, 3), months: 4);
      expect(jan.trend.map((p) => p.month), [DateTime(2026, 10), DateTime(2026, 11), DateTime(2026, 12), DateTime(2027, 1)]);
      expect(jan.trend.first.collectedCentavos, 100);
    });
  });

  group('DonationOverviewSection', () {
    testWidgets('shows collected funds and simulated activity separately', (tester) async {
      tester.view.physicalSize = const Size(1500, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DonationOverviewSection(loader: () async => DonationOverview.fromRows(rows, now: now)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      Finder inKpi(String key, Finder f) => find.descendant(of: find.byKey(ValueKey(key)), matching: f);
      expect(inKpi('kpi-collected', find.text('₱1,790.50')), findsOneWidget);
      expect(inKpi('kpi-collected', find.text('4 verified donations')), findsOneWidget);
      expect(inKpi('kpi-checkouts', find.text('1 completed')), findsOneWidget);
      expect(inKpi('kpi-checkouts', find.textContaining('₱200.00 in simulated payments')), findsOneWidget);
      expect(inKpi('kpi-awaiting', find.text('1')), findsOneWidget);
      expect(inKpi('kpi-volume', find.text('${rows.length}')), findsOneWidget);
      expect(find.byKey(const ValueKey('trend-collected')), findsOneWidget);
      expect(find.byKey(const ValueKey('trend-activity')), findsOneWidget);
      expect(find.text('Simulated payment'), findsOneWidget); // legend
      // No centre-by-centre comparison on the dashboard.
      expect(find.textContaining('performance'), findsNothing);
    });

    testWidgets('error state offers a retry', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DonationOverviewSection(loader: () async => throw Exception('down'))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Donation figures could not be loaded.'), findsOneWidget);
      expect(find.textContaining('down'), findsNothing);
    });
  });
}
