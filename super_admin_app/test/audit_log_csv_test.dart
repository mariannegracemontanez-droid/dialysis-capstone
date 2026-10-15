import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/utils/audit_log_csv.dart';

/// Decodes the CSV bytes, asserting and stripping the UTF-8 BOM.
String _decode(List<int> bytes) {
  expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM');
  return utf8.decode(bytes.sublist(3));
}

void main() {
  group('AuditLogCsv.build', () {
    test('empty logs produce a BOM and header row only', () {
      final csv = _decode(AuditLogCsv.build(const []));

      expect(
        csv,
        '"created_at","action","actor_id","actor_name",'
        '"target_id","target_name","metadata"\r\n',
      );
    });

    test('escapes commas, quotes and line breaks inside cells', () {
      final csv = _decode(
        AuditLogCsv.build([
          {
            'action': 'update, role',
            'actor_name': 'Juan "JD" Dela Cruz',
            'target_name': 'Line one\nLine two\r\nLine three',
          },
        ]),
      );
      final row = csv.split('\r\n')[1];

      expect(row, startsWith('"","update, role","","Juan ""JD"" Dela Cruz",'));
      expect(csv, contains('"Line one\nLine two\r\nLine three"'));
    });

    test('keeps non-ASCII text intact as UTF-8', () {
      final csv = _decode(
        AuditLogCsv.build([
          {'actor_name': 'Peña Ñiño — 日本'},
        ]),
      );

      expect(csv, contains('"Peña Ñiño — 日本"'));
    });

    test('missing and null values become empty cells', () {
      final csv = _decode(
        AuditLogCsv.build([
          {'action': null},
        ]),
      );

      expect(csv.split('\r\n')[1], '"","","","","","",""');
    });

    test('prefixes formula-like values so spreadsheets treat them as text', () {
      final csv = _decode(
        AuditLogCsv.build([
          {'actor_name': '=HYPERLINK("x")', 'target_name': '  @cmd'},
        ]),
      );

      expect(csv, contains('"\'=HYPERLINK(""x"")"'));
      expect(csv, contains('"\'  @cmd"'));
    });

    test('encodes map metadata as JSON', () {
      final csv = _decode(
        AuditLogCsv.build([
          {
            'metadata': {'role': 'admin'},
          },
        ]),
      );

      expect(csv, contains('"{""role"":""admin""}"'));
    });

    test('one row per log, in input order', () {
      final csv = _decode(
        AuditLogCsv.build([
          {'action': 'first'},
          {'action': 'second'},
        ]),
      );
      final lines = csv.split('\r\n')..removeLast();

      expect(lines, hasLength(3));
      expect(lines[1], contains('"first"'));
      expect(lines[2], contains('"second"'));
    });
  });

  test('fileName uses the given date', () {
    expect(
      AuditLogCsv.fileName(DateTime(2026, 10, 13)),
      'CureNurture_Audit_Logs_2026-10-13.csv',
    );
  });
}
