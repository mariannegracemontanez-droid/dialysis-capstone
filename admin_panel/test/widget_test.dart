// Smoke tests for the Admin panel shell.
//
// This file previously held the unmodified "counter" test that
// `flutter create` generates; the app has never had a counter, so it
// could only ever fail. It now covers what the shell actually has to do:
// render the login page, and lay the sidebar out across desktop widths
// without clipping or overflowing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/features/auth/login_page.dart';
import 'package:admin_panel/main.dart';
import 'package:admin_panel/theme/app_theme.dart';
import 'package:admin_panel/widgets/admin_sidebar.dart';
import 'package:admin_panel/widgets/admin_title.dart';

void main() {
  testWidgets('the app opens on the login page', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('CureNurture Center Portal'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the login page sits on a light ground', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.canvas);
  });

  group('Page titles', () {
    testWidgets('the login page names itself in the browser tab', (
      tester,
    ) async {
      await tester.pumpWidget(const MyApp());
      await tester.pump();

      // MaterialApp installs a Title of its own from `MaterialApp.title`,
      // so the page's own one is the innermost.
      final title = tester.widget<Title>(
        find.descendant(
          of: find.byType(LoginPage),
          matching: find.byType(Title),
        ),
      );
      expect(title.title, 'CureNurture | Admin Sign In');
      // The dev-server address must never be what the tab shows.
      expect(title.title, isNot(contains('localhost')));
    });

    test('every page title is prefixed with the product name', () {
      expect(
        AdminTitle.titleFor('Admin Dashboard'),
        'CureNurture | Admin Dashboard',
      );
      expect(AdminTitle.titleFor('Patients'), 'CureNurture | Patients');
    });
  });

  group('AdminSidebar', () {
    Widget host(int selected, void Function(int) onSelect) {
      return MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminSidebar(
                selectedIndex: selected,
                onSelect: onSelect,
                onLogout: () {},
                centerName: 'Valenzuela Dialysis Center',
                machineCount: 10,
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );
    }

    testWidgets('shows both destinations and a log out button', (tester) async {
      await tester.pumpWidget(host(AdminNav.dashboard, (_) {}));

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Patients'), findsOneWidget);
      // The Patients page previously had no way to sign out.
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('the brand block carries no head nurse name', (tester) async {
      await tester.pumpWidget(host(AdminNav.dashboard, (_) {}));

      // The name moved to AdminHeader. What is left under the wordmark
      // is the portal, not the person.
      expect(find.text('CureNurture'), findsOneWidget);
      expect(find.text('Center Portal'), findsOneWidget);
      expect(find.text('Maria Santos'), findsNothing);
    });

    testWidgets('an unlisted destination highlights nothing', (tester) async {
      // Center Profile is reached from the header, so it has no sidebar
      // row -- every row must then read as inactive rather than one of
      // them staying lit from the previous page.
      await tester.pumpWidget(host(AdminNav.centerProfile, (_) {}));

      final items = tester
          .widgetList<AdminSidebarItem>(find.byType(AdminSidebarItem))
          .toList();

      expect(items, isNotEmpty);
      expect(items.every((item) => !item.selected), isTrue);
    });

    testWidgets('the active destination uses a CureNurture blue block', (
      tester,
    ) async {
      await tester.pumpWidget(host(AdminNav.patients, (_) {}));

      final items = tester
          .widgetList<AdminSidebarItem>(find.byType(AdminSidebarItem))
          .toList();

      final patients = items.firstWhere((item) => item.label == 'Patients');
      final dashboard = items.firstWhere((item) => item.label == 'Dashboard');

      expect(patients.selected, isTrue);
      expect(dashboard.selected, isFalse);

      final decoration =
          tester
                  .widgetList<AnimatedContainer>(
                    find.descendant(
                      of: find.byWidget(patients),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;

      expect(decoration.color, AppTheme.blue1);
    });

    testWidgets('reports the tapped destination', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(host(AdminNav.dashboard, tapped.add));

      await tester.tap(find.text('Patients'));
      await tester.pump();

      expect(tapped, [AdminNav.patients]);
    });

    for (final size in const [
      Size(1024, 720), // small desktop
      Size(1366, 768), // standard laptop
      Size(1920, 1080), // large monitor
      Size(2560, 1440), // very large monitor
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(AdminNav.dashboard, (_) {}));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final width = tester.getSize(find.byType(AdminSidebar)).width;
        expect(width, AppTheme.sidebarWidth(size.width));
        // Narrower than the old 240px shell, but still comfortable.
        expect(width, greaterThanOrEqualTo(220));
        expect(width, lessThanOrEqualTo(260));
      });
    }
  });
}
