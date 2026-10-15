import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/utils/center_assignment.dart';
import 'package:super_admin_app/utils/form_dirty_state.dart';

void main() {
  group('centre assignment eligibility', () {
    final clinics = <Map<String, dynamic>>[
      {'id': 'a', 'name': 'A', 'status': 'open'},
      {'id': 'b', 'name': 'B', 'status': 'busy'}, // legacy -> Active
      {'id': 'c', 'name': 'C', 'status': 'closed'}, // Inactive
      {'id': 'd', 'name': 'D', 'status': null},
      {'id': 'e', 'name': 'E', 'status': 'full'},
    ];

    List<String> ids(List<Map<String, dynamic>> rows) =>
        rows.map((row) => row['id'] as String).toList();

    test(
      'excludes inactive centres and centres that already have an admin',
      () {
        final eligible = eligibleCentersForAssignment(
          clinics,
          clinicsWithAdmin: {'a', 'e'},
        );
        expect(ids(eligible), ['b', 'd']);
      },
    );

    test(
      "keeps the edited account's own centre, even if it has that admin",
      () {
        final eligible = eligibleCentersForAssignment(
          clinics,
          clinicsWithAdmin: {'a'},
          currentClinicId: 'a',
        );
        expect(ids(eligible), ['a', 'b', 'd', 'e']);
      },
    );

    test("keeps the edited account's own centre when it became inactive", () {
      expect(
        isCenterEligibleForAssignment(
          clinics[2],
          clinicsWithAdmin: const {},
          currentClinicId: 'c',
        ),
        isTrue,
      );
      expect(
        isCenterEligibleForAssignment(clinics[2], clinicsWithAdmin: const {}),
        isFalse,
      );
    });

    test('empty when nothing is available', () {
      expect(
        eligibleCentersForAssignment(
          clinics,
          clinicsWithAdmin: {'a', 'b', 'd', 'e'},
        ),
        isEmpty,
      );
    });

    test('a row without an id is never eligible', () {
      expect(
        isCenterEligibleForAssignment({
          'name': 'X',
          'status': 'open',
        }, clinicsWithAdmin: const {}),
        isFalse,
      );
    });
  });

  group('hasFormChanges (Save Changes visibility)', () {
    final original = <String, Object?>{
      'name': 'Center A',
      'machines': '4',
      'open': 420,
      'latitude': 14.7,
      'clinic_id': null,
    };

    test('opening a record unchanged is not dirty', () {
      expect(hasFormChanges(original, Map.of(original)), isFalse);
    });

    test('any real change is dirty', () {
      expect(
        hasFormChanges(original, {...original, 'name': 'Center B'}),
        isTrue,
      );
      expect(hasFormChanges(original, {...original, 'open': 480}), isTrue);
      expect(hasFormChanges(original, {...original, 'clinic_id': 'x'}), isTrue);
      expect(hasFormChanges(original, {...original, 'latitude': 14.8}), isTrue);
    });

    test('changing a value and restoring it is clean again', () {
      final edited = {...original, 'name': 'Center B'};
      expect(hasFormChanges(original, edited), isTrue);
      edited['name'] = 'Center A';
      expect(hasFormChanges(original, edited), isFalse);
    });

    test('surrounding whitespace alone is not a change', () {
      expect(
        hasFormChanges(original, {...original, 'name': ' Center A  '}),
        isFalse,
      );
    });

    test('a missing or extra field counts as a change', () {
      expect(hasFormChanges(original, {...original}..remove('name')), isTrue);
      expect(hasFormChanges(original, {...original, 'extra': 1}), isTrue);
    });
  });
}
