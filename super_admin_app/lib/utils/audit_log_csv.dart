import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

/// Builds the Audit Trail CSV download from the `audit_logs` rows the
/// Account Management page has already loaded.
///
/// Read-only by design: it only formats the maps it is given, so the export
/// can never change, add or drop a log record. One CSV row per input map, in
/// the same order, so the file always matches what the tab shows.
class AuditLogCsv {
  AuditLogCsv._();

  static const String mimeType = 'text/csv;charset=utf-8';

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

  static final DateFormat _timestamp = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final DateFormat _fileDate = DateFormat('yyyy-MM-dd');

  /// `CureNurture_Audit_Logs_2026-10-11.csv`
  static String fileName([DateTime? now]) =>
      'CureNurture_Audit_Logs_${_fileDate.format(now ?? DateTime.now())}.csv';

  /// UTF-8 bytes with a leading BOM, so Excel opens non-English characters
  /// correctly instead of guessing the system code page.
  static Uint8List build(List<Map<String, dynamic>> logs) {
    final buffer = StringBuffer('\uFEFF');

    _writeRow(buffer, columns);
    for (final log in logs) {
      _writeRow(buffer, columns.map((column) => _value(log, column)));
    }

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  static void _writeRow(StringBuffer buffer, Iterable<String> cells) {
    buffer
      ..write(cells.map(_cell).join(','))
      ..write('\r\n');
  }

  /// The display string for one column of one record. Missing and null
  /// values both become an empty cell.
  static String _value(Map<String, dynamic> log, String column) {
    final raw = log[column];
    if (raw == null) return '';

    if (column == 'created_at') {
      // Local date and time, same zone the Audit Trail cards are read in.
      // An unparseable value is kept as stored rather than dropped.
      final parsed = DateTime.tryParse(raw.toString());
      return parsed == null
          ? raw.toString()
          : _timestamp.format(parsed.toLocal());
    }

    if (column == 'metadata' && (raw is Map || raw is List)) {
      return jsonEncode(raw);
    }

    return raw.toString();
  }

  /// One quoted CSV cell. Every cell is quoted and embedded quotes are
  /// doubled, so commas and line breaks stay inside their cell.
  ///
  /// A value that a spreadsheet would read as a formula (leading `=`, `+`,
  /// `-`, `@`, tab or carriage return, even after leading spaces) gets a
  /// leading apostrophe so it opens as plain text. Only the file is
  /// affected; the stored log is untouched.
  static String _cell(String value) {
    final trimmed = value.trimLeft();
    final isFormulaLike =
        (value.isNotEmpty && _formulaTriggers.contains(value[0])) ||
        (trimmed.isNotEmpty && _formulaTriggers.contains(trimmed[0]));
    final safe = isFormulaLike ? "'$value" : value;

    return '"${safe.replaceAll('"', '""')}"';
  }

  static const Set<String> _formulaTriggers = <String>{
    '=',
    '+',
    '-',
    '@',
    '\t',
    '\r',
  };
}
