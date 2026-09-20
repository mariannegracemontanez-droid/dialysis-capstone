// The Center Profile's data model.
//
// The case that matters here is requirements round-tripping. The Center
// Admin and the Super Admin write the SAME `clinics.requirements`
// column, so a requirement the Super Admin ticked has to come back
// ticked in the Admin's edit form -- and anything neither of them knows
// about has to survive an edit rather than being quietly dropped.

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/models/center_profile.dart';

void main() {
  group('requirements parsing', () {
    test('a text[] column comes back one item per element', () {
      expect(
        CenterProfile.parseRequirements([
          'Latest Laboratory Results',
          'PDD Certification',
        ]),
        ['Latest Laboratory Results', 'PDD Certification'],
      );
    });

    test('blank elements are dropped, real ones kept', () {
      expect(CenterProfile.parseRequirements(['  ', 'PDD Certification', '']), [
        'PDD Certification',
      ]);
    });

    test('null and empty mean no requirements, not a blank one', () {
      expect(CenterProfile.parseRequirements(null), isEmpty);
      expect(CenterProfile.parseRequirements(''), isEmpty);
      expect(CenterProfile.parseRequirements([]), isEmpty);
    });

    test('a bracketed legacy value splits on its own separators', () {
      // Dart's List.toString() form: those commas were written by code.
      expect(
        CenterProfile.parseRequirements('[1×1 Picture, PHIC Consumption]'),
        ['1×1 Picture', 'PHIC Consumption'],
      );
    });

    test('unbracketed prose is never split on a comma', () {
      // "ID, referral" could be one item an admin typed. Splitting it
      // would invent a requirement nobody wrote -- the same rule the
      // Super Admin form and the mobile app already follow.
      expect(
        CenterProfile.parseRequirements('Government ID, referral letter'),
        ['Government ID, referral letter'],
      );
    });

    test('unbracketed text splits on the newline this app writes', () {
      expect(
        CenterProfile.parseRequirements('PDD Certification\n1×1 Picture'),
        ['PDD Certification', '1×1 Picture'],
      );
    });
  });

  group('CenterProfile.fromJson', () {
    final row = <String, dynamic>{
      'id': 'c1',
      'name': 'Valenzuela Dialysis Center',
      'address': '12 Maysan Road',
      'city': 'Valenzuela City',
      'contact_number': '0288888888',
      'machine': 10,
      'slots_available': 12,
      'status': 'open',
      'operating_hours': '7:00 AM - 5:00 PM',
      'target_daily_capacity': 16,
      'requirements': ['Latest Laboratory Results', 'Bring your own towel'],
      'house_rules': 'No visitors during treatment hours.',
    };

    test('maps the existing clinics columns', () {
      final center = CenterProfile.fromJson(row);

      expect(center.name, 'Valenzuela Dialysis Center');
      expect(center.machines, 10);
      expect(center.availableSlots, 12);
      expect(center.operatingHours, '7:00 AM - 5:00 PM');
      expect(center.targetDailyCapacity, 16);
      expect(center.hasHouseRules, isTrue);
    });

    test('a row with no house rules is not treated as having blank ones', () {
      final center = CenterProfile.fromJson({...row, 'house_rules': null});

      expect(center.houseRules, '');
      expect(center.hasHouseRules, isFalse);
    });

    test('whitespace-only house rules do not count as written', () {
      expect(
        CenterProfile.fromJson({...row, 'house_rules': '   '}).hasHouseRules,
        isFalse,
      );
    });

    test('a missing machine count reads as zero, never as null', () {
      expect(CenterProfile.fromJson({...row, 'machine': null}).machines, 0);
    });
  });

  group('edit form round trip', () {
    test('a stored requirement ticks its checkbox; the rest stay custom', () {
      final center = CenterProfile.fromJson({
        'id': 'c1',
        'requirements': [
          'Latest Laboratory Results',
          'PDD Certification',
          'Bring your own towel',
        ],
      });

      // What the edit form computes when it opens.
      final ticked = {
        for (final option in kCommonCenterRequirements)
          option: center.requirements.contains(option),
      };
      final custom = center.requirements
          .where((item) => !kCommonCenterRequirements.contains(item))
          .toList();

      expect(ticked['Latest Laboratory Results'], isTrue);
      expect(ticked['PDD Certification'], isTrue);
      expect(ticked['1×1 Picture'], isFalse);

      // Preserved verbatim rather than dropped or forced into a label it
      // does not match.
      expect(custom, ['Bring your own towel']);
    });

    test('unticking removes the requirement from what gets saved', () {
      final ticked = {
        for (final option in kCommonCenterRequirements) option: false,
      }..['PDD Certification'] = true;

      final saved = [
        for (final option in kCommonCenterRequirements)
          if (ticked[option] == true) option,
      ];

      expect(saved, ['PDD Certification']);
      expect(saved, isNot(contains('Latest Laboratory Results')));
    });

    test('copyWith replaces only the fields the profile page owns', () {
      final center = CenterProfile.fromJson({
        'id': 'c1',
        'name': 'Valenzuela Dialysis Center',
        'machine': 10,
        'slots_available': 12,
        'requirements': ['1×1 Picture'],
      });

      final edited = center.copyWith(machines: 12, houseRules: 'Be on time.');

      expect(edited.machines, 12);
      expect(edited.houseRules, 'Be on time.');
      // Super-Admin-owned fields are carried through untouched.
      expect(edited.name, 'Valenzuela Dialysis Center');
      expect(edited.availableSlots, 12);
      expect(edited.requirements, ['1×1 Picture']);
    });
  });
}
