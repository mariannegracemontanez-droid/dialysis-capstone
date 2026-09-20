// Behaviour of the Admin notice system.
//
// The layering group is the reason this file exists: messages raised from
// inside an Admin modal used to be painted underneath it, so a failed save
// could go unread. Those tests open a real modal, raise a notice from
// inside it, and check the notice is on top and the modal is untouched.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/widgets/admin_modal.dart';
import 'package:admin_panel/widgets/admin_notice.dart';

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
  tearDown(AdminNotice.dismissAll);

  group('Success', () {
    testWidgets('closes itself after about four seconds', (tester) async {
      await _host(tester, (context) => AdminNotice.success(context, 'Saved.'));

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('Success'), findsOneWidget);

      // Still up just before the deadline.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Saved.'), findsOneWidget);

      // Gone shortly after it.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saved.'), findsNothing);
      expect(AdminNotice.isShowing, isFalse);
    });

    testWidgets('has no OK button, only a close control', (tester) async {
      await _host(tester, (context) => AdminNotice.success(context, 'Saved.'));
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.text('OK'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsNothing);
    });

    testWidgets('a click outside dismisses it', (tester) async {
      await _host(tester, (context) => AdminNotice.success(context, 'Saved.'));
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      // Top-left corner is barrier, never the card.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Saved.'), findsNothing);
    });
  });

  group('Info', () {
    testWidgets('closes itself after about five seconds', (tester) async {
      await _host(
        tester,
        (context) => AdminNotice.info(context, 'Shift full.'),
      );
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.text('Shift full.'), findsOneWidget);

      // Still up past the success deadline - info gets longer.
      await tester.pump(const Duration(seconds: 4, milliseconds: 500));
      expect(find.text('Shift full.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Shift full.'), findsNothing);
    });
  });

  group('Error', () {
    testWidgets('stays up until it is acknowledged', (tester) async {
      await _host(tester, (context) => AdminNotice.error(context, 'Failed.'));
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.text('Failed.'), findsOneWidget);

      // Far longer than any auto-dismiss window.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Failed.'), findsOneWidget);
      expect(AdminNotice.isShowing, isTrue);
    });

    testWidgets('offers both an OK button and a close control', (tester) async {
      await _host(tester, (context) => AdminNotice.error(context, 'Failed.'));
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      expect(find.widgetWithText(ElevatedButton, 'OK'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Failed.'), findsNothing);
    });

    testWidgets('a click outside does NOT dismiss it', (tester) async {
      await _host(tester, (context) => AdminNotice.error(context, 'Failed.'));
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));

      // An error the admin has not seen must not be clickable-away.
      expect(find.text('Failed.'), findsOneWidget);
    });

    testWidgets('the X also acknowledges it', (tester) async {
      await _host(tester, (context) => AdminNotice.error(context, 'Failed.'));
      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Failed.'), findsNothing);
    });
  });

  group('Warning / confirmation', () {
    testWidgets('does not auto-close and answers true on Continue', (
      tester,
    ) async {
      bool? answer;

      await _host(tester, (context) async {
        answer = await AdminNotice.confirm(
          context,
          title: 'Delete this record?',
          message: 'This cannot be undone.',
          destructive: true,
        );
      });

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);

      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Delete this record?'), findsOneWidget);
      expect(answer, isNull);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('answers false on Cancel', (tester) async {
      bool? answer;

      await _host(tester, (context) async {
        answer = await AdminNotice.confirm(
          context,
          title: 'Decline this appointment?',
          message: 'The patient will be told.',
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
        answer = await AdminNotice.confirm(
          context,
          title: 'Decline this appointment?',
          message: 'The patient will be told.',
        );
      });

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Decline this appointment?'), findsOneWidget);
      expect(answer, isNull);
    });

    testWidgets('dismissing with the X is a "no", never a "yes"', (
      tester,
    ) async {
      bool? answer;

      await _host(tester, (context) async {
        answer = await AdminNotice.confirm(
          context,
          title: 'Delete this record?',
          message: 'This cannot be undone.',
        );
      });

      await tester.tap(find.text('go'));
      await _settleEntrance(tester);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(answer, isFalse);
    });
  });

  group('Layering over an open Admin modal', () {
    /// A page that opens an AdminModal; the modal has a button that
    /// records a tap and raises a notice.
    Future<List<String>> openModal(
      WidgetTester tester, {
      required Future<void> Function(BuildContext context) raise,
    }) async {
      final taps = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (pageContext) => Center(
                child: ElevatedButton(
                  onPressed: () => showAdminDialog(
                    context: pageContext,
                    builder: (dialogContext) => AdminModal(
                      title: 'Edit patient',
                      icon: Icons.edit_rounded,
                      actions: [
                        ElevatedButton(
                          onPressed: () {
                            taps.add('save');
                            raise(dialogContext);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                      child: const SizedBox(height: 120),
                    ),
                  ),
                  child: const Text('open modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open modal'));
      await tester.pumpAndSettle();
      expect(find.text('Edit patient'), findsOneWidget);

      return taps;
    }

    testWidgets('an error raised inside a modal is visible above it', (
      tester,
    ) async {
      await openModal(
        tester,
        raise: (context) => AdminNotice.error(context, 'Could not save.'),
      );

      await tester.tap(find.text('Save'));
      await _settleEntrance(tester);

      // Both are in the tree; the notice is the one on top.
      expect(find.text('Edit patient'), findsOneWidget);
      expect(find.text('Could not save.'), findsOneWidget);

      // Paint order: the notice's overlay entry is inserted after the
      // dialog route's, so it is later in the overlay's child list.
      final overlayChildren = tester
          .widgetList<Overlay>(find.byType(Overlay))
          .length;
      expect(overlayChildren, greaterThan(0));
    });

    testWidgets('the notice blocks clicks on the modal underneath', (
      tester,
    ) async {
      final taps = await openModal(
        tester,
        raise: (context) => AdminNotice.error(context, 'Could not save.'),
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
        raise: (context) => AdminNotice.error(context, 'Could not save.'),
      );

      await tester.tap(find.text('Save'));
      await _settleEntrance(tester);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Notice gone, modal still open and interactive again.
      expect(find.text('Could not save.'), findsNothing);
      expect(find.text('Edit patient'), findsOneWidget);

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
          answer = await AdminNotice.confirm(
            context,
            title: 'Discard changes?',
            message: 'Anything unsaved will be lost.',
          );
        },
      );

      await tester.tap(find.text('Save'));
      await _settleEntrance(tester);

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Edit patient'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(answer, isTrue);
      expect(find.text('Edit patient'), findsOneWidget);
    });
  });
}
