import 'package:CureNurture/models/clinic_announcement.dart';
import 'package:CureNurture/pages/home/clinic_info_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClinicAnnouncement _announcement(
  int n, {
  String? title,
  String? body,
  String color = 'blue',
  DateTime? date,
}) {
  return ClinicAnnouncement(
    id: 'a$n',
    title: title ?? 'Announcement $n',
    body: body ?? 'Body of announcement $n.',
    color: color,
    announcementDate: date,
    createdAt: DateTime(2026, 9, 20 + n, 9, 30),
  );
}

final String _longText = List.filled(
  60,
  'The clinic will be closed for maintenance and all sessions move.',
).join(' ');

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 780),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: ListView(padding: const EdgeInsets.all(20), children: [child]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _announcements(
  List<ClinicAnnouncement> items, {
  bool isLoading = false,
  bool hasError = false,
  VoidCallback? onRetry,
}) {
  return ClinicAnnouncementsSection(
    isLoading: isLoading,
    hasError: hasError,
    clinicName: 'Sunrise Dialysis Center',
    announcements: items,
    onRetry: onRetry ?? () {},
  );
}

Widget _rules(String rules, {bool hasError = false}) {
  return ClinicHouseRulesSection(
    isLoading: false,
    hasError: hasError,
    clinicName: 'Sunrise Dialysis Center',
    houseRules: rules,
    onRetry: () {},
  );
}

void main() {
  group('Clinic Announcements', () {
    testWidgets('loading state', (tester) async {
      await _pump(tester, _announcements(const [], isLoading: true));
      expect(find.text('Loading clinic announcements...'), findsOneWidget);
    });

    testWidgets('no announcements shows an empty state', (tester) async {
      await _pump(tester, _announcements(const []));
      expect(find.textContaining('No announcements right now'), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('error state offers retry', (tester) async {
      var retried = 0;
      await _pump(
        tester,
        _announcements(const [], hasError: true, onRetry: () => retried++),
      );
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('one announcement has no navigation', (tester) async {
      await _pump(tester, _announcements([_announcement(1)]));
      expect(find.text('Announcement 1'), findsOneWidget);
      expect(find.byTooltip('Next announcement'), findsNothing);
      expect(find.text('1 / 1'), findsNothing);
    });

    testWidgets('next/previous buttons and position indicator', (
      tester,
    ) async {
      await _pump(
        tester,
        _announcements([_announcement(1), _announcement(2), _announcement(3)]),
      );
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Next announcement'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Announcement 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next announcement'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);

      // At the end, Next is disabled.
      await tester.tap(find.byTooltip('Next announcement'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous announcement'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('swipe left/right moves between announcements', (
      tester,
    ) async {
      await _pump(
        tester,
        _announcements([_announcement(1), _announcement(2), _announcement(3)]),
      );

      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('many announcements fall back to the counter only', (
      tester,
    ) async {
      await _pump(
        tester,
        _announcements(List.generate(12, (i) => _announcement(i + 1))),
      );
      expect(find.text('1 / 12'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long content stays fixed-height and opens full details', (
      tester,
    ) async {
      final long = _announcement(
        1,
        title: 'A very long holiday schedule announcement title ' * 4,
        body: _longText,
        color: 'red',
        date: DateTime(2026, 12, 25),
      );
      await _pump(tester, _announcements([long, _announcement(2)]));
      expect(tester.takeException(), isNull);

      final pageViewHeight = tester.getSize(find.byType(PageView)).height;
      expect(pageViewHeight, 170);
      expect(find.text('Urgent'), findsOneWidget);

      await tester.tap(find.text('Tap to read full announcement').first);
      await tester.pumpAndSettle();

      // Full title/body are rendered in the sheet, with the date and clinic.
      expect(find.text(_longText), findsNWidgets(2));
      expect(find.text('Friday, December 25, 2026'), findsOneWidget);
      expect(find.text('Sunrise Dialysis Center'), findsOneWidget);
      expect(find.text('1 / 2'), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      // The long body scrolls inside the sheet; Close stays reachable.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('detail sheet closes with the X button', (tester) async {
      await _pump(tester, _announcements([_announcement(1)]));
      await tester.tap(find.text('Announcement 1'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('small screen with large text does not overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        _announcements([
          _announcement(1, title: 'Long title ' * 10, body: _longText),
          _announcement(2),
        ]),
        size: const Size(320, 640),
        textScale: 1.4,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('unknown colour token falls back to the default style', (
      tester,
    ) async {
      await _pump(tester, _announcements([_announcement(1, color: 'teal')]));
      expect(find.text('Announcement'), findsOneWidget);
    });
  });

  group('Clinic House Rules', () {
    testWidgets('empty rules show a graceful empty state', (tester) async {
      await _pump(tester, _rules('   '));
      expect(
        find.textContaining('has not posted house rules yet'),
        findsOneWidget,
      );
      expect(find.text('View all house rules'), findsNothing);
    });

    testWidgets('error state offers retry', (tester) async {
      await _pump(tester, _rules('', hasError: true));
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('short rules show a preview and view-all', (tester) async {
      await _pump(tester, _rules('1. Arrive 15 minutes early.\n2. No food.'));
      expect(find.text('1. Arrive 15 minutes early.\n2. No food.'), findsOne);
      expect(find.text('View all house rules'), findsOneWidget);
    });

    testWidgets('long rules are clamped and open in full', (tester) async {
      final rules = List.generate(
        40,
        (i) => '${i + 1}. $_longText'.substring(0, 90),
      ).join('\n');
      await _pump(tester, _rules(rules), size: const Size(320, 640));
      expect(tester.takeException(), isNull);

      final preview = tester.widget<Text>(find.text(rules));
      expect(preview.maxLines, 4);

      await tester.tap(find.text('View all house rules'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Clinic House Rules'), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('View all house rules'), findsOneWidget);
    });
  });
}
