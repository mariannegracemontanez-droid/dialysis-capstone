import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/clinic_shift.dart';
import '../../models/reschedule_request.dart';
import '../../services/reschedule_request_service.dart';

/// The Center Admin view of patient reschedule requests submitted from the
/// mobile app. Reads the same `reschedule_requests` rows the mobile app
/// writes -- there is no admin-side copy of the list.
///
/// Deciding a request never edits the patient's recurring weekly schedule:
/// accept / change date create a ONE-TIME occurrence on the granted date
/// and cancel the original date's occurrence, both inside a single
/// database function.
class RescheduleRequestsSection extends StatefulWidget {
  final String clinicId;

  /// Called after a decision changes a schedule, so the dashboard can
  /// refresh Today's Schedule if the granted date is the one on screen.
  final VoidCallback? onRequestApplied;

  const RescheduleRequestsSection({
    super.key,
    required this.clinicId,
    this.onRequestApplied,
  });

  @override
  State<RescheduleRequestsSection> createState() =>
      RescheduleRequestsSectionState();
}

class RescheduleRequestsSectionState extends State<RescheduleRequestsSection> {
  final RescheduleRequestService _service = RescheduleRequestService();

  static const Color primary = Color(0xFF245C78);
  static const Color border = Color(0xFFE1E8EF);
  static const Color textDark = Color(0xFF1F2D3D);
  static const Color textMuted = Color(0xFF6B7A8C);
  static const Color green = Color(0xFF10B981);
  static const Color orange = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF8E44AD);
  static const Color red = Color(0xFFDC2626);
  static const Color softBg = Color(0xFFF8FAFC);

  List<RescheduleRequest> _requests = [];
  bool _isLoading = true;
  String? _error;
  String? _expandedId;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant RescheduleRequestsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final requests = await _service.getRequests(clinicId: widget.clinicId);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load reschedule requests error: $e');
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _isLoading = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? red : green,
        duration: Duration(seconds: isError ? 6 : 4),
      ),
    );
  }

  String _formatDate(DateTime? date, {String fallback = 'Not set'}) {
    if (date == null) return fallback;
    return DateFormat('EEE, MMM d, yyyy').format(date);
  }

  String _formatShortDate(DateTime? date, {String fallback = '—'}) {
    if (date == null) return fallback;
    return DateFormat('MMM d').format(date);
  }

  // ------------------------------------------------------------------
  // Decisions
  // ------------------------------------------------------------------

  /// Accept on the date the patient asked for. The conflict/capacity check
  /// runs first so the admin gets a readable explanation (and the option
  /// to pick another date) instead of a raw database error.
  Future<void> _accept(RescheduleRequest request) async {
    final date = request.requestedDate;

    if (date == null) {
      _showMessage(
        'This patient did not pick a date. Use Change Date to set one.',
        isError: true,
      );
      return;
    }

    final problem = await _service.validateTarget(
      clinicId: widget.clinicId,
      patientId: request.patientId,
      date: date,
    );

    if (!mounted) return;

    if (problem != null) {
      final pickAnother = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('That date cannot be used'),
          content: Text('$problem\n\nWould you like to pick another date?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Change Date'),
            ),
          ],
        ),
      );

      if (pickAnother == true && mounted) await _changeDate(request);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept reschedule request'),
        content: Text(
          'Move ${request.patientName}\'s session from '
          '${_formatDate(request.originalDate, fallback: 'their usual day')} '
          'to ${_formatDate(date)}?\n\n'
          'This is a one-time change. Their recurring weekly schedule stays '
          'exactly as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _run(request.id, () async {
      final result = await _service.accept(requestId: request.id);
      _showMessage(
        '${request.patientName} is scheduled for ${_formatDate(date)} '
        '(${result['shift'] ?? ''} shift). Their recurring schedule is '
        'unchanged.',
      );
    });
  }

  Future<void> _reject(RescheduleRequest request) async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject reschedule request'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reject ${request.patientName}\'s request? Their schedule is '
                'not changed in any way.',
                style: const TextStyle(color: textDark, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Reason for the patient (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject request'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    final note = noteController.text.trim();
    noteController.dispose();

    await _run(request.id, () async {
      await _service.reject(
        requestId: request.id,
        adminNotes: note.isEmpty ? null : note,
      );
      _showMessage('Request from ${request.patientName} rejected.');
    });
  }

  /// Accept, but on a date (and optionally a shift) the admin chooses.
  Future<void> _changeDate(RescheduleRequest request) async {
    final shifts = await _service.getActiveShifts(widget.clinicId);
    if (!mounted) return;

    final result = await showDialog<(DateTime, String?, String?)>(
      context: context,
      builder: (ctx) => _ChangeDateDialog(
        request: request,
        shifts: shifts,
        validate: (date, shiftCode) => _service.validateTarget(
          clinicId: widget.clinicId,
          patientId: request.patientId,
          date: date,
          shiftCode: shiftCode,
        ),
      ),
    );

    if (result == null) return;

    final (date, shiftCode, note) = result;

    await _run(request.id, () async {
      final applied = await _service.changeDate(
        requestId: request.id,
        date: date,
        shiftCode: shiftCode,
        adminNotes: note,
      );
      _showMessage(
        '${request.patientName} is scheduled for ${_formatDate(date)} '
        '(${applied['shift'] ?? ''} shift). Their recurring schedule is '
        'unchanged.',
      );
    });
  }

  Future<void> _run(String requestId, Future<void> Function() action) async {
    setState(() => _busyId = requestId);

    try {
      await action();
      await load();
      widget.onRequestApplied?.call();
    } catch (e) {
      debugPrint('Reschedule decision error: $e');
      if (mounted) _showMessage(_friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  (Color, String) _statusStyle(RescheduleRequest request) {
    switch (request.status) {
      case 'approved':
        return (green, request.statusLabel);
      case 'changed_date':
        return (purple, request.statusLabel);
      case 'declined':
        return (red, request.statusLabel);
      case 'cancelled':
        return (textMuted, request.statusLabel);
      default:
        return (orange, request.statusLabel);
    }
  }

  Widget _statusPill(RescheduleRequest request) {
    final (color, label) = _statusStyle(request);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textDark,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestTile(RescheduleRequest request) {
    final isExpanded = _expandedId == request.id;
    final isBusy = _busyId == request.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: request.isPending ? Colors.white : softBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: request.isPending ? orange.withOpacity(0.35) : border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFFE0F2FE),
                  child: Text(
                    request.patientName.trim().isEmpty
                        ? 'P'
                        : request.patientName.trim()[0].toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF0369A1),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    request.patientName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: textDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: Text(
                    '${_formatShortDate(request.originalDate)} → '
                    '${_formatShortDate(request.displayDate)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _statusPill(request),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () => setState(
                    () => _expandedId = isExpanded ? null : request.id,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    minimumSize: const Size(52, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: Text(isExpanded ? 'Hide' : 'View'),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailLine(
                    'Original date',
                    _formatDate(request.originalDate),
                  ),
                  _detailLine(
                    'Requested date',
                    _formatDate(
                      request.requestedDate,
                      fallback: 'Not specified by the patient',
                    ),
                  ),
                  _detailLine('Date requested', _formatDate(request.createdAt)),
                  _detailLine('Reason', request.reason ?? 'Not given'),
                  if (request.notes != null)
                    _detailLine('Patient notes', request.notes!),
                  _detailLine('Status', request.statusLabel),
                  if (request.isGranted && request.resolvedDate != null)
                    _detailLine(
                      'Scheduled for',
                      '${_formatDate(request.resolvedDate)}'
                      '${request.resolvedShift == null ? '' : ' • ${request.resolvedShift} shift'}',
                    ),
                  if (request.adminNotes != null)
                    _detailLine('Your note', request.adminNotes!),
                  const SizedBox(height: 10),
                  if (request.isPending)
                    isBusy
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _accept(request),
                                icon: const Icon(Icons.check_rounded, size: 15),
                                label: const Text('Accept'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _reject(request),
                                icon: const Icon(Icons.close_rounded, size: 15),
                                label: const Text('Reject'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: red,
                                  side: BorderSide(
                                    color: red.withOpacity(0.45),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _changeDate(request),
                                icon: const Icon(
                                  Icons.event_rounded,
                                  size: 15,
                                ),
                                label: const Text('Change Date'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primary,
                                  side: BorderSide(
                                    color: primary.withOpacity(0.45),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          )
                  else
                    Text(
                      'Reviewed ${_formatDate(request.reviewedAt, fallback: 'earlier')}.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(color: primary)),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: red.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Could not load reschedule requests: $_error',
                style: const TextStyle(
                  fontSize: 12,
                  color: textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_requests.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: softBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: const Text(
          'No reschedule requests from patients yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final pendingCount = _requests.where((r) => r.isPending).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              pendingCount == 0
                  ? 'No pending requests'
                  : '$pendingCount pending request${pendingCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: pendingCount == 0 ? textMuted : orange,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              onPressed: load,
              iconSize: 17,
              color: textMuted,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Fixed height + scroll, the same pattern the other dashboard
        // lists use, so a busy week never stretches the page.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 330),
          child: Scrollbar(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(right: 6),
              itemCount: _requests.length,
              itemBuilder: (context, index) => _requestTile(_requests[index]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Date + shift picker for "Change Date", with the same capacity/conflict
/// check the accept path runs, applied before the dialog closes.
class _ChangeDateDialog extends StatefulWidget {
  final RescheduleRequest request;
  final List<ClinicShift> shifts;
  final Future<String?> Function(DateTime date, String? shiftCode) validate;

  const _ChangeDateDialog({
    required this.request,
    required this.shifts,
    required this.validate,
  });

  @override
  State<_ChangeDateDialog> createState() => _ChangeDateDialogState();
}

class _ChangeDateDialogState extends State<_ChangeDateDialog> {
  static const Color primary = Color(0xFF245C78);
  static const Color textDark = Color(0xFF1F2D3D);
  static const Color textMuted = Color(0xFF6B7A8C);
  static const Color red = Color(0xFFDC2626);

  DateTime? _date;

  /// Null means "keep the patient's own default shift for that weekday",
  /// read from patient_schedule_days -- never written to.
  String? _shiftCode;

  final TextEditingController _noteController = TextEditingController();

  bool _isChecking = false;
  String? _problem;

  @override
  void initState() {
    super.initState();

    final requested = widget.request.requestedDate;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);

    if (requested != null && !requested.isBefore(startOfToday)) {
      _date = requested;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 120)),
      selectableDayPredicate: (day) => day.weekday != DateTime.sunday,
    );

    if (picked != null) {
      setState(() {
        _date = picked;
        _problem = null;
      });
    }
  }

  Future<void> _confirm() async {
    final date = _date;
    if (date == null) {
      setState(() => _problem = 'Please pick a date.');
      return;
    }

    setState(() {
      _isChecking = true;
      _problem = null;
    });

    final problem = await widget.validate(date, _shiftCode);

    if (!mounted) return;

    if (problem != null) {
      setState(() {
        _isChecking = false;
        _problem = problem;
      });
      return;
    }

    final note = _noteController.text.trim();

    Navigator.of(context).pop((date, _shiftCode, note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change dialysis date'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.request.patientName} — this changes one session only. '
              'Their recurring weekly schedule and default shift stay as they '
              'are.',
              style: const TextStyle(
                fontSize: 12,
                color: textMuted,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _isChecking ? null : _pickDate,
              icon: const Icon(Icons.event_rounded, size: 17),
              label: Text(
                _date == null
                    ? 'Pick a new date'
                    : DateFormat('EEE, MMM d, yyyy').format(_date!),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                alignment: Alignment.centerLeft,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Shift',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: textDark,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String?>(
              initialValue: _shiftCode,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text("Use the patient's usual shift"),
                ),
                ...widget.shifts.map(
                  (shift) => DropdownMenuItem<String?>(
                    value: shift.shiftCode,
                    child: Text(
                      '${shift.shiftCode} — ${shift.displayLabel}',
                    ),
                  ),
                ),
              ],
              onChanged: _isChecking
                  ? null
                  : (value) => setState(() {
                      _shiftCode = value;
                      _problem = null;
                    }),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              maxLines: 2,
              maxLength: 300,
              enabled: !_isChecking,
              decoration: const InputDecoration(
                labelText: 'Note for the patient (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: red.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: red.withOpacity(0.25)),
                ),
                child: Text(
                  _problem!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: red,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isChecking ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isChecking ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
          ),
          child: _isChecking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save new date'),
        ),
      ],
    );
  }
}
