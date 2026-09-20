import 'package:intl/intl.dart';

import '../models/dialysis_session.dart';
import '../services/session_history_service.dart';

/// Turns ONE patient's session history into a file the center can keep.
///
/// Pure string building, no widgets and no network: the caller has
/// already loaded the patient and their sessions (both scoped to the
/// admin's own clinic by [SessionHistoryService]), so nothing here can
/// reach a record it was not handed. That also makes the output directly
/// testable.
///
/// Two formats, because the two uses are different:
///
///   * [buildPrintableHtml] -- a laid-out document for a patient file or
///     a referral. Opens in any browser and prints (or "saves as PDF")
///     from there, which is how a Flutter web app produces a PDF without
///     taking on a PDF toolchain.
///   * [buildCsv] -- the same rows for a spreadsheet.
///
/// Both begin with the patient's identifying details, and both cover
/// exactly the sessions passed in.
class SessionHistoryReport {
  const SessionHistoryReport._();

  static final DateFormat _fileDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _longDate = DateFormat('MMMM d, y');
  static final DateFormat _rowDate = DateFormat('MMM d, y');
  static final DateFormat _weekday = DateFormat('EEEE');
  static final DateFormat _timestamp = DateFormat('MMMM d, y • h:mm a');

  /// `session-history_juan-dela-cruz_2026-09-20.csv`
  static String fileName({
    required String patientName,
    required String extension,
  }) {
    final slug = patientName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    final safeSlug = slug.isEmpty ? 'patient' : slug;

    return 'session-history_${safeSlug}_'
        '${_fileDate.format(DateTime.now())}.$extension';
  }

  // ------------------------------------------------------------- CSV

  /// Escapes one CSV cell. Quotes anything containing a comma, a quote or
  /// a newline, and doubles embedded quotes -- the RFC 4180 rules every
  /// spreadsheet reads.
  static String _cell(Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return '';

    if (text.contains(RegExp(r'[",\n\r]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }

    return text;
  }

  static String _row(List<Object?> cells) => cells.map(_cell).join(',');

  static String buildCsv({
    required Map<String, dynamic> patient,
    required List<DialysisSession> sessions,
    required SessionHistorySummary summary,
  }) {
    final lines = <String>[
      _row(['CureNurture — Dialysis Session History']),
      _row(['Generated', _timestamp.format(DateTime.now())]),
      _row(['Center', _text(patient['clinics']?['name'])]),
      _row([]),

      // Patient identification, as required at the top of the file.
      _row(['Patient name', _text(patient['full_name'])]),
      _row(['Date of birth', _birthDate(patient)]),
      _row(['Phone number', _text(patient['phone'])]),
      _row(['Address', _text(patient['home_address'])]),
      _row(['Email', _text(patient['email'])]),
      _row(['Blood type', _text(patient['blood_type'])]),
      _row(['Dialysis stage', _text(patient['dialysis_stage'])]),
      _row([]),

      _row(['Completed sessions', summary.totalSessions]),
      _row([
        'Average session duration',
        summary.averageDurationLabel,
        'across ${summary.recordedDurations} recorded',
      ]),
      _row([
        'Average weight change',
        summary.averageWeightChangeLabel,
        'across ${summary.recordedWeightChanges} recorded',
      ]),
      _row([]),

      _row([
        'Session date',
        'Day',
        'Shift',
        'Status',
        'Weight before (kg)',
        'Weight after (kg)',
        'Weight change (kg)',
        'BP before (mmHg)',
        'Duration',
        'Completed at',
      ]),
    ];

    for (final session in sessions) {
      lines.add(
        _row([
          _rowDate.format(session.date),
          _weekday.format(session.date),
          session.shift,
          session.status,
          session.beforeWeight?.toStringAsFixed(1) ?? '',
          session.afterWeight?.toStringAsFixed(1) ?? '',
          session.weightChange == null
              ? ''
              : session.weightChange!.toStringAsFixed(1),
          session.bloodPressure ?? '',
          session.duration ?? '',
          session.completedAt == null
              ? ''
              : _timestamp.format(session.completedAt!.toLocal()),
        ]),
      );
    }

    if (sessions.isEmpty) {
      lines.add(_row(['No completed dialysis sessions on record.']));
    }

    return lines.join('\r\n');
  }

  // ------------------------------------------------------------ HTML

  /// Escapes text for HTML. Every value below comes from the database
  /// and could contain a `<` a patient typed, so nothing is interpolated
  /// raw.
  static String _esc(Object? value) {
    return (value?.toString() ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String buildPrintableHtml({
    required Map<String, dynamic> patient,
    required List<DialysisSession> sessions,
    required SessionHistorySummary summary,
  }) {
    final name = _text(patient['full_name']);
    final rows = StringBuffer();

    if (sessions.isEmpty) {
      rows.write(
        '<tr><td colspan="8" class="empty">'
        'No completed dialysis sessions on record for this patient.'
        '</td></tr>',
      );
    }

    for (final session in sessions) {
      final change = session.weightChange;

      rows.write(
        '<tr>'
        '<td class="date"><strong>${_esc(_rowDate.format(session.date))}</strong>'
        '<span>${_esc(_weekday.format(session.date))}</span></td>'
        '<td>${_esc(session.shift)}</td>'
        '<td>${_esc(_dash(session.beforeWeight?.toStringAsFixed(1)))}</td>'
        '<td>${_esc(_dash(session.afterWeight?.toStringAsFixed(1)))}</td>'
        '<td>${change == null ? '&mdash;' : _esc('${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}')}</td>'
        '<td>${_esc(_dash(session.bloodPressure))}</td>'
        '<td>${_esc(_dash(session.duration))}</td>'
        '<td>${_esc(session.status)}</td>'
        '</tr>',
      );
    }

    return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Session History — ${_esc(name)}</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 32px;
    background: #f4f7fa;
    color: #1f2d3d;
    font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
          Helvetica, Arial, sans-serif;
  }
  .sheet {
    max-width: 960px;
    margin: 0 auto;
    background: #fff;
    border: 1px solid #e4ebf1;
    border-radius: 14px;
    padding: 34px;
  }
  header { border-bottom: 2px solid #2a5f7e; padding-bottom: 18px; }
  .brand { color: #2a5f7e; font-size: 12px; font-weight: 700;
           letter-spacing: 1.4px; text-transform: uppercase; }
  h1 { color: #17435c; font-size: 25px; margin: 8px 0 4px; }
  .meta { color: #7c8b9b; font-size: 12px; }
  h2 { color: #17435c; font-size: 15px; margin: 30px 0 12px; }
  .grid {
    display: grid; gap: 12px;
    grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
  }
  .field {
    background: #f4f8fa; border: 1px solid #e4ebf1;
    border-radius: 10px; padding: 11px 13px;
  }
  .field span {
    display: block; color: #7c8b9b; font-size: 10.5px;
    font-weight: 700; letter-spacing: 0.7px; text-transform: uppercase;
  }
  .field strong { display: block; margin-top: 4px; font-size: 14px;
                  font-weight: 600; color: #1f2d3d; }
  table { width: 100%; border-collapse: collapse; margin-top: 4px; }
  th {
    background: #eff5f9; color: #4a5c70; font-size: 10.5px;
    font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase;
    text-align: left; padding: 10px; border-bottom: 1px solid #d6e0e8;
  }
  td { padding: 10px; border-bottom: 1px solid #eef3f7; font-size: 13px; }
  td.date span { display: block; color: #7c8b9b; font-size: 11px; }
  td.empty { text-align: center; color: #7c8b9b; padding: 26px; }
  tbody tr:nth-child(even) { background: #fbfdfe; }
  footer { margin-top: 26px; color: #7c8b9b; font-size: 11px;
           border-top: 1px solid #e4ebf1; padding-top: 14px; }
  @media print {
    body { background: #fff; padding: 0; }
    .sheet { border: 0; border-radius: 0; padding: 0; max-width: none; }
    thead { display: table-header-group; }
    tr { break-inside: avoid; }
  }
</style>
</head>
<body>
<div class="sheet">
  <header>
    <div class="brand">CureNurture &middot; Dialysis Session History</div>
    <h1>${_esc(name)}</h1>
    <div class="meta">
      ${_esc(_text(patient['clinics']?['name']))} &middot;
      Generated ${_esc(_timestamp.format(DateTime.now()))}
    </div>
  </header>

  <h2>Patient Information</h2>
  <div class="grid">
    <div class="field"><span>Full name</span><strong>${_esc(name)}</strong></div>
    <div class="field"><span>Date of birth</span><strong>${_esc(_birthDate(patient))}</strong></div>
    <div class="field"><span>Phone number</span><strong>${_esc(_text(patient['phone']))}</strong></div>
    <div class="field"><span>Address</span><strong>${_esc(_text(patient['home_address']))}</strong></div>
    <div class="field"><span>Email</span><strong>${_esc(_text(patient['email']))}</strong></div>
    <div class="field"><span>Blood type</span><strong>${_esc(_text(patient['blood_type']))}</strong></div>
  </div>

  <h2>Summary</h2>
  <div class="grid">
    <div class="field"><span>Completed sessions</span><strong>${summary.totalSessions}</strong></div>
    <div class="field"><span>First session</span><strong>${_esc(summary.firstSession == null ? '—' : _longDate.format(summary.firstSession!))}</strong></div>
    <div class="field"><span>Most recent session</span><strong>${_esc(summary.lastSession == null ? '—' : _longDate.format(summary.lastSession!))}</strong></div>
    <div class="field"><span>Average duration</span><strong>${_esc(summary.averageDurationLabel)}</strong></div>
    <div class="field"><span>Average weight change</span><strong>${_esc(summary.averageWeightChangeLabel)}</strong></div>
  </div>

  <h2>Session Records</h2>
  <table>
    <thead>
      <tr>
        <th>Date</th><th>Shift</th><th>Before (kg)</th><th>After (kg)</th>
        <th>Change (kg)</th><th>BP before</th><th>Duration</th><th>Status</th>
      </tr>
    </thead>
    <tbody>$rows</tbody>
  </table>

  <footer>
    This record covers ${sessions.length} session${sessions.length == 1 ? '' : 's'}
    for ${_esc(name)} only. It contains confidential patient information —
    handle it according to your center's data protection policy.
  </footer>
</div>
</body>
</html>''';
  }

  // -------------------------------------------------------- helpers

  static String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return 'Not provided';
    return text;
  }

  static String _dash(String? value) =>
      (value == null || value.isEmpty) ? '—' : value;

  static String _birthDate(Map<String, dynamic> patient) {
    final raw = patient['date_of_birth']?.toString();
    if (raw == null || raw.trim().isEmpty) return 'Not provided';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    return _longDate.format(parsed);
  }
}
