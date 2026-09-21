// Behaviour of the Super Admin notice system.
//
// The layering group is the reason this file exists: messages raised from a
// Super Admin page used to be snack bars, which the ScaffoldMessenger paints
// inside the page -- so a message raised while a modal was open landed at the
// bottom of the screen underneath it, unread. These tests open a real modal
// of each kind the portal uses, raise a notice from inside it, and check the
// notice is on top and the modal is untouched.
//
// It is deliberately the mirror of admin_panel/test/admin_notice_test.dart:
// both portals drive the same implementation
// (package:curenurture_notice), so the same expectations have to hold on
// both sides.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:super_admin_app/widgets/super_admin_notice.dart';

/// Pumps a page with one button that runs [onPressed].
Future<void> _host(
  WidgetTester tester,
  Future<void> Function(BuildContext context) onPressed,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => onPressed(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One frame plus the entrance animation.
Future<void> _settleEntrance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  tearDown(SuperAdminNotice.dismissAll);

  group('Success', () {
    testWidgets('closes itself after about four seconds', (tester) async {
      await _host(
        tester,
        (context) => SuperAdminNotice.success(context, 'Admin created.'),
      );

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.text('Admin created.'), findsOneWidget);
      expect(find.text('Success'), findsOneWidget);

      // Still up just before the deadline.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Admin created.'), findsOneWidget);

      // Gone shortly after it.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Admin created.'), findsNothing);
      expect(SuperAdminNotice.isShowing, isFalse);
    });

    testWidgets('has no OK button, only a close control', (tester) async {
      await _host(
        tester,
        (context) => SuperAdminNotice.success(context, 'Admin created.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.text('OK'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Admin created.'), findsNothing);
    });

    testWidgets('a click outside dismisses it', (tester) async {
      await _host(
        tester,
        (context) => SuperAdminNotice.success(context, 'Admin created.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      // Top-left corner is barrier, never the card.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Admin created.'), findsNothing);
    });
  });

  group('Info', () {
    testWidgets('closes itself after about five seconds', (tester) async {
      await _host(
        tester,
        (context) =>
            SuperAdminNotice.info(context, 'No pending registrations found.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.text('No pending registrations found.'), findsOneWidget);

      // Still up past the success deadline - info gets longer.
      await tester.pump(const Duration(seconds: 4, milliseconds: 500));
      expect(find.text('No pending registrations found.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No pending registrations found.'), findsNothing);
    });

    testWidgets('can also be closed by hand', (tester) async {
      await _host(
        tester,
        (context) => SuperAdminNotice.info(context, 'Already distributed.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Already distributed.'), findsNothing);
    });
  });

  group('Error', () {
    testWidgets('stays up until it is acknowledged', (tester) async {
      await _host(
        tester,
        (context) => SuperAdminNotice.error(context, 'Failed to save.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.text('Failed to save.'), findsOneWidget);

      // Far longer than any auto-dismiss window.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Failed to save.'), findsOneWidget);
      expect(SuperAdminNotice.isShowing, isTrue);
    });

    testWidgets('offers both an OK button and a close control', (tester) async {
      await _host(
        tester,
        (context) => SuperAdminNotice.error(context, 'Failed to save.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.widgetWithText(ElevatedButton, 'OK'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Failed to save.'), findsNothing);
    });

    testWidgets('a click outside does NOT dismiss it', (tester) async {
      await _host(
        tester,
        (context) => SuperAdminNotice.error(context, 'Failed to save.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));

      // An error the super admin has not seen must not be clickable-away.
      expect(find.text('Failed to save.'), findsOneWidget);
    });

    testWidgets('the X also acknowledges it', (tester) async {
      await _host(
        tester,
        (context) => SuperAdminNotice.error(context, 'Failed to save.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Failed to save.'), findsNothing);
    });
  });

  group('Warning / confirmation', () {
    testWidgets('does not auto-close and answers true on Continue', (
      tester,
    ) async {
      bool? answer;

      await _host(tester, (context) async {
        answer = await SuperAdminNotice.confirm(
          context,
          title: 'Delete this admin?',
          message: 'This action cannot be undone.',
          destructive: true,
        );
      });

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Delete this admin?'), findsOneWidget);
      expect(answer, isNull);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('answers false on Cancel', (tester) async {
      bool? answer;

      await _host(tester, (context) async {
        answer = await SuperAdminNotice.confirm(
          context,
          title: 'Decline this registration?',
          message: 'The applicant will be told.',
        );
      });

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(answer, isFalse);
    });

    testWidgets('a click outside does not answer it', (tester) async {
      bool? answer;

      await _host(tester, (context) async {
        answer = await SuperAdminNotice.confirm(
          context,
          title: 'Distribute this donation?',
          message: 'The funds will be released to the center.',
        );
      });

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Distribute this donation?'), findsOneWidget);
      expect(answer, isNull);
    });

    testWidgets('dismissing with the X is a "no", never a "yes"', (
      tester,
    ) async {
      bool? answer;

      await _host(tester, (context) async {
        answer = await SuperAdminNotice.confirm(
          context,
          title: 'Delete this admin?',
          message: 'This action cannot be undone.',
        );
      });

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(answer, isFalse);
    });
  });

  group('Layering over an open Super Admin modal', () {
    /// A page that opens a modal the way the portal does; the modal has a
    /// button that records a tap and raises a notice.
    ///
    /// [general] picks between the two kinds of modal the portal opens: the
    /// blurred `showGeneralDialog` used by Account Management, and the plain
    /// `showDialog` + `AlertDialog` used by the center form.
    Future<List<String>> openModal(
      WidgetTester tester, {
      required Future<void> Function(BuildContext context) raise,
      bool general = false,
    }) async {
      final taps = <String>[];

      Widget modal(BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Edit head nurse'),
          content: const SizedBox(height: 120, width: 200),
          actions: [
            ElevatedButton(
              onPressed: () {
                taps.add('save');
                raise(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (pageContext) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    if (general) {
                      showGeneralDialog<void>(
                        context: pageContext,
                        barrierDismissible: true,
                        barrierLabel: 'Edit head nurse',
                        pageBuilder: (dialogContext, _, _) =>
                            modal(dialogContext),
                      );
                    } else {
                      showDialog<void>(context: pageContext, builder: modal);
                    }
                  },
                  child: const Text('open modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open modal'));
      await tester.pumpAndSettle();
      expect(find.text('Edit head nurse'), findsOneWidget);

      return taps;
    }

    testWidgets('an error raised inside a modal is visible above it', (
      tester,
    ) async {
      await openModal(
        tester,
        raise: (context) =>
            SuperAdminNotice.error(context, 'Could not save the admin.'),
      );

      await tester.tap(find.text('Save'));
      await _settleEntrance(tester);

      // Both are in the tree; the notice is the one on top, because its
      // overlay entry was inserted after the dialog route's.
      expect(find.text('Edit head nurse'), findsOneWidget);
      expect(find.text('Could not save the admin.'), findsOneWidget);
    });

    testWidgets('the same holds for a blurred showGeneralDialog modal', (
      tester,
    ) async {
      await openModal(
        tester,
        general: true,
        raise: (context) =>
            SuperAdminNotice.error(context, 'Could not save the admin.'),
      );

      await tester.tap(find.text('Save'));
      await _settleEntrance(tester);

      expect(find.text('Edit head nurse'), findsOneWidget);
      expect(find.text('Could not save the admin.'), findsOneWidget);
    });

    testWidgets('the notice blocks clicks on the modal underneath', (
      tester,
    ) async {
      final taps = await openModal(
        tester,
        raise: (context) =>
            SuperAdminNotice.error(context, 'Could not save the admin.'),
      );

      final saveSpot = tester.getCenter(find.text('Save'));

      await tester.tap(find.text('Save'));
      await _settleEntrance(tester);
      expect(taps, ['save']);

      // Tapping where the modal's Save button sits must not reach it now.
      await tester.tapAt(saveSpot);
      await tester.pump(const Duration(milliseconds: 200));

      expect(taps, ['save'], reason: 'the barrier absorbed the second tap');
    });

    testWidgets('closing the notice leaves the modal exactly as it was', (
      tester,
    ) async {
      final taps = await openModal(
        tester,
        raise: (context) =>
            SuperAdminNotice.error(context, 'Could not save the admin.'),
      );

      await tester.tap(find.text('Save'));
      await _settleEntrance(tester);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Notice gone, modal still open and interactive again.
      expect(find.text('Could not save the admin.'), findsNothing);
      expect(find.text('Edit head nurse'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(taps, ['save', 'save']);
    });

    testWidgets('a confirmation raised inside a modal still answers', (
      tester,
    ) async {
      bool? answer;

      await openModal(
        tester,
        raise: (context) async {
          answer = await SuperAdminNotice.confirm(
            context,
            title: 'Discard changes?',
            message: 'Anything unsaved will be lost.',
          );
        },
      );

      await tester.tap(find.text('Save'));
      await _settleEntrance(tester);

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Edit head nurse'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(answer, isTrue);
      expect(find.text('Edit head nurse'), findsOneWidget);
    });
  });
}
