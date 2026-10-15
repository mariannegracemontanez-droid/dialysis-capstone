import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/purchase_log.dart';
import 'package:super_admin_app/widgets/purchase_logs_section.dart';

Map<String, dynamic> _row(
  String id, {
  String clinic = 'Center A',
  String item = 'Dialyzer',
  Object amount = 100,
  String? purchaseDate,
  String? createdAt,
}) => {
  'id': id,
  'clinic_name': clinic,
  'item_name': item,
  'amount': amount,
  'purchase_date': purchaseDate,
  'created_at': createdAt,
};

void main() {
  group('purchaseLogsFromRows', () {
    test('maps the donation_purchase_logs columns', () {
      final logs = purchaseLogsFromRows([
        _row(
          '1',
          clinic: ' Center A ',
          item: 'Needles',
          amount: '250.50',
          purchaseDate: '2026-10-01T08:00:00Z',
        ),
      ]);

      expect(logs.single.id, '1');
      expect(logs.single.clinicName, 'Center A');
      expect(logs.single.itemName, 'Needles');
      expect(logs.single.amount, 250.5);
      expect(logs.single.date, DateTime.utc(2026, 10, 1, 8).toLocal());
    });

    test('one entry per id, latest values win (no duplicates)', () {
      final logs = purchaseLogsFromRows([
        _row('1', item: 'Old name', amount: 100),
        _row('2'),
        _row('1', item: 'Updated name', amount: 120),
      ]);

      expect(logs.length, 2);
      final updated = logs.firstWhere((log) => log.id == '1');
      expect(updated.itemName, 'Updated name');
      expect(updated.amount, 120);
    });

    test('newest first; falls back to created_at; undated last', () {
      final logs = purchaseLogsFromRows([
        _row('old', purchaseDate: '2026-01-01T00:00:00Z'),
        _row('undated'),
        _row('new', createdAt: '2026-06-01T00:00:00Z'),
      ]);
      expect(logs.map((log) => log.id), ['new', 'old', 'undated']);
    });

    test('tolerates missing fields and bad values', () {
      final logs = purchaseLogsFromRows([
        {'id': 'x', 'amount': 'abc'},
        'not a row',
      ]);
      expect(logs.single.amount, 0);
      expect(logs.single.clinicName, '');
      expect(logs.single.date, isNull);
    });
  });

  group('PurchaseLogsSection', () {
    Widget wrap(Future<List<PurchaseLog>> Function() loader) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PurchaseLogsSection(loader: loader, listenForChanges: false),
        ),
      ),
    );

    testWidgets('shows a loader, then the logs', (tester) async {
      final completer = Completer<List<PurchaseLog>>();
      await tester.pumpWidget(wrap(() => completer.future));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(
        purchaseLogsFromRows([
          _row('1', item: 'Dialyzer', purchaseDate: '2026-10-01T08:00:00Z'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dialyzer'), findsOneWidget);
      expect(find.text('Center A'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await tester.pumpWidget(wrap(() async => const []));
      await tester.pumpAndSettle();
      expect(find.text('No purchase logs yet'), findsOneWidget);
    });

    testWidgets('error state with retry', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        wrap(() async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return purchaseLogsFromRows([_row('1', item: 'Gloves')]);
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Purchase logs unavailable'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Gloves'), findsOneWidget);
    });
  });
}
