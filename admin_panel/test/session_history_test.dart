// Session history: the read model over daily_schedules, the summary the
// view shows, and the two files the admin can download.
//
// The download cases matter most. A history file leaves the building --
// it goes into a patient folder or a referral -- so the two things it can
// never get wrong are whose record it is and whether the numbers in it
// were really recorded. Both are asserted here.

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/models/dialysis_session.dart';
import 'package:admin_panel/services/session_history_service.dart';
import 'package:admin_panel/utils/session_history_report.dart';

DialysisSession _session({
  required String id,
  required String date,
  String shift = 'AM',
  String status = 'completed',
  double? beforeWeight,
  double? afterWeight,
  int? systolic,
  int? diastolic,
  int? hours,
  int? minutes,
}) {
  return DialysisSession.fromJson({
    'id': id,
    'schedule_date': date,
    'shift': shift,
    'status': status,
    'before_weight': beforeWeight,
    'after_weight': afterWeight,
    'before_systolic': systolic,
    'before_diastolic': diastolic,
    'duration_hours': hours,
    'duration_minutes': minutes,
  });
}

final _patient = <String, dynamic>{
  'id': 'p1',
  'full_name': 'Juan Dela Cruz',
  'email': 'juan@example.com',
  'phone': '0917 123 4567',
  'home_address': '12 Maysan Road, Valenzuela',
  'date_of_birth': '1970-05-02',
  'blood_type': 'O+',
  'clinics': {'name': 'Valenzuela Dialysis Center'},
};

void main() {
  group('DialysisSession', () {
    test('reads a completed daily_schedules row', () {
      final session = _session(
        id: 's1',
        date: '2026-09-18',
        beforeWeight: 63.5,
        afterWeight: 61.2,
        systolic: 140,
        diastolic: 90,
        hours: 3,
        minutes: 30,
      );

      expect(session.isCompleted, isTrue);
      expect(session.bloodPressure, '140/90');
      expect(session.duration, '3h 30m');
      expect(session.durationInMinutes, 210);
      expect(session.weightChange, closeTo(-2.3, 0.001));
    });

    test('a missing weight yields no change rather than a wrong one', () {
      final session = _session(id: 's2', date: '2026-09-16', beforeWeight: 63);

      expect(session.weightChange, isNull);
      expect(session.hasBeforeData, isTrue);
      expect(session.hasAfterData, isFalse);
    });

    test('a missing blood pressure half is not half a reading', () {
      expect(
        _session(id: 's3', date: '2026-09-14', systolic: 130).bloodPressure,
        isNull,
      );
    });

    test('a recorded zero duration is kept, an unrecorded one is not', () {
      expect(
        _session(id: 's4', date: '2026-09-12', hours: 0, minutes: 0).duration,
        '0m',
      );
      expect(_session(id: 's5', date: '2026-09-10').duration, isNull);
    });
  });

  group('summary', () {
    test('averages only the sessions that recorded a value', () {
      final summary = SessionHistoryService.summarize([
        _session(
          id: 's1',
          date: '2026-09-18',
          beforeWeight: 63,
          afterWeight: 61,
          hours: 4,
          minutes: 0,
        ),
        _session(
          id: 's2',
          date: '2026-09-16',
          beforeWeight: 62,
          afterWeight: 60,
          hours: 3,
          minutes: 0,
        ),
        // Nothing recorded: must lower the sample size, not the average.
        _session(id: 's3', date: '2026-09-14'),
      ]);

      expect(summary.totalSessions, 3);
      expect(summary.recordedDurations, 2);
      expect(summary.recordedWeightChanges, 2);
      expect(summary.averageDurationMinutes, 210);
      expect(summary.averageDurationLabel, '3h 30m');
      expect(summary.averageWeightChange, closeTo(-2.0, 0.001));
      expect(summary.averageWeightChangeLabel, '-2.00 kg');
    });

    test('first and last come from a newest-first list', () {
      final summary = SessionHistoryService.summarize([
        _session(id: 's1', date: '2026-09-18'),
        _session(id: 's2', date: '2026-09-16'),
        _session(id: 's3', date: '2026-09-14'),
      ]);

      expect(summary.firstSession, DateTime(2026, 9, 14));
      expect(summary.lastSession, DateTime(2026, 9, 18));
    });

    test('an empty history reports nothing rather than zero', () {
      final summary = SessionHistoryService.summarize(const []);

      expect(summary.totalSessions, 0);
      expect(summary.averageDurationMinutes, isNull);
      expect(summary.averageDurationLabel, '--');
      expect(summary.averageWeightChangeLabel, '--');
    });

    test('pending and cancelled rows are not counted as history', () {
      final summary = SessionHistoryService.summarize([
        _session(id: 's1', date: '2026-09-18'),
        _session(id: 's2', date: '2026-09-20', status: 'pending'),
        _session(id: 's3', date: '2026-09-16', status: 'cancelled'),
      ]);

      expect(summary.totalSessions, 1);
    });
  });

  group('downloaded file', () {
    final sessions = [
      _session(
        id: 's1',
        date: '2026-09-18',
        beforeWeight: 63.5,
        afterWeight: 61.2,
        systolic: 140,
        diastolic: 90,
        hours: 3,
        minutes: 30,
      ),
      _session(id: 's2', date: '2026-09-16', shift: 'PM', beforeWeight: 62.8),
    ];

    final summary = SessionHistoryService.summarize(sessions);

    test('the file name identifies the patient and the day', () {
      final name = SessionHistoryReport.fileName(
        patientName: 'Juan Dela Cruz',
        extension: 'csv',
      );

      expect(name, startsWith('session-history_juan-dela-cruz_'));
      expect(name, endsWith('.csv'));
    });

    test('a name with no usable characters still produces a file name', () {
      expect(
        SessionHistoryReport.fileName(patientName: '***', extension: 'html'),
        startsWith('session-history_patient_'),
      );
    });

    group('CSV', () {
      final csv = SessionHistoryReport.buildCsv(
        patient: _patient,
        sessions: sessions,
        summary: summary,
      );

      test('opens with the patient identification the record needs', () {
        expect(csv, contains('Patient name,Juan Dela Cruz'));
        expect(csv, contains('Date of birth,"May 2, 1970"'));
        expect(csv, contains('Phone number,0917 123 4567'));
        expect(csv, contains('Address,"12 Maysan Road, Valenzuela"'));
      });

      test('carries every session row', () {
        expect(csv, contains('63.5'));
        expect(csv, contains('61.2'));
        expect(csv, contains('140/90'));
        expect(csv, contains('3h 30m'));
      });

      test('quotes a value containing a comma so columns do not shift', () {
        // The address has a comma in it; unquoted it would split the row.
        expect(csv, contains('"12 Maysan Road, Valenzuela"'));
      });

      test('says so plainly when there is no history', () {
        final empty = SessionHistoryReport.buildCsv(
          patient: _patient,
          sessions: const [],
          summary: SessionHistoryService.summarize(const []),
        );

        expect(empty, contains('No completed dialysis sessions on record.'));
        expect(empty, contains('Patient name,Juan Dela Cruz'));
      });
    });

    group('printable report', () {
      final html = SessionHistoryReport.buildPrintableHtml(
        patient: _patient,
        sessions: sessions,
        summary: summary,
      );

      test('names the patient in the title and the header', () {
        expect(html, contains('<title>Session History — Juan Dela Cruz'));
        expect(html, contains('<h1>Juan Dela Cruz</h1>'));
      });

      test('prints the identification block', () {
        expect(html, contains('May 2, 1970'));
        expect(html, contains('0917 123 4567'));
        expect(html, contains('12 Maysan Road, Valenzuela'));
      });

      test('carries one row per session and nobody else\'s', () {
        expect(html, contains('63.5'));
        expect(html, contains('140/90'));
        expect(html, contains('covers 2 sessions'));
      });

      test('escapes text so a typed angle bracket cannot become markup', () {
        final escaped = SessionHistoryReport.buildPrintableHtml(
          patient: {..._patient, 'full_name': 'Ana <script>alert(1)</script>'},
          sessions: const [],
          summary: SessionHistoryService.summarize(const []),
        );

        expect(escaped, isNot(contains('<script>alert(1)</script>')));
        expect(escaped, contains('&lt;script&gt;'));
      });

      test('a missing value reads as absent, never as zero', () {
        // s2 has no after-weight: the change column must be a dash.
        expect(html, contains('&mdash;'));
        expect(html, isNot(contains('+0.0')));
      });
    });
  });
}
