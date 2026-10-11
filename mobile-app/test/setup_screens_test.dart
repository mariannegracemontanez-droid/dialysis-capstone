import 'package:CureNurture/models/signup_data.dart';
import 'package:CureNurture/pages/auth/confirm_info_page.dart';
import 'package:CureNurture/pages/auth/setup_page.dart';
import 'package:CureNurture/pages/home/pending_application_card.dart';
import 'package:CureNurture/utils/patient_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Test fonts draw every glyph as a full square, so text is wider than on a
// device; [size] lets a screen use a larger (still phone-sized) viewport.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump();
}

SignupData _signupData({
  PatientName name = const PatientName(firstName: 'Juan', lastName: 'Cruz'),
  String password = 'Secret#123',
  String bloodType = '',
}) {
  return SignupData(
    name: name,
    email: 'juan@example.com',
    phone: '09171234567',
    password: password,
    profileId: 'profile-1',
    bloodType: bloodType,
  );
}

void main() {
  group('Step 1 (SetupPage)', () {
    testWidgets('shows the 3-step indicator, name, medical and insurance', (
      tester,
    ) async {
      await _pump(tester, SetupPage(signupData: _signupData()));

      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Juan'), findsOneWidget);
      expect(find.text('Cruz'), findsOneWidget);
      expect(find.text("I don't have a middle name"), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Insurance Coverage'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Medical Information'), findsOneWidget);
      expect(find.text('PhilHealth'), findsOneWidget);
      expect(find.text('Budget Range'), findsNothing);
    });

    testWidgets('NEXT with an empty name reports the first missing part', (
      tester,
    ) async {
      await _pump(
        tester,
        SetupPage(signupData: _signupData(name: const PatientName())),
      );

      await tester.scrollUntilVisible(
        find.text('NEXT'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('NEXT'));
      await tester.pump();

      expect(find.text('First name is required.'), findsWidgets);
    });

    testWidgets('re-apply pre-fill with free-text blood type does not crash', (
      tester,
    ) async {
      await _pump(
        tester,
        SetupPage(
          signupData: _signupData(
            password: '',
            bloodType: 'O positive',
            name: const PatientName(legacyFullName: 'Juan Santos Cruz'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Re-apply flow gets a back button; the legacy name is shown as a
      // reference for re-entering it in separate fields.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      expect(find.textContaining('Juan Santos Cruz'), findsOneWidget);
    });
  });

  testWidgets('Confirm page shows separated name and no budget', (
    tester,
  ) async {
    await _pump(
      tester,
      ConfirmInfoPage(
        signupData: _signupData(
          name: const PatientName(
            firstName: 'Juan',
            middleName: 'Santos',
            lastName: 'Cruz',
          ),
        ),
      ),
      size: const Size(412, 915),
    );

    expect(find.text('Juan Santos Cruz'), findsOneWidget);
    expect(find.text('Juan · Santos · Cruz'), findsOneWidget);
    expect(find.text('Budget Range'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('No documents uploaded.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
  });

  group('PendingApplicationCard', () {
    Map<String, dynamic> application() => {
      'id': 'app-1',
      'status': 'pending',
      'clinic_name': 'Valenzuela Dialysis Center',
      'first_name': 'Juan',
      'middle_name': null,
      'last_name': 'Cruz',
      'full_name': 'Juan Cruz',
      'dialysis_stage': 'Stage 5',
      'clinic': {
        'name': 'Valenzuela Dialysis Center',
        'address': '123 MacArthur Hwy, Valenzuela City',
        'requirements': ['Laboratory Results', 'Government ID'],
      },
      'documents': {
        'patient_id': 'app-1',
        'lab_results_url': 'https://example.invalid/lab.jpg',
      },
    };

    testWidgets('collapsed shows clinic and address; expands to details', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PendingApplicationCard(application: application()),
          ),
        ),
      );

      expect(find.text('Valenzuela Dialysis Center'), findsOneWidget);
      expect(find.text('123 MacArthur Hwy, Valenzuela City'), findsOneWidget);
      expect(find.text('Documents Needed'), findsNothing);

      await tester.tap(find.text('Valenzuela Dialysis Center'));
      await tester.pumpAndSettle();

      expect(find.text('Documents Needed'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Not submitted'), findsOneWidget);
      expect(find.text('No middle name'), findsOneWidget);
      expect(find.text('Stage 5'), findsOneWidget);
      expect(find.text('Laboratory Results'), findsWidgets);
    });

    testWidgets('tapping a document opens a preview that closes', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PendingApplicationCard(application: application()),
          ),
        ),
      );
      await tester.tap(find.text('Valenzuela Dialysis Center'));
      await tester.pumpAndSettle();

      final galleryItem = find.byType(InkWell).last;
      await tester.ensureVisible(galleryItem);
      await tester.tap(galleryItem);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing);
    });

    testWidgets('no requirements and no documents show empty states', (
      tester,
    ) async {
      final row = application()
        ..['clinic'] = {'name': 'Clinic', 'address': 'Somewhere'}
        ..['documents'] = null;
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PendingApplicationCard(application: row),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('This clinic has not listed any document requirements.'),
        findsOneWidget,
      );
      expect(
        find.text('No uploaded documents were found for this application.'),
        findsOneWidget,
      );
    });
  });
}
