import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/features/dashboard/announcements_section.dart';
import 'package:admin_panel/models/announcement.dart';
import 'package:admin_panel/theme/app_theme.dart';
import 'package:admin_panel/widgets/admin_modal.dart';

/// Wraps a widget in just enough app for a dialog to open.
Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('AnnouncementColor', () {
    test('every offered token is one the database accepts', () {
      // The picker must never offer a value the check constraint in
      // patient_announcements.sql would reject.
      const accepted = {
        'blue',
        'light_blue',
        'green',
        'orange',
        'purple',
        'red',
      };

      expect(AnnouncementColor.all.toSet(), accepted);
    });

    test('an unknown token falls back to blue rather than breaking', () {
      expect(AnnouncementColor.normalize('chartreuse'), AnnouncementColor.blue);
      expect(AnnouncementColor.normalize(null), AnnouncementColor.blue);
      expect(AnnouncementColor.normalize('RED'), AnnouncementColor.red);
    });
  });

  group('Announcement', () {
    test('reads the columns the mobile app also reads', () {
      final announcement = Announcement.fromJson({
        'id': 'a1',
        'clinic_id': 'c1',
        'title': '  Center closed Friday  ',
        'body': 'Maintenance on the water system.',
        'announcement_date': '2026-09-25',
        'color': 'red',
        'created_at': '2026-09-19T08:30:00Z',
        'updated_at': '2026-09-19T08:30:00Z',
      });

      expect(announcement.id, 'a1');
      expect(announcement.title, 'Center closed Friday');
      expect(announcement.announcementDate, DateTime(2026, 9, 25));
      expect(announcement.color, AnnouncementColor.red);
    });

    test('a missing date is null, not an epoch', () {
      final announcement = Announcement.fromJson({
        'id': 'a2',
        'clinic_id': 'c1',
        'title': 'General notice',
        'body': 'Body',
        'announcement_date': null,
        'color': 'blue',
      });

      expect(announcement.announcementDate, isNull);
      expect(announcement.isUpcoming, isFalse);
    });
  });

  group('Create Announcement modal', () {
    testWidgets('will not return a draft without a title', (tester) async {
      AnnouncementDraft? result;
      var returned = false;

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAnnouncementEditor(context: context);
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Create Announcement'), findsOneWidget);

      // Submitting an empty form must not close the modal.
      await tester.tap(find.text('Post announcement'));
      await tester.pumpAndSettle();

      expect(find.text('Give the announcement a title.'), findsOneWidget);
      expect(find.text('Create Announcement'), findsOneWidget);
      expect(returned, isFalse);
      expect(result, isNull);
    });

    testWidgets('returns title, body and colour', (tester) async {
      AnnouncementDraft? result;

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAnnouncementEditor(context: context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'Center closed Friday',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'Maintenance on the water system.',
      );

      // Pick the urgent colour. The picker sits below the text fields in
      // the modal's scrollable body, so scroll it into view first.
      await tester.ensureVisible(find.text('Urgent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Urgent'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Post announcement'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.title, 'Center closed Friday');
      expect(result!.body, 'Maintenance on the water system.');
      expect(result!.color, AnnouncementColor.red);
      // The date is optional and was never touched.
      expect(result!.date, isNull);
    });

    testWidgets('an existing announcement opens prefilled for editing', (
      tester,
    ) async {
      final existing = Announcement(
        id: 'a1',
        clinicId: 'c1',
        title: 'Dialysis Centre Schedule',
        body: 'Please be reminded that the center opens at 6am.',
        announcementDate: DateTime(2026, 9, 20),
        color: AnnouncementColor.orange,
      );

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showAnnouncementEditor(context: context, existing: existing),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Announcement'), findsOneWidget);
      expect(find.text('Dialysis Centre Schedule'), findsWidgets);
      expect(find.text('September 20, 2026'), findsWidgets);
      expect(find.text('Save changes'), findsOneWidget);
    });
  });

  group('Admin modal system', () {
    testWidgets('a confirmation returns true only when confirmed', (
      tester,
    ) async {
      bool? answer;

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                answer = await showAdminConfirm(
                  context: context,
                  title: 'Remove from this day',
                  message: 'Remove this patient from the AM shift?',
                  confirmLabel: 'Remove',
                  destructive: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('lays out at a small desktop width without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAdminDialog(
                context: context,
                builder: (_) => AdminModal(
                  title: 'A wide modal',
                  icon: Icons.campaign_rounded,
                  size: AdminModalSize.xlarge,
                  actions: [
                    ElevatedButton(
                      onPressed: () {},
                      style: AppTheme.primaryButton(),
                      child: const Text('Save'),
                    ),
                  ],
                  child: const SizedBox(height: 200),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('A wide modal'), findsOneWidget);

      final box = tester.getSize(find.byType(AdminModal));
      expect(box.width, lessThanOrEqualTo(1024));
    });
  });
}
