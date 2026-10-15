import 'package:flutter_test/flutter_test.dart';

import 'package:super_admin_app/main.dart';

void main() {
  // Replaces the default Flutter "Counter increments" template test, which
  // tested a counter this app never had. The init-error path is the one
  // MyApp build that needs no Supabase connection, so it can run here.
  testWidgets('shows the initialization error instead of crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(initError: 'missing SUPABASE_URL'));

    expect(find.text('Initialization Error'), findsOneWidget);
    expect(find.textContaining('missing SUPABASE_URL'), findsOneWidget);
  });
}
