import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import 'xlsx_writer.dart';

/// Builds the Audit Trail Excel download from the `audit_logs` rows the
/// Account Management page has already loaded.
///
/// Read-only by design: it only formats the maps it is given, so the export
/// can never change, add or drop a log record. One sheet row per input map,
/// in the same order, so the workbook always matches what the tab shows.
///
/// Values are written as inline text cells (never `<f>` formulas), so a
/// stored value such as `=HYPERLINK(...)` opens as plain text in Excel.
class AuditLogXlsx {
  AuditLogXlsx._();

  static const String mimeType = XlsxWriter.mimeType;
  static const String sheetName = 'Audit Trail';

  /// The `audit_logs` columns exported, in order. Also used as the header
  /// row, so the file names each column exactly as the database does.
  static const List<String> columns = <String>[
    'created_at',
    'action',
    'actor_id',
    'actor_name',
    'target_id',
    'target_name',
    'metadata',
  ];

  /// Character widths for [columns]; ids are UUIDs (36 characters).
  static const List<double> columnWidths = <double>[18, 24, 38, 26, 38, 26, 60];

  static final DateFormat _fileDate = DateFormat('yyyy-MM-dd');

  /// `CureNurture_Audit_Logs_2026-10-13.xlsx`
  static String fileName([DateTime? now]) =>
      'CureNurture_Audit_Logs_${_fileDate.format(now ?? DateTime.now())}.xlsx';

  /// The bytes of a complete .xlsx workbook: a frozen header row with
  /// filter drop-downs, then one row per log.
  static Uint8List build(
    List<Map<String, dynamic>> logs, {
    DateTime? generatedAt,
  }) {
    final rows = <List<XlsxCell?>?>[
      [for (final column in columns) XlsxCell(column, style: XlsxStyle.header)],
      for (final log in logs)
        [for (final column in columns) _cell(log, column)],
    ];

    final lastColumn = XlsxWriter.columnLetter(columns.length - 1);

    return XlsxWriter.build(
      XlsxSheet(
        name: sheetName,
        rows: rows,
        columnWidths: columnWidths,
        frozenRows: 1,
        printTitleRow: 1,
        autoFilterRef: 'A1:$lastColumn${rows.length}',
      ),
      title: 'CureNurture Audit Logs',
      created: generatedAt,
    );
  }

  /// One cell for one column of one record. Missing and null values become
  /// an empty (but bordered) cell.
  static XlsxCell _cell(Map<String, dynamic> log, String column) {
    final raw = log[column];
    if (raw == null) return const XlsxCell(null, style: XlsxStyle.text);

    if (column == 'created_at') {
      // A real Excel date in local time, the zone the Audit Trail cards are
      // read in. An unparseable value is kept as stored rather than dropped.
      final parsed = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
      return parsed == null
          ? XlsxCell(raw.toString(), style: XlsxStyle.text)
          : XlsxCell(parsed.toLocal(), style: XlsxStyle.dateTime);
    }

    if (column == 'metadata' && (raw is Map || raw is List)) {
      return XlsxCell(jsonEncode(raw), style: XlsxStyle.text);
    }

    return XlsxCell(raw.toString(), style: XlsxStyle.text);
  }
}
