import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/widgets/super_admin_gate.dart';

Widget _gate(Future<bool> Function() verify) {
  return MaterialApp(
    home: SuperAdminGate(
      verify: verify,
      fallback: const Text('login'),
      child: const Text('dashboard'),
    ),
  );
}

void main() {
  group('SuperAdminGate', () {
    testWidgets('shows a spinner, not the dashboard, while verifying', (
      tester,
    ) async {
      final pending = Completer<bool>();
      await tester.pumpWidget(_gate(() => pending.future));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('dashboard'), findsNothing);

      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('dashboard'), findsOneWidget);
    });

    testWidgets('a superadmin session gets the dashboard', (tester) async {
      await tester.pumpWidget(_gate(() async => true));
      await tester.pumpAndSettle();

      expect(find.text('dashboard'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });

    testWidgets('any other session gets the login fallback', (tester) async {
      await tester.pumpWidget(_gate(() async => false));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('dashboard'), findsNothing);
    });

    testWidgets('a failed check fails closed to the login fallback', (
      tester,
    ) async {
      await tester.pumpWidget(_gate(() async => throw Exception('offline')));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('dashboard'), findsNothing);
    });
  });
}
