import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/center_schedule.dart';
import '../../models/clinic_shift.dart';
import '../../models/patient.dart';
import '../../models/schedule_recommendation.dart';
import '../../services/center_schedule_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/schedule_recommendation_service.dart';

// Mirrors dashboard_page.dart's palette so this modal reads as part of the
// same screen -- kept local since those constants are private to that
// file's State class.
const Color _primary = Color(0xFF245C78);
const Color _primaryDark = Color(0xFF17435C);
const Color _border = Color(0xFFE1E8EF);
const Color _textDark = Color(0xFF1F2D3D);
const Color _textMuted = Color(0xFF6B7A8C);
const Color _green = Color(0xFF10B981);
const Color _orange = Color(0xFFF59E0B);
const Color _red = Color(0xFFEF4444);
const Color _softBg = Color(0xFFF8FAFC);

/// Opens the recurring schedule assignment modal for a patient who
/// doesn't have one yet (the "Patients Needing Schedule" table).
///
/// Flow: patient information -> suggested schedule -> day selection ->
/// a single default shift -> one save that persists days and shift
/// together. [onScheduled] fires only after that save succeeds, so
/// generating or applying a suggestion never moves the patient out of
/// the unscheduled list on its own.
Future<void> showPatientScheduleModal(
  BuildContext context, {
  required Patient patient,
  required VoidCallback onScheduled,
}) {
  return showDialog(
    context: context,
    builder: (_) => _PatientScheduleModal(
      patient: patient,
      onScheduled: onScheduled,
    ),
  );
}

class _PatientScheduleModal extends StatefulWidget {
  final Patient patient;
  final VoidCallback onScheduled;

  const _PatientScheduleModal({
    required this.patient,
    required this.onScheduled,
  });

  @override
  State<_PatientScheduleModal> createState() => _PatientScheduleModalState();
}

class _PatientScheduleModalState extends State<_PatientScheduleModal> {
  final CenterScheduleService _centerScheduleService = CenterScheduleService();
  final ScheduleRecommendationService _recommendationService =
      ScheduleRecommendationService();
  final DashboardService _dashboardService = DashboardService();

  String? _clinicId;
  bool _isLoadingContext = true;
  String? _contextError;

  int? _sessionsPerWeek;
  List<ClinicShift> _shifts = [];
  PatientRecurringSchedule? _existingSchedule;

  final Set<String> _selectedDays = {};

  /// One shift for the whole recurring schedule. Stored per day in
  /// patient_schedule_days (so different days can differ later) but
  /// chosen once here to keep the flow simple.
  String? _defaultShiftId;

  Map<String, DayShiftStatus> _dayStatus = {};
  bool _isValidating = false;

  bool _isGeneratingRecommendation = true;
  ScheduleRecommendationResult? _recommendationResult;
  String? _recommendationError;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _red : _green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadContext() async {
    setState(() {
      _isLoadingContext = true;
      _contextError = null;
    });

    try {
      final clinicId = widget.patient.clinicId ??
          await _dashboardService.getCurrentClinicId();

      if (clinicId == null) {
        throw Exception('No clinic assigned to this admin account.');
      }

      final shifts = await _centerScheduleService.getClinicShifts(
        clinicId,
        activeOnly: true,
      );
      final sessionsPerWeek =
          await _centerScheduleService.getSessionsPerWeek(widget.patient.id);
      final existingSchedule =
          await _centerScheduleService.getPatientRecurringSchedule(
        widget.patient.id,
      );

      if (!mounted) return;
      setState(() {
        _clinicId = clinicId;
        _shifts = shifts;
        _sessionsPerWeek = sessionsPerWeek;
        _existingSchedule = existingSchedule;
        _isLoadingContext = false;
      });

      if (existingSchedule == null) {
        _loadRecommendation();
      } else {
        setState(() => _isGeneratingRecommendation = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contextError = 'Could not load scheduling data: $e';
        _isLoadingContext = false;
        _isGeneratingRecommendation = false;
      });
    }
  }

  Future<void> _loadRecommendation() async {
    final clinicId = _clinicId;
    if (clinicId == null) return;

    setState(() {
      _isGeneratingRecommendation = true;
      _recommendationError = null;
    });

    try {
      final result = await _recommendationService.generateSuggestedSchedule(
        patientId: widget.patient.id,
        clinicId: clinicId,
      );
      if (!mounted) return;
      setState(() {
        _recommendationResult = result;
        _isGeneratingRecommendation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recommendationError = 'Could not load a suggested schedule: $e';
        _isGeneratingRecommendation = false;
      });
    }
  }

  void _toggleDay(String day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
        _dayStatus.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
    _revalidate();
  }

  /// Applies the suggested DAYS only. The default shift stays the
  /// admin's choice below -- the system doesn't silently pick a shift
  /// for a new patient.
  void _applyRecommendation(ScheduleRecommendation recommendation) {
    setState(() {
      _selectedDays
        ..clear()
        ..addAll(recommendation.days);
    });
    _revalidate();
    _showSnack(
      'Suggested days applied. Choose a default shift below, then save.',
    );
  }

  List<DayShiftSelection> get _selections {
    final shiftId = _defaultShiftId;
    if (shiftId == null) return const [];
    return _selectedDays
        .map((day) => DayShiftSelection(day: day, shiftId: shiftId))
        .toList();
  }

  Future<void> _revalidate() async {
    final clinicId = _clinicId;
    final selections = _selections;

    if (clinicId == null || selections.isEmpty) {
      setState(() => _dayStatus = {});
      return;
    }

    setState(() => _isValidating = true);

    try {
      final results = await _centerScheduleService.validateScheduleAssignment(
        clinicId: clinicId,
        dayShifts: selections,
      );
      if (!mounted) return;
      setState(() {
        _dayStatus = {for (final r in results) r.day: r};
        _isValidating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isValidating = false);
    }
  }

  Future<void> _save() async {
    final clinicId = _clinicId;
    if (clinicId == null) return;

    if (_selectedDays.isEmpty) {
      _showSnack('Please select at least one day.', isError: true);
      return;
    }

    if (_defaultShiftId == null) {
      _showSnack('Please choose a default shift.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // One authoritative check (frequency, duplicates, existing
      // schedule, operating day, shift availability, capacity), re-run
      // against current data. The database enforces the same rules again
      // on write.
      final validationError =
          await _centerScheduleService.validateFinalAssignment(
        patientId: widget.patient.id,
        clinicId: clinicId,
        dayShifts: _selections,
      );

      if (validationError != null) {
        setState(() => _isSaving = false);
        _showSnack(validationError, isError: true);
        await _revalidate();
        return;
      }

      // Days and default shift are persisted in a single operation.
      await _centerScheduleService.setPatientRecurringSchedule(
        patientId: widget.patient.id,
        clinicId: clinicId,
        dayShifts: _selections,
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onScheduled();
    } on PostgrestException catch (e) {
      setState(() => _isSaving = false);
      _showSnack(e.message, isError: true);
    } catch (e) {
      setState(() => _isSaving = false);
      _showSnack('Error: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 760),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: _isLoadingContext
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: CircularProgressIndicator(color: _primary),
                          ),
                        )
                      : _contextError != null
                          ? _buildErrorState()
                          : _buildContent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = widget.patient.name;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryDark, _primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white,
            child: Text(
              initial,
              style: const TextStyle(
                color: _primary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Assign recurring weekly schedule',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _contextError!,
          style: const TextStyle(color: _red, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: _loadContext, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildContent() {
    if (_existingSchedule != null && _existingSchedule!.isActive) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _orange.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _orange.withOpacity(0.3)),
        ),
        child: const Text(
          'This patient already has an active recurring schedule. Managing '
          'an existing schedule isn\'t available from this screen.',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w700),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPatientInfo(),
        const SizedBox(height: 20),
        _buildSuggestedSchedule(),
        const SizedBox(height: 20),
        const Text(
          'Dialysis Days',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Select the days this patient will regularly receive dialysis.',
          style: TextStyle(color: _textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _buildDayPills(),
        if (_dayStatus.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildDayStatusList(),
        ],
        const SizedBox(height: 20),
        _buildDefaultShiftSection(),
        const SizedBox(height: 22),
        _buildFooter(),
      ],
    );
  }

  Widget _buildPatientInfo() {
    final stage = widget.patient.dialysisStage;
    final sessionsLabel =
        _sessionsPerWeek == null ? 'Not specified' : '$_sessionsPerWeek / week';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _infoItem(
            'Dialysis Stage',
            stage?.trim().isNotEmpty == true ? stage! : 'Not specified',
          ),
          _infoItem('Required Sessions', sessionsLabel),
          _infoItem('Schedule Status', 'No recurring schedule yet'),
        ],
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _textDark,
            ),
          ),
        ],
      ),
    );
  }

  /// Clickable day pills, matching the selector style used elsewhere in
  /// the admin panel.
  Widget _buildDayPills() {
    const shortLabels = {
      'Monday': 'Mon',
      'Tuesday': 'Tue',
      'Wednesday': 'Wed',
      'Thursday': 'Thu',
      'Friday': 'Fri',
      'Saturday': 'Sat',
    };

    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: CenterScheduleService.allDays.map((day) {
        final isSelected = _selectedDays.contains(day);

        return FilterChip(
          label: Text(shortLabels[day] ?? day),
          selected: isSelected,
          onSelected: (_) => _toggleDay(day),
          backgroundColor: _softBg,
          selectedColor: _primary,
          checkmarkColor: Colors.white,
          side: BorderSide(color: isSelected ? _primary : _border),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : _textDark,
            fontWeight: FontWeight.w900,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        );
      }).toList(),
    );
  }

  /// Capacity feedback for the chosen days, shown once a default shift
  /// has been picked (availability is per day + shift).
  Widget _buildDayStatusList() {
    final days = CenterScheduleService.allDays
        .where((d) => _selectedDays.contains(d) && _dayStatus.containsKey(d))
        .toList();

    if (days.isEmpty) return const SizedBox.shrink();

    return Column(
      children: days.map((day) {
        final status = _dayStatus[day]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  day,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                  ),
                ),
              ),
              _statusChip(status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.message,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _textMuted),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// The single default shift for this recurring schedule, chosen at the
  /// end of the flow and saved together with the selected days.
  Widget _buildDefaultShiftSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Default Shift',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "The patient's usual shift on their dialysis days. It seeds "
            "Today's Dialysis Schedule; the daily list can still be "
            'adjusted on the day itself.',
            style: TextStyle(color: _textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_shifts.isEmpty)
            const Text(
              'This center has no active shifts configured.',
              style: TextStyle(color: _red, fontSize: 12),
            )
          else
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey('default-shift-$_defaultShiftId'),
                initialValue: _defaultShiftId,
                isDense: true,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
                hint: const Text(
                  'Select shift',
                  style: TextStyle(fontSize: 13),
                ),
                items: _shifts
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.shiftCode} — ${s.displayLabel}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _defaultShiftId = value);
                  _revalidate();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(DayShiftStatus status) {
    late final Color color;
    late final String label;

    switch (status.availability) {
      case DayShiftAvailability.available:
        color = _green;
        label = 'Available';
        break;
      case DayShiftAvailability.nearCapacity:
        color = _orange;
        label = 'Near Capacity';
        break;
      case DayShiftAvailability.full:
        color = _red;
        label = 'Full';
        break;
      case DayShiftAvailability.centerClosed:
        color = _red;
        label = 'Center Closed';
        break;
      case DayShiftAvailability.shiftInactive:
        color = _red;
        label = 'Unavailable';
        break;
    }

    return Tooltip(
      message: status.message,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedSchedule() {
    final result = _recommendationResult;
    final best =
        (result != null && result.success && result.recommendations.isNotEmpty)
            ? result.recommendations.first
            : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Suggested Weekly Schedule',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isGeneratingRecommendation)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primary,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Analyzing weekly schedule...',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else if (_recommendationError != null || best == null)
            const Text(
              'No suitable schedule available.',
              style: TextStyle(color: _textMuted, fontSize: 13),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _primary.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: best.days
                        .map(
                          (day) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF5FA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              day,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: _textDark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${best.matchPercent}% Match',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () => _applyRecommendation(best),
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                      ),
                      label: const Text('Apply Suggestion'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: _textDark,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: (_isSaving || _isValidating) ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded, size: 18),
          label: Text(_isSaving ? 'Saving...' : 'Save Schedule'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}
