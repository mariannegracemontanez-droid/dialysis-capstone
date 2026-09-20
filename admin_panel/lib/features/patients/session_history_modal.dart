import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/dialysis_session.dart';
import '../../models/patient.dart';
import '../../services/session_history_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/file_download.dart';
import '../../utils/session_history_report.dart';
import '../../widgets/admin_modal.dart';
import '../../widgets/admin_notice.dart';

/// Opens one patient's dialysis **session history**.
///
/// Not their weekly schedule. The recurring schedule says which days a
/// patient normally comes in; this shows the sessions that actually took
/// place, read from `daily_schedules` where each row is one real session
/// with its before/after readings.
///
/// The patient is named in the header, in the summary strip and in every
/// downloaded file, so there is never a question of whose record is on
/// screen.
Future<void> showSessionHistory({
  required BuildContext context,
  required Patient patient,
}) {
  return showAdminDialog<void>(
    context: context,
    builder: (_) => _SessionHistoryModal(patient: patient),
  );
}

class _SessionHistoryModal extends StatefulWidget {
  final Patient patient;

  const _SessionHistoryModal({required this.patient});

  @override
  State<_SessionHistoryModal> createState() => _SessionHistoryModalState();
}

class _SessionHistoryModalState extends State<_SessionHistoryModal> {
  final SessionHistoryService _service = SessionHistoryService();
  final ScrollController _listScroll = ScrollController();

  static final DateFormat _rowDate = DateFormat('MMM d, y');
  static final DateFormat _weekday = DateFormat('EEEE');

  bool _loading = true;
  String? _error;

  /// The patient row as the database has it -- the download header is
  /// built from this rather than from the list item that was clicked, so
  /// the file always carries current, clinic-scoped details.
  Map<String, dynamic>? _patientRecord;
  List<DialysisSession> _sessions = const [];
  SessionHistorySummary? _summary;

  /// Cancelled dates are hidden by default: a session that did not happen
  /// is not history. The toggle exists because staff occasionally need to
  /// see a gap explained.
  bool _includeCancelled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _listScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final record = await _service.getPatientForHistory(widget.patient.id);

      if (record == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error =
              'This patient is not registered at your center, so their '
              'session history cannot be opened here.';
        });
        return;
      }

      final sessions = await _service.getSessionHistory(
        widget.patient.id,
        completedOnly: !_includeCancelled,
      );

      if (!mounted) return;

      setState(() {
        _patientRecord = record;
        _sessions = sessions;
        _summary = SessionHistoryService.summarize(sessions);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load session history error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'The session history could not be loaded. Please try again.';
      });
    }
  }

  Future<void> _download(_DownloadFormat format) async {
    final record = _patientRecord;
    final summary = _summary;

    if (record == null || summary == null) {
      AdminNotice.error(
        context,
        'The session history is still loading. Wait for it to finish, then '
        'download again.',
      );
      return;
    }

    // Always written from the freshly-loaded, clinic-scoped record, and
    // only ever this one patient's sessions.
    final name = record['full_name']?.toString() ?? widget.patient.name;

    try {
      switch (format) {
        case _DownloadFormat.html:
          downloadTextFile(
            fileName: SessionHistoryReport.fileName(
              patientName: name,
              extension: 'html',
            ),
            content: SessionHistoryReport.buildPrintableHtml(
              patient: record,
              sessions: _sessions,
              summary: summary,
            ),
            mimeType: 'text/html',
          );
        case _DownloadFormat.csv:
          downloadTextFile(
            fileName: SessionHistoryReport.fileName(
              patientName: name,
              extension: 'csv',
            ),
            content: SessionHistoryReport.buildCsv(
              patient: record,
              sessions: _sessions,
              summary: summary,
            ),
            mimeType: 'text/csv',
          );
      }

      if (!mounted) return;

      AdminNotice.success(
        context,
        '$name\'s session history (${_sessions.length} '
        'session${_sessions.length == 1 ? '' : 's'}) has been saved to your '
        'downloads.',
        title: 'Download started',
      );
    } catch (e) {
      debugPrint('Download session history error: $e');
      if (!mounted) return;
      AdminNotice.error(
        context,
        e is UnsupportedError
            ? (e.message ?? 'Downloading is not available here.')
            : 'The session history could not be downloaded. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminModal(
      title: 'Session History',
      subtitle: '${widget.patient.name} — completed dialysis sessions',
      icon: Icons.history_rounded,
      accent: AppTheme.accentTeal,
      accentSoft: AppTheme.accentTealSoft,
      size: AdminModalSize.xlarge,
      bodyPadding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: AppTheme.secondaryButton(),
          child: const Text('Close'),
        ),
        _downloadButton(),
      ],
      child: _body(),
    );
  }

  Widget _downloadButton() {
    final enabled = !_loading && _error == null;

    return AppMenuTheme(
      child: PopupMenuButton<_DownloadFormat>(
        enabled: enabled,
        tooltip: '',
        onSelected: _download,
        position: PopupMenuPosition.under,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _DownloadFormat.html,
            child: _DownloadOption(
              icon: Icons.description_rounded,
              label: 'Printable report (.html)',
              hint: 'Open in a browser and print or save as PDF',
            ),
          ),
          PopupMenuItem(
            value: _DownloadFormat.csv,
            child: _DownloadOption(
              icon: Icons.table_chart_rounded,
              label: 'Spreadsheet (.csv)',
              hint: 'Open in Excel or Google Sheets',
            ),
          ),
        ],
        child: AbsorbPointer(
          child: ElevatedButton.icon(
            onPressed: enabled ? () {} : null,
            icon: const Icon(Icons.download_rounded, size: 17),
            label: const Text('Download Session History'),
            style: AppTheme.primaryButton(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final error = _error;
    if (error != null) {
      return _message(
        icon: Icons.lock_outline_rounded,
        title: 'Session history unavailable',
        body: error,
        accent: AppTheme.danger,
        soft: AppTheme.dangerSoft,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _patientStrip(),
        const SizedBox(height: 16),
        _summaryCards(),
        const SizedBox(height: 18),
        _listHeader(),
        const SizedBox(height: 10),
        _sessionList(),
      ],
    );
  }

  /// Whose history this is, stated on the record itself and not only in
  /// the modal title.
  Widget _patientStrip() {
    final record = _patientRecord ?? const {};

    String value(Object? raw, String fallback) {
      final text = raw?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
      return text;
    }

    final birthDate = widget.patient.birthDate;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.surface, AppTheme.headerTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: AppTheme.iconBox(AppTheme.accentTealSoft),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppTheme.accentTeal,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SESSION HISTORY FOR', style: AppTheme.eyebrow),
                    const SizedBox(height: 4),
                    Text(
                      value(record['full_name'], widget.patient.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.blue3,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _detail(
                Icons.cake_rounded,
                'Date of birth',
                birthDate == null
                    ? value(record['date_of_birth'], 'Not provided')
                    : DateFormat('MMMM d, y').format(birthDate),
              ),
              _detail(
                Icons.phone_rounded,
                'Phone',
                value(record['phone'], 'Not provided'),
              ),
              _detail(
                Icons.home_rounded,
                'Address',
                value(record['home_address'], 'Not provided'),
              ),
              _detail(
                Icons.bloodtype_rounded,
                'Blood type',
                value(record['blood_type'], 'Not provided'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.iconMuted),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(), style: AppTheme.eyebrow),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCards() {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 620 ? 2 : 4;
        const gap = 12.0;
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        final cards = <Widget>[
          _stat(
            'Completed sessions',
            summary.totalSessions.toString(),
            Icons.check_circle_rounded,
            AppTheme.accentGreen,
            AppTheme.accentGreenSoft,
          ),
          _stat(
            'Most recent',
            summary.lastSession == null
                ? '--'
                : _rowDate.format(summary.lastSession!),
            Icons.event_available_rounded,
            AppTheme.blue1,
            AppTheme.accentBlueSoft,
          ),
          _stat(
            'Average duration',
            summary.averageDurationLabel,
            Icons.timer_rounded,
            AppTheme.accentTeal,
            AppTheme.accentTealSoft,
            footnote: summary.recordedDurations == 0
                ? 'Not recorded yet'
                : 'From ${summary.recordedDurations} session'
                      '${summary.recordedDurations == 1 ? '' : 's'}',
          ),
          _stat(
            'Average weight change',
            summary.averageWeightChangeLabel,
            Icons.monitor_weight_rounded,
            AppTheme.accentPurple,
            AppTheme.accentPurpleSoft,
            footnote: summary.recordedWeightChanges == 0
                ? 'Needs before and after weight'
                : 'From ${summary.recordedWeightChanges} session'
                      '${summary.recordedWeightChanges == 1 ? '' : 's'}',
          ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _stat(
    String label,
    String value,
    IconData icon,
    Color accent,
    Color soft, {
    String? footnote,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: AppTheme.iconBox(soft),
                child: Icon(icon, color: accent, size: 16),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.eyebrow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.blue3,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 3),
            Text(
              footnote,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _listHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text('Session Records', style: AppTheme.sectionTitle),
        ),
        Tooltip(
          message:
              'Cancelled dates are sessions that did not take place. They '
              'are hidden by default.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _includeCancelled,
                visualDensity: VisualDensity.compact,
                onChanged: (value) {
                  setState(() => _includeCancelled = value ?? false);
                  _load();
                },
              ),
              const Text(
                'Include cancelled / upcoming',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sessionList() {
    if (_sessions.isEmpty) {
      return _message(
        icon: Icons.event_busy_rounded,
        title: 'No sessions recorded yet',
        body:
            '${widget.patient.name} has no '
            '${_includeCancelled ? '' : 'completed '}dialysis sessions on '
            'record at this center. Sessions appear here once they are '
            'marked completed on the daily schedule.',
        accent: AppTheme.blue1,
        soft: AppTheme.accentBlueSoft,
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 340),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tableHeader(),
          Flexible(
            child: Scrollbar(
              controller: _listScroll,
              child: ListView.separated(
                controller: _listScroll,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _sessions.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppTheme.border,
                ),
                itemBuilder: (context, index) => _sessionRow(_sessions[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<({String label, int flex})> _columns = [
    (label: 'Date', flex: 3),
    (label: 'Shift', flex: 2),
    (label: 'Before', flex: 2),
    (label: 'After', flex: 2),
    (label: 'Change', flex: 2),
    (label: 'BP before', flex: 2),
    (label: 'Duration', flex: 2),
    (label: 'Status', flex: 2),
  ];

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceTint,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          for (final column in _columns)
            Expanded(
              flex: column.flex,
              child: Text(column.label.toUpperCase(), style: AppTheme.eyebrow),
            ),
        ],
      ),
    );
  }

  Widget _sessionRow(DialysisSession session) {
    final change = session.weightChange;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _rowDate.format(session.date),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _weekday.format(session.date),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: AdminPill(
              label: session.shift.isEmpty ? '--' : session.shift,
              color: AppTheme.accentTeal,
              background: AppTheme.accentTealSoft,
            ),
          ),
          _cell(
            flex: 2,
            text: session.beforeWeight == null
                ? '--'
                : '${session.beforeWeight!.toStringAsFixed(1)} kg',
          ),
          _cell(
            flex: 2,
            text: session.afterWeight == null
                ? '--'
                : '${session.afterWeight!.toStringAsFixed(1)} kg',
          ),
          _cell(
            flex: 2,
            text: change == null
                ? '--'
                : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} kg',
            color: change == null
                ? null
                : (change < 0 ? AppTheme.accentGreen : AppTheme.accentOrange),
          ),
          _cell(flex: 2, text: session.bloodPressure ?? '--'),
          _cell(flex: 2, text: session.duration ?? '--'),
          Expanded(flex: 2, child: _statusPill(session.status)),
        ],
      ),
    );
  }

  Widget _cell({required int flex, required String text, Color? color}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? AppTheme.textSecondary,
          fontSize: 12.5,
          fontWeight: color == null ? FontWeight.w500 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final (Color accent, Color soft, String label) = switch (status) {
      'completed' => (
        AppTheme.accentGreen,
        AppTheme.accentGreenSoft,
        'Completed',
      ),
      'cancelled' => (AppTheme.danger, AppTheme.dangerSoft, 'Cancelled'),
      'pending' => (AppTheme.accentOrange, AppTheme.accentOrangeSoft, 'Pending'),
      _ => (AppTheme.textMuted, AppTheme.surfaceTint, status),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: AdminPill(label: label, color: accent, background: soft),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    required Color accent,
    required Color soft,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: AppTheme.iconBox(soft, radius: AppTheme.rLg),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.blue3,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

enum _DownloadFormat { html, csv }

class _DownloadOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;

  const _DownloadOption({
    required this.icon,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppTheme.blue1),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              hint,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
