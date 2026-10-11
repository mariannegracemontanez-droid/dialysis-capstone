import 'package:CureNurture/models/signup_data.dart';
import 'package:CureNurture/services/medical_document_service.dart';
import 'package:CureNurture/utils/date_range.dart';
import 'package:CureNurture/utils/patient_name.dart';
import 'package:CureNurture/utils/validators.dart';
import 'package:CureNurture/widgets/patient_name_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientName', () {
    test('formats with and without a middle name', () {
      expect(
        const PatientName(
          firstName: 'Juan',
          middleName: 'Santos',
          lastName: 'Dela Cruz',
        ).displayName,
        'Juan Santos Dela Cruz',
      );
      expect(
        const PatientName(
          firstName: 'Maria Clara',
          lastName: 'Reyes',
        ).displayName,
        'Maria Clara Reyes',
      );
    });

    test('trims and collapses spaces, treats blank middle as none', () {
      final name = PatientName.fromRow({
        'first_name': '  Ana  ',
        'middle_name': '   ',
        'last_name': ' de   los Santos ',
      });
      expect(name.middleName, isNull);
      expect(name.displayName, 'Ana de los Santos');
      expect(name.toColumns()['middle_name'], isNull);
    });

    test('legacy rows keep full_name and are never split', () {
      final name = PatientName.fromRow({'full_name': 'Jose Maria Rizal'});
      expect(name.hasComponents, isFalse);
      expect(name.firstName, isEmpty);
      expect(name.lastName, isEmpty);
      expect(name.displayName, 'Jose Maria Rizal');
      // Writing a legacy name back must not blank out separated columns.
      expect(name.toColumns(), {'full_name': 'Jose Maria Rizal'});
    });

    test('toColumns writes the components plus the formatted full name', () {
      expect(
        const PatientName(
          firstName: 'Juan',
          middleName: 'Santos',
          lastName: 'Cruz',
        ).toColumns(),
        {
          'first_name': 'Juan',
          'middle_name': 'Santos',
          'last_name': 'Cruz',
          'full_name': 'Juan Santos Cruz',
        },
      );
    });
  });

  group('Validators.validatePersonNamePart', () {
    test('accepts accented letters, apostrophes, hyphens, spaces', () {
      for (final value in [
        'Peña',
        'Niño',
        "O'Neil",
        'Dela Cruz',
        'Ana-Marie',
      ]) {
        expect(
          Validators.validatePersonNamePart(value, fieldLabel: 'Name'),
          isNull,
          reason: value,
        );
      }
    });

    test('rejects blanks, digits and punctuation-only values', () {
      expect(
        Validators.validatePersonNamePart('   ', fieldLabel: 'First name'),
        'First name is required.',
      );
      expect(
        Validators.validatePersonNamePart('J0hn', fieldLabel: 'First name'),
        isNotNull,
      );
      expect(
        Validators.validatePersonNamePart("--'", fieldLabel: 'First name'),
        isNotNull,
      );
    });
  });

  group('PatientNameController', () {
    test('requires a middle name unless the checkbox is ticked', () {
      final controller = PatientNameController();
      addTearDown(controller.dispose);
      controller.first.text = 'Juan';
      controller.last.text = 'Cruz';

      expect(controller.validate(), isNotNull);
      expect(controller.middleError, isNotNull);

      controller.noMiddleName = true;
      expect(controller.validate(), isNull);
      expect(controller.value.middleName, isNull);
      expect(controller.value.displayName, 'Juan Cruz');
    });

    test('first and last name stay required with the checkbox ticked', () {
      final controller = PatientNameController();
      addTearDown(controller.dispose);
      controller.noMiddleName = true;

      expect(controller.validate(), 'First name is required.');
      expect(controller.lastError, 'Last name is required.');
    });

    test('ticking the checkbox clears a typed middle name', () {
      final controller = PatientNameController();
      addTearDown(controller.dispose);
      controller.middle.text = 'Santos';
      controller.noMiddleName = true;
      expect(controller.middle.text, isEmpty);
    });

    test('pre-fill: checked only for a separated name without middle', () {
      final noMiddle = PatientNameController(
        initial: const PatientName(firstName: 'Juan', lastName: 'Cruz'),
      );
      final withMiddle = PatientNameController(
        initial: const PatientName(
          firstName: 'Juan',
          middleName: 'Santos',
          lastName: 'Cruz',
        ),
      );
      final legacy = PatientNameController(
        initial: const PatientName(legacyFullName: 'Juan Cruz'),
      );
      addTearDown(noMiddle.dispose);
      addTearDown(withMiddle.dispose);
      addTearDown(legacy.dispose);

      expect(noMiddle.noMiddleName, isTrue);
      expect(withMiddle.noMiddleName, isFalse);
      expect(legacy.noMiddleName, isFalse);
      expect(legacy.legacyFullName, 'Juan Cruz');
    });
  });

  testWidgets('checkbox disables and re-enables the Middle Name field', (
    tester,
  ) async {
    final controller = PatientNameController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PatientNameFields(
              controller: controller,
              decoration: (label, icon, errorText) =>
                  InputDecoration(labelText: label, errorText: errorText),
            ),
          ),
        ),
      ),
    );

    TextField middleField() =>
        tester.widget<TextField>(find.widgetWithText(TextField, 'Middle Name'));

    expect(middleField().enabled, isTrue);
    await tester.tap(find.text("I don't have a middle name"));
    await tester.pump();
    expect(middleField().enabled, isFalse);
    expect(controller.noMiddleName, isTrue);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(middleField().enabled, isTrue);
  });

  group('SignupData.toPatientApplicationColumns', () {
    SignupData data({PatientName? name}) => SignupData(
      name: name ?? const PatientName(firstName: 'Juan', lastName: 'Cruz'),
      email: 'juan@example.com',
      phone: '09171234567',
      password: '',
      dateOfBirth: '1980-05-02',
      homeAddress: '12 Mabini St',
      barangay: 'Malinta',
      emergencyContactName: 'Maria Cruz',
      emergencyContactRelationship: 'Spouse',
      conditions: const ['None'],
    );

    test('stores separated names with NULL middle name, no budget', () {
      final columns = data().toPatientApplicationColumns();
      expect(columns['first_name'], 'Juan');
      expect(columns.containsKey('middle_name'), isTrue);
      expect(columns['middle_name'], isNull);
      expect(columns['last_name'], 'Cruz');
      expect(columns['full_name'], 'Juan Cruz');
      expect(columns.containsKey('budget'), isFalse);
      expect(
        columns['home_address'],
        '12 Mabini St, Barangay Malinta, Valenzuela City',
      );
      expect(columns['emergency_contact_name'], 'Maria Cruz (Spouse)');
      expect(columns['date_of_birth'], '1980-05-02');
    });

    test('fromPatientRow prefers row components, falls back to profile', () {
      final fromRow = SignupData.fromPatientRow(
        {
          'first_name': 'Juan',
          'middle_name': 'Santos',
          'last_name': 'Cruz',
          'full_name': 'Juan Santos Cruz',
        },
        profileId: 'p1',
        fallbackName: const PatientName(firstName: 'Other', lastName: 'Name'),
      );
      expect(fromRow.name.displayName, 'Juan Santos Cruz');

      final legacyRow = SignupData.fromPatientRow(
        {'full_name': 'Juan Santos Cruz'},
        profileId: 'p1',
        fallbackName: const PatientName(firstName: 'Juan', lastName: 'Cruz'),
      );
      expect(legacyRow.name.hasComponents, isTrue);
      expect(legacyRow.name.displayName, 'Juan Cruz');

      final bothLegacy = SignupData.fromPatientRow({
        'full_name': 'Juan Santos Cruz',
      }, profileId: 'p1');
      expect(bothLegacy.name.hasComponents, isFalse);
      expect(bothLegacy.name.legacyFullName, 'Juan Santos Cruz');
    });
  });

  group('isWithinLastDays', () {
    final now = DateTime(2026, 10, 11, 15, 30);

    test('7/30/60-day windows include today and the oldest day', () {
      expect(isWithinLastDays('2026-10-11', 7, now: now), isTrue);
      expect(isWithinLastDays('2026-10-05', 7, now: now), isTrue);
      expect(isWithinLastDays('2026-10-04', 7, now: now), isFalse);
      expect(isWithinLastDays('2026-09-12', 30, now: now), isTrue);
      expect(isWithinLastDays('2026-09-11', 30, now: now), isFalse);
      expect(isWithinLastDays('2026-08-13', 60, now: now), isTrue);
      expect(isWithinLastDays('2026-08-12', 60, now: now), isFalse);
    });

    test('missing or unreadable dates are excluded', () {
      expect(isWithinLastDays(null, 60, now: now), isFalse);
      expect(isWithinLastDays('', 60, now: now), isFalse);
      expect(isWithinLastDays('not a date', 60, now: now), isFalse);
    });
  });

  test('clinic requirement labels map to document columns', () {
    expect(
      MedicalDocumentService.columnForRequirement('Laboratory Results'),
      'lab_results_url',
    );
    expect(
      MedicalDocumentService.columnForRequirement(
        'Referral Letter/Endorsement Letter/Discharge Summary',
      ),
      'referral_letter_url',
    );
    expect(
      MedicalDocumentService.columnForRequirement('Barangay Clearance'),
      'barangay_clearance',
    );
  });
}
