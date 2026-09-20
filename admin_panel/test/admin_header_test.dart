// The Admin header: where the head nurse's name now lives, and the way
// through to Center Profile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/widgets/admin_header.dart';

Widget _host({
  String? adminName,
  String? centerName,
  bool centerProfileActive = false,
  VoidCallback? onOpen,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          AdminHeader(
            adminName: adminName,
            centerName: centerName,
            centerProfileActive: centerProfileActive,
            onOpenCenterProfile: onOpen ?? () {},
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('greets the signed-in head nurse by name', (tester) async {
    await tester.pumpWidget(
      _host(adminName: 'Maria Santos', centerName: 'Valenzuela Dialysis'),
    );

    expect(find.text('Hello, Maria Santos'), findsOneWidget);
    expect(find.text('Valenzuela Dialysis'), findsOneWidget);
  });

  testWidgets('falls back to a bare greeting while the profile loads', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    // Never a placeholder name, which would read as a real one.
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('a blank name is treated as no name', (tester) async {
    await tester.pumpWidget(_host(adminName: '   '));

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('offers a way into Center Profile', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(adminName: 'Maria Santos', onOpen: () => opened++),
    );

    expect(find.text('Center Profile'), findsOneWidget);

    await tester.tap(find.text('Center Profile'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('on the Center Profile page the button is inert', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        adminName: 'Maria Santos',
        centerProfileActive: true,
        onOpen: () => opened++,
      ),
    );

    // Still labelled, so the header does not shift on navigation, but
    // tapping it cannot re-push the page you are already on.
    expect(find.text('Center Profile'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.tap(find.text('Center Profile'));
    await tester.pump();

    expect(opened, 0);
  });

  testWidgets('lays out without overflow across desktop widths', (
    tester,
  ) async {
    for (final width in [1024.0, 1366.0, 1920.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          adminName: 'Maria Santos-Villanueva De La Cruz',
          centerName: 'Valenzuela City Dialysis and Wellness Center',
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'at ${width}px');
    }
  });
}
