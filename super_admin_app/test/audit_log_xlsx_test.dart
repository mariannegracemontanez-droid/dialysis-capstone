import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/utils/audit_log_xlsx.dart';
import 'package:super_admin_app/utils/xlsx_writer.dart';

/// Unzips [bytes] and returns the named part as text.
String _part(Uint8List bytes, String path) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.findFile(path);
  expect(file, isNotNull, reason: '$path is missing from the .xlsx');
  return utf8.decode(file!.content as List<int>);
}

String _sheet(Uint8List bytes) => _part(bytes, 'xl/worksheets/sheet1.xml');

/// The XML of 1-based [row], e.g. `<row r="2">...</row>`.
String _row(String sheetXml, int row) =>
    RegExp('<row r="$row"[^>]*>.*?</row>').firstMatch(sheetXml)!.group(0)!;

void main() {
  group('AuditLogXlsx.build', () {
    test('produces a valid zip with the required workbook parts', () {
      final bytes = AuditLogXlsx.build(const []);

      expect(bytes.sublist(0, 2), [0x50, 0x4B], reason: 'zip "PK" signature');
      for (final path in [
        '[Content_Types].xml',
        '_rels/.rels',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
      ]) {
        _part(bytes, path);
      }
    });

    test('names the worksheet "Audit Trail"', () {
      final workbook = _part(AuditLogXlsx.build(const []), 'xl/workbook.xml');

      expect(workbook, contains('<sheet name="Audit Trail"'));
    });

    test('empty logs produce the header row only', () {
      final sheet = _sheet(AuditLogXlsx.build(const []));

      expect(RegExp('<row ').allMatches(sheet), hasLength(1));
      for (final column in AuditLogXlsx.columns) {
        expect(_row(sheet, 1), contains('<t xml:space="preserve">$column</t>'));
      }
    });

    test('header is frozen, filterable, and columns have widths', () {
      final sheet = _sheet(
        AuditLogXlsx.build([
          {'action': 'a'},
          {'action': 'b'},
        ]),
      );

      expect(sheet, contains('ySplit="1"'));
      expect(sheet, contains('<autoFilter ref="A1:G3"/>'));
      expect(RegExp('<col ').allMatches(sheet), hasLength(7));
    });

    test('one row per log, in input order, columns in order', () {
      final sheet = _sheet(
        AuditLogXlsx.build([
          {
            'action': 'first',
            'actor_id': 'actor-1',
            'actor_name': 'Ana',
            'target_id': 'target-1',
            'target_name': 'Ben',
          },
          {'action': 'second'},
        ]),
      );
      final row2 = _row(sheet, 2);

      expect(
        row2,
        contains('r="B2" s="${XlsxStyle.text.index}" t="inlineStr"'),
      );
      expect(row2, contains('>first<'));
      expect(
        row2,
        matches(
          RegExp(
            'r="C2".*actor-1.*r="D2".*Ana.*r="E2"'
            '.*target-1.*r="F2".*Ben',
          ),
        ),
      );
      expect(_row(sheet, 3), contains('>second<'));
    });

    test('keeps non-English and XML special characters intact', () {
      final sheet = _sheet(
        AuditLogXlsx.build([
          {
            'actor_name': 'Peña Ñiño — 日本',
            'target_name': 'A & B <c> "quoted", comma\nnew line',
          },
        ]),
      );

      expect(sheet, contains('Peña Ñiño — 日本'));
      expect(
        sheet,
        contains('A &amp; B &lt;c&gt; &quot;quoted&quot;, comma\nnew line'),
      );
    });

    test('formula-like values are stored as text, never as formulas', () {
      final sheet = _sheet(
        AuditLogXlsx.build([
          {'actor_name': '=HYPERLINK("http://x")', 'target_name': '+1+1'},
        ]),
      );

      expect(sheet, isNot(contains('<f>')));
      expect(
        sheet,
        contains(
          't="inlineStr"><is><t xml:space="preserve">'
          '=HYPERLINK(&quot;http://x&quot;)</t>',
        ),
      );
      expect(sheet, contains('>+1+1<'));
    });

    test('created_at becomes a real Excel date; bad values stay as text', () {
      final when = DateTime(2026, 10, 13, 9, 30);
      final sheet = _sheet(
        AuditLogXlsx.build([
          {'created_at': when.toUtc().toIso8601String()},
          {'created_at': 'not a date'},
        ]),
      );

      expect(
        _row(sheet, 2),
        contains(
          '<c r="A2" s="${XlsxStyle.dateTime.index}">'
          '<v>${XlsxWriter.excelSerial(when)}</v></c>',
        ),
      );
      expect(_row(sheet, 3), contains('>not a date<'));
    });

    test('map metadata is JSON; null and missing values are empty cells', () {
      final sheet = _sheet(
        AuditLogXlsx.build([
          {
            'action': null,
            'metadata': {'role': 'admin'},
          },
        ]),
      );
      final row = _row(sheet, 2);

      expect(row, contains('{&quot;role&quot;:&quot;admin&quot;}'));
      expect(row, contains('<c r="B2" s="${XlsxStyle.text.index}"/>'));
      expect(row, contains('<c r="C2" s="${XlsxStyle.text.index}"/>'));
    });
  });

  test('fileName uses the given date and .xlsx extension', () {
    expect(
      AuditLogXlsx.fileName(DateTime(2026, 10, 13)),
      'CureNurture_Audit_Logs_2026-10-13.xlsx',
    );
  });

  test('mimeType is the Office Open XML spreadsheet type', () {
    expect(
      AuditLogXlsx.mimeType,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  });
}
