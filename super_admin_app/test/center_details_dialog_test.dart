import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/center_model.dart';
import 'package:super_admin_app/widgets/center_details_dialog.dart';

Future<void> _pump(
  WidgetTester tester,
  CenterModel center,
  Size size, {
  int? reserved,
  int? estimate,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CenterDetailsDialog(
          center: center,
          reservedPatients: reserved,
          estimatedAvailable: estimate,
        ),
      ),
    ),
  );
}

void main() {
  final full = CenterModel.fromJson({
    'id': '1',
    'name': 'Valenzuela Dialysis Center',
    'address': '12 Main St',
    'city': 'Valenzuela City',
    'requirements': ['Latest Laboratory Results', 'PDD Certification'],
    'machine': 5,
    'slots_available': 8, // distinct from the 10 total capacity
    'status': 'busy',
    'operating_hours': '7:00 AM - 5:00 PM',
    'shifts': 2,
    'contact_number': '09171234567',
    'created_at': '2026-03-15T12:00:00Z',
  });

  testWidgets('shows the saved centre information', (tester) async {
    await _pump(tester, full, const Size(1200, 1100), reserved: 4, estimate: 6);

    expect(find.text('Valenzuela Dialysis Center'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('7:00 AM - 5:00 PM'), findsOneWidget);
    expect(find.text('+63 917 123 4567'), findsOneWidget);
    expect(find.textContaining('PDD Certification'), findsOneWidget);
    // The address is shown once, under the name -- no separate section.
    expect(find.text('12 Main St, Valenzuela City'), findsOneWidget);
    expect(find.text('Center Address'), findsNothing);
    // Never the removed capacity labels.
    expect(find.text('Busy'), findsNothing);
    expect(find.text('Full'), findsNothing);
  });

  testWidgets('shows the capacity breakdown and created date moved out of '
      'the table', (tester) async {
    await _pump(tester, full, const Size(1200, 1100), reserved: 4, estimate: 6);

    expect(find.text('Total Capacity'), findsOneWidget);
    // Only the number -- no "(5 machines × 2 shifts)" explanation.
    expect(find.text('10'), findsOneWidget);
    expect(find.textContaining('machines ×'), findsNothing);
    expect(find.text('Reserved'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Available (Est.)'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Available Slots (saved)'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Mar 15, 2026'), findsOneWidget);
  });

  testWidgets('flags an estimate when reserved exceeds capacity', (
    tester,
  ) async {
    await _pump(
      tester,
      full,
      const Size(1200, 1100),
      reserved: 12,
      estimate: 0,
    );
    expect(find.text('0 · capacity exceeded'), findsOneWidget);
  });

  testWidgets('missing values read "Not set" / "Unavailable", never 0 or '
      'today', (tester) async {
    final sparse = CenterModel.fromJson({
      'id': '2',
      'name': 'Old Center',
      'status': 'closed',
    });
    await _pump(tester, sparse, const Size(1200, 1100));

    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    // Hours, contact number and created date.
    expect(find.text('Not set'), findsNWidgets(3));
    // Reserved and the estimate, when the live count is not available.
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(find.text('No requirements listed.'), findsOneWidget);
  });

  testWidgets('fits a phone-width screen without overflow', (tester) async {
    await _pump(tester, full, const Size(360, 780), reserved: 4, estimate: 6);
    expect(tester.takeException(), isNull);
    expect(find.text('Valenzuela Dialysis Center'), findsOneWidget);
  });
}
