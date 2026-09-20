// Layout regression tests for the Admin shell.
//
// These exist because of a real failure: a row of summary cards used
// `CrossAxisAlignment.stretch` directly inside the page's scroll view. A
// Row stretching on its cross axis hands each child a TIGHT height equal
// to the incoming maxHeight - which is `infinity` inside a vertically
// unbounded scroll view. The subtree then fails to lay out, and in a
// release build it simply paints nothing: both the Dashboard and the
// Patients page came up blank next to a perfectly healthy sidebar.
//
// Every case below therefore renders inside a real SingleChildScrollView,
// which is the only place the bug can appear.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/theme/app_theme.dart';
import 'package:admin_panel/widgets/admin_card_row.dart';

/// The page shell both Admin pages use: a scroll view whose child has
/// unbounded height.
Widget _inPageScroll(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTheme.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [child],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _card(String label, {double height = 80}) {
  return Container(
    height: height,
    decoration: AppTheme.card(),
    alignment: Alignment.center,
    child: Text(label),
  );
}

void main() {
  group('AdminCardRow inside a page scroll view', () {
    for (final width in const [480.0, 720.0, 1024.0, 1366.0, 1920.0, 2560.0]) {
      testWidgets('lays out at ${width.toInt()}px without failing', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _inPageScroll(
            AdminCardRow(
              width: width - 48,
              cards: [_card('A'), _card('B'), _card('C')],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The original bug surfaced here: an infinite-height child.
        expect(tester.takeException(), isNull);

        // All three cards are laid out, at a finite size, and on screen.
        for (final label in ['A', 'B', 'C']) {
          final size = tester.getSize(find.text(label));
          expect(size.isFinite, isTrue, reason: '$label has a finite size');
        }
      });
    }

    testWidgets('cards in one row share the tallest height', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _inPageScroll(
          AdminCardRow(
            width: 1552,
            cards: [
              _card('short', height: 60),
              _card('tall', height: 120),
              _card('mid', height: 90),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final heights = ['short', 'tall', 'mid']
          .map(
            (label) => tester
                .getSize(
                  find
                      .ancestor(
                        of: find.text(label),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .height,
          )
          .toSet();

      // Equal heights is the whole reason the row stretches.
      expect(heights.length, 1);
      expect(heights.single, 120);
    });

    testWidgets('stacks every card on a narrow window', (tester) async {
      tester.view.physicalSize = const Size(480, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _inPageScroll(
          AdminCardRow(width: 432, cards: [_card('A'), _card('B'), _card('C')]),
        ),
      );
      await tester.pumpAndSettle();

      final a = tester.getTopLeft(find.text('A'));
      final b = tester.getTopLeft(find.text('B'));
      final c = tester.getTopLeft(find.text('C'));

      expect(a.dx, b.dx);
      expect(b.dx, c.dx);
      expect(a.dy, lessThan(b.dy));
      expect(b.dy, lessThan(c.dy));
    });

    testWidgets('pairs cards at an in-between width', (tester) async {
      tester.view.physicalSize = const Size(760, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _inPageScroll(
          AdminCardRow(width: 712, cards: [_card('A'), _card('B'), _card('C')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // A and B side by side, C on its own line beneath them.
      expect(
        tester.getTopLeft(find.text('A')).dy,
        tester.getTopLeft(find.text('B')).dy,
      );
      expect(
        tester.getTopLeft(find.text('C')).dy,
        greaterThan(tester.getTopLeft(find.text('A')).dy),
      );
    });

    testWidgets('an empty or single-card row is still valid', (tester) async {
      await tester.pumpWidget(
        _inPageScroll(const AdminCardRow(cards: [], width: 1200)),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _inPageScroll(AdminCardRow(cards: [_card('only')], width: 1200)),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('only'), findsOneWidget);
    });
  });
}
