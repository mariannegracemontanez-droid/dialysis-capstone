import 'package:admin_panel/services/schedule_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../../models/center_schedule.dart';
import '../../models/clinic_shift.dart';
import '../../services/center_schedule_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/admin_validators.dart';
import '../../widgets/admin_modal.dart';
import '../../widgets/admin_notice.dart';

class TodayScheduleSection extends StatefulWidget {
  final String clinicId;
  final int machineCount;

  /// Fired after this section changes a day's schedule, so the dashboard
  /// can refresh anything that reads the same data (the reschedule
  /// requests list, for one).
  final VoidCallback? onScheduleChanged;

  const TodayScheduleSection({
    super.key,
    required this.clinicId,
    required this.machineCount,
    this.onScheduleChanged,
  });

  @override
  State<TodayScheduleSection> createState() => TodayScheduleSectionState();
}

class TodayScheduleSectionState extends State<TodayScheduleSection> {
  final ScheduleService _service = ScheduleService();
  final CenterScheduleService _centerScheduleService = CenterScheduleService();

  List<ClinicShift> _shifts = [];

  /// patientId -> default shift code, for the day currently shown. Used
  /// only to label a row as recurring vs. manually added.
  Map<String, String> _recurringShifts = {};

  /// This DATE's capacity picture, straight from
  /// CenterScheduleService.getDateCapacity -- the one capacity
  /// calculation in the app. Cancelled (removed) occupants never count,
  /// so removing a patient frees a seat and adding one takes it.
  DayCapacity? _dateCapacity;

  ShiftCapacity? _shiftCapacityFor(String shiftCode) {
    for (final entry in _dateCapacity?.shifts ?? const <ShiftCapacity>[]) {
      if (entry.shift.shiftCode == shiftCode) return entry;
    }
    return null;
  }

  /// Configured capacity for a shift code -- never a naive machine-count
  /// assumption. Falls back to the raw clinic_shifts figure, and then the
  /// machine count, only while the date snapshot hasn't loaded yet.
  int _capacityFor(String shiftCode) {
    final entry = _shiftCapacityFor(shiftCode);
    if (entry != null) return entry.effectiveCapacity;

    for (final shift in _shifts) {
      if (shift.shiftCode == shiftCode) return shift.capacity;
    }
    return widget.machineCount;
  }

  /// Outcomes from this section are raised through the one notice
  /// system. It matters here more than anywhere: add, move, remove and
  /// the session form are all driven from inside a modal, and a snack bar
  /// raised from there used to be painted underneath it.
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    if (isError) {
      AdminNotice.error(context, message);
    } else {
      AdminNotice.success(context, message);
    }
  }

  /// A rule the admin has run into -- a closed day, an inactive shift, a
  /// full shift. Not a failure, so it does not demand acknowledgement.
  void _showInfo(String message) {
    if (!mounted) return;
    AdminNotice.info(context, message);
  }

  /// A field the admin has to correct before the save can go through.
  /// An error notice rather than an info one, so it waits to be
  /// acknowledged and cannot be dismissed by clicking past it.
  void _showValidation(String message) {
    if (!mounted) return;
    AdminNotice.error(context, message, title: 'Check this before saving');
  }

  /// Strips Dart's "Exception: " prefix so a blocked add/move/remove reads
  /// as the plain explanation the service wrote.
  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  final List<String> days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  late String selectedDay;
  bool isLoading = false;

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<dynamic> amPatients = [];
  List<dynamic> pmPatients = [];

  Map<String, String> shiftTimes = {'AM': 'Time not set', 'PM': 'Time not set'};

  Timer? _dateWatcher;
  DateTime _currentWeekStart = DateTime.now();

  // Presentation only: the section's palette now comes from the shared
  // Admin theme, so it matches the rest of the panel and the Super Admin
  // portal. The names are unchanged, so nothing below had to move.
  static const Color primary = AppTheme.blue1;
  static const Color border = AppTheme.border;
  static const Color textDark = AppTheme.textPrimary;
  static const Color textMuted = AppTheme.textMuted;
  static const Color green = AppTheme.accentGreen;
  static const Color teal = AppTheme.blue1;
  static const Color softBg = AppTheme.surfaceTint;
  static const Color orange = AppTheme.accentOrange;
  static const Color purple = AppTheme.accentPurple;

  @override
  void initState() {
    super.initState();

    _currentWeekStart = getStartOfWeek();
    selectedDay = _getToday();

    loadSelectedDaySchedule();

    _dateWatcher = Timer.periodic(const Duration(minutes: 1), (_) {
      final latestWeekStart = getStartOfWeek();
      final latestToday = _getToday();

      final weekChanged = !_isSameDate(_currentWeekStart, latestWeekStart);
      final dayChanged = selectedDay != latestToday;

      if (weekChanged || dayChanged) {
        setState(() {
          _currentWeekStart = latestWeekStart;
          selectedDay = latestToday;
        });

        loadSelectedDaySchedule();
      }
    });
  }

  @override
  void dispose() {
    _dateWatcher?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TodayScheduleSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.clinicId != widget.clinicId ||
        oldWidget.machineCount != widget.machineCount) {
      loadSelectedDaySchedule();
    }
  }

  String _getToday() {
    final now = DateTime.now();

    if (now.weekday >= DateTime.monday && now.weekday <= DateTime.saturday) {
      return days[now.weekday - 1];
    }

    return 'Monday';
  }

  DateTime getStartOfWeek() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
  }

  DateTime getDateForDay(int index) {
    return getStartOfWeek().add(Duration(days: index));
  }

  String getDateForSelectedDay() {
    final index = days.indexOf(selectedDay);
    final safeIndex = index < 0 ? 0 : index;
    final date = getDateForDay(safeIndex);

    return date.toIso8601String().split('T')[0];
  }

  String getPatientName(dynamic item) {
    return _service.getPatientName(item);
  }

  String _getShiftTime(String shift) {
    return shiftTimes[shift] ?? 'Time not set';
  }

  String _formatTimeValue(dynamic value) {
    if (value == null) return '';

    final raw = value.toString().trim();
    if (raw.isEmpty) return '';

    try {
      if (raw.contains('T')) {
        final parsed = DateTime.parse(raw);
        final hour = parsed.hour;
        final minute = parsed.minute;
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
      }

      final parts = raw.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);

        if (hour != null && minute != null) {
          final period = hour >= 12 ? 'PM' : 'AM';
          final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
          return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
        }
      }
    } catch (_) {
      return raw;
    }

    return raw;
  }

  String _getFirstValue(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }

  String _buildTimeRange(Map<String, dynamic> slot) {
    final directRange = _getFirstValue(slot, [
      'time_range',
      'schedule_time',
      'display_time',
      'slot_time',
    ]);

    if (directRange.isNotEmpty) return directRange;

    final start = _getFirstValue(slot, [
      'start_time',
      'time_start',
      'start',
      'from_time',
    ]);

    final end = _getFirstValue(slot, [
      'end_time',
      'time_end',
      'end',
      'to_time',
    ]);

    final formattedStart = _formatTimeValue(start);
    final formattedEnd = _formatTimeValue(end);

    if (formattedStart.isNotEmpty && formattedEnd.isNotEmpty) {
      return '$formattedStart - $formattedEnd';
    }

    if (formattedStart.isNotEmpty) return formattedStart;
    if (formattedEnd.isNotEmpty) return formattedEnd;

    return 'Time not set';
  }

  String _detectShift(Map<String, dynamic> slot) {
    final rawShift = _getFirstValue(slot, [
      'shift',
      'shift_name',
      'session',
      'period',
      'name',
      'slot_name',
    ]).toUpperCase();

    if (rawShift.contains('AM') || rawShift.contains('MORNING')) return 'AM';
    if (rawShift.contains('PM') || rawShift.contains('AFTERNOON')) return 'PM';

    final start = _getFirstValue(slot, [
      'start_time',
      'time_start',
      'start',
      'from_time',
    ]);

    final parts = start.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts.first) : null;

    if (hour != null) return hour < 12 ? 'AM' : 'PM';

    return '';
  }

  /// Reads shift label/time straight from clinic_shifts -- previously
  /// this only showed a shift's time once at least one daily_schedules
  /// row for that shift existed on some date, which meant a brand-new
  /// clinic or an empty day showed "Time not set" even though the shift
  /// was fully configured.
  Future<void> loadShiftTimes() async {
    try {
      final shifts = await _centerScheduleService.getClinicShifts(
        widget.clinicId,
      );

      if (!mounted) return;

      setState(() {
        shiftTimes = _shiftTimesFrom(shifts);
        _shifts = shifts;
      });
    } catch (e) {
      debugPrint('Load shift times error: $e');
    }
  }

  /// The AM/PM time labels for a shift list. Pure, so a caller that has
  /// already read the shifts doesn't have to read them a second time just
  /// to get the labels.
  Map<String, String> _shiftTimesFrom(List<ClinicShift> shifts) {
    final nextShiftTimes = {'AM': 'Time not set', 'PM': 'Time not set'};

    for (final shift in shifts) {
      final startTime = _formatTimeValue(shift.startTime);
      final endTime = _formatTimeValue(shift.endTime);

      if (startTime.isNotEmpty && endTime.isNotEmpty) {
        nextShiftTimes[shift.shiftCode] = '$startTime - $endTime';
      }
    }

    return nextShiftTimes;
  }

  /// Loads everything the selected day needs.
  ///
  /// Same reads, same results, same order of dependency as before -- only
  /// the *shape* of the trip changed. It used to be a chain of awaits in
  /// which a capacity snapshot was built twice (once inside
  /// generateTodayDefaultSchedule, once inside getDateCapacity) and the
  /// clinic's shifts were read three times over, so switching day cost
  /// roughly fifteen sequential round trips. It is now three phases:
  ///
  ///   1. read the shifts and the capacity snapshot, together;
  ///   2. generate this date's default list -- this WRITES, so it has to
  ///      finish before the date is read back;
  ///   3. read the date back: assignments, recurring labels and this
  ///      date's live capacity, together.
  ///
  /// Nothing is cached between calls: every switch of the day still reads
  /// the schedule fresh from the database, because a stale dialysis list
  /// is not an acceptable trade for a faster one.
  Future<void> loadSelectedDaySchedule() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final selectedDate = getDateForSelectedDay();
      final dayIndex = days.indexOf(selectedDay);
      final date = getDateForDay(dayIndex < 0 ? 0 : dayIndex);

      // --- phase 1: the center's configuration ------------------------
      final setup = await Future.wait<Object>([
        _centerScheduleService.getClinicShifts(widget.clinicId),
        _centerScheduleService.getCapacitySnapshot(widget.clinicId),
      ]);

      final shifts = setup[0] as List<ClinicShift>;
      final snapshot = setup[1] as CenterCapacitySnapshot;

      if (!mounted) return;

      // The shift time labels come from the list just read, so the header
      // stops saying "Time not set" as early as possible.
      setState(() {
        _shifts = shifts;
        shiftTimes = _shiftTimesFrom(shifts);
      });

      // --- phase 2: populate this date's default list ------------------
      // Additive and idempotent, and never touches a daily_schedules row
      // that already exists for a patient on this date (manually added or
      // previously generated).
      await _centerScheduleService.generateTodayDefaultSchedule(
        clinicId: widget.clinicId,
        date: date,
        snapshot: snapshot,
      );

      // --- phase 3: read the date back ---------------------------------
      final loaded = await Future.wait<Object>([
        _service.getDailyAssignments(
          clinicId: widget.clinicId,
          scheduleDate: selectedDate,
        ),
        _centerScheduleService.getRecurringPatientShiftsForDay(
          clinicId: widget.clinicId,
          day: selectedDay,
          shifts: shifts,
        ),
        // Capacity for this exact date, not the recurring week -- so a
        // removal frees a seat and an addition takes one straight away.
        // The snapshot only supplies the configured capacity; the
        // occupancy figure is still read fresh from daily_schedules.
        _centerScheduleService.getDateCapacity(
          clinicId: widget.clinicId,
          date: date,
          snapshot: snapshot,
        ),
      ]);

      final data = loaded[0] as List<dynamic>;
      final recurringShifts = loaded[1] as Map<String, String>;
      final dateCapacity = loaded[2] as DayCapacity;

      if (!mounted) return;

      setState(() {
        amPatients = data.where((item) => item['shift'] == 'AM').toList();
        pmPatients = data.where((item) => item['shift'] == 'PM').toList();
        _recurringShifts = recurringShifts;
        _dateCapacity = dateCapacity;
      });
    } catch (e) {
      debugPrint('Load schedule error: $e');

      if (!mounted) return;

      _showMessage(
        'The schedule for $selectedDay could not be loaded. $e',
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  /// Colour + wording for why a candidate is offered on this date.
  static (String, Color, IconData) _sourceBadge(DateCandidateSource source) {
    switch (source) {
      case DateCandidateSource.rescheduled:
        return ('Rescheduled', purple, Icons.swap_horiz_rounded);
      case DateCandidateSource.removedToday:
        return ('Removed', orange, Icons.undo_rounded);
      case DateCandidateSource.recurring:
        return ('Recurring', primary, Icons.event_repeat_rounded);
    }
  }

  Widget _candidateBadge(DateCandidateSource source) {
    final (label, color, icon) = _sourceBadge(source);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Why this patient can be added today, in one short line under their
  /// name -- so an approved reschedule is never a silent appearance.
  String _candidateSubtitle(DateScheduleCandidate candidate) {
    switch (candidate.source) {
      case DateCandidateSource.rescheduled:
        final from = candidate.rescheduleOriginalDate;
        final to = candidate.rescheduleNewDate;
        final range = from == null || to == null
            ? ''
            : '  •  ${DateFormat('EEE, MMM d').format(from)} → '
                  '${DateFormat('EEE, MMM d').format(to)}';
        return 'Available from an approved reschedule request$range';

      case DateCandidateSource.removedToday:
        final was = candidate.currentShiftCode;
        return was == null
            ? 'Taken off this day earlier — adding them back affects this '
                  'day only'
            : 'Taken off the $was shift earlier — adding them here affects '
                  'this day only';

      case DateCandidateSource.recurring:
        final code = candidate.defaultShiftCode;
        return code == null
            ? 'From their recurring weekly schedule'
            : 'Recurring $code patient on $selectedDay';
    }
  }

  Future<void> openAddModal(String shift) async {
    try {
      final selectedDate = getDateForSelectedDay();
      final dayIndex = days.indexOf(selectedDay);
      final date = getDateForDay(dayIndex < 0 ? 0 : dayIndex);

      // The capacity check and the candidate list are independent reads,
      // so the modal waits for one round trip rather than two. Both are
      // read fresh -- the capacity that gates the add is never taken from
      // the copy this section already has on screen.
      final opening = await Future.wait<Object>([
        _centerScheduleService.getDateCapacity(
          clinicId: widget.clinicId,
          date: date,
        ),
        // Candidates are resolved for the DATE, not just the weekday:
        // recurring patients who aren't on the list yet, anyone an admin
        // removed from this date earlier, and anyone an approved
        // reschedule request grants this date. Nobody already live on
        // this date is offered -- they can only be moved.
        _centerScheduleService.getDateCandidates(
          clinicId: widget.clinicId,
          date: date,
          shifts: _shifts.isEmpty ? null : _shifts,
        ),
      ]);

      final dayCapacity = opening[0] as DayCapacity;
      final candidates = opening[1] as List<DateScheduleCandidate>;

      if (!mounted) return;

      if (!dayCapacity.isOperating) {
        _showInfo('The center does not operate on $selectedDay.');
        return;
      }

      ShiftCapacity? shiftCapacity;
      for (final entry in dayCapacity.shifts) {
        if (entry.shift.shiftCode == shift) shiftCapacity = entry;
      }

      if (shiftCapacity == null || !shiftCapacity.shift.isActive) {
        _showInfo('The $shift shift is not active at this center.');
        return;
      }

      if (shiftCapacity.isFull) {
        _showInfo(
          'The $shift shift is full '
          '(${shiftCapacity.scheduled}/${shiftCapacity.effectiveCapacity}). '
          'Remove a patient from this shift before adding another.',
        );
        return;
      }

      final capacityLine =
          '${shiftCapacity.scheduled}/${shiftCapacity.effectiveCapacity} '
          'filled · ${shiftCapacity.available} vacant';

      await showAdminDialog(
        context: context,
        builder: (dialogContext) {
          bool dialogIsAdding = false;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(24),
                child: Container(
                  width: 540,
                  constraints: const BoxConstraints(maxHeight: 580),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rXl),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.shadowMd,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: green,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add Patient to $shift Shift',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                      color: textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$selectedDay • $selectedDate • '
                                    '$capacityLine',
                                    style: const TextStyle(
                                      color: textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: border),
                      Flexible(
                        child: SizedBox(
                          height: 430,
                          child: candidates.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Everyone scheduled for this day is '
                                      'already on the list.\n\nPatients also '
                                      'appear here once they are removed from '
                                      'this day, or once a reschedule request '
                                      'for this date is approved.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: textMuted,
                                        fontWeight: FontWeight.w700,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: candidates.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final candidate = candidates[index];
                                    final patientName = candidate.patientName;

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: dialogIsAdding
                                          ? null
                                          : () async {
                                              setDialogState(() {
                                                dialogIsAdding = true;
                                              });

                                              try {
                                                await _centerScheduleService
                                                    .addPatientToDate(
                                                      clinicId: widget.clinicId,
                                                      date: date,
                                                      shiftCode: shift,
                                                      patientId:
                                                          candidate.patientId,
                                                      weeklyScheduleId:
                                                          candidate
                                                              .weeklyScheduleId,
                                                      rescheduleRequestId:
                                                          candidate
                                                              .rescheduleRequestId,
                                                    );

                                                if (!mounted) return;

                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();

                                                await loadSelectedDaySchedule();
                                                widget.onScheduleChanged
                                                    ?.call();

                                                if (!mounted) return;

                                                _showMessage(
                                                  '$patientName added to the '
                                                  '$shift shift for '
                                                  '$selectedDay.',
                                                );
                                              } catch (e) {
                                                debugPrint(
                                                  'Add patient error: $e',
                                                );

                                                if (!mounted) return;

                                                setDialogState(() {
                                                  dialogIsAdding = false;
                                                });

                                                _showMessage(
                                                  _friendlyError(e),
                                                  isError: true,
                                                );
                                              }
                                            },
                                      child: Container(
                                        padding: const EdgeInsets.all(13),
                                        decoration: BoxDecoration(
                                          color: softBg,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(color: border),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: const Color(
                                                0xFFE0F2FE,
                                              ),
                                              child: Text(
                                                patientName.trim().isEmpty
                                                    ? 'P'
                                                    : patientName
                                                          .trim()[0]
                                                          .toUpperCase(),
                                                style: const TextStyle(
                                                  color: AppTheme.blue1,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 11),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          patientName,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color: textDark,
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 7),
                                                      _candidateBadge(
                                                        candidate.source,
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    _candidateSubtitle(
                                                      candidate,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 10.5,
                                                      color: textMuted,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            dialogIsAdding
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons.chevron_right_rounded,
                                                    color: AppTheme.iconMuted,
                                                  ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Open modal error: $e');

      if (!mounted) return;
      _showMessage(_friendlyError(e), isError: true);
    }
  }

  /// The small tinted explanation that sits under a confirmation's
  /// question - used wherever an action is deliberately scoped to one day.
  static Widget _noticeBox({required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.blue1),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Takes the patient off THIS DATE only.
  ///
  /// This cancels the date's daily_schedules occurrence. It does not touch
  /// patient_schedule_days, weekly_schedules or patients.preferred_shift,
  /// so the patient's recurring Mon/Wed/Fri (or whatever they are on)
  /// stays exactly as it was and they reappear automatically on their next
  /// scheduled day.
  Future<void> removePatient(dynamic item) async {
    final patientName = getPatientName(item);
    final shift = item['shift']?.toString() ?? '';

    final confirmed = await showAdminConfirm(
      context: context,
      title: 'Remove from this day',
      icon: Icons.event_busy_rounded,
      destructive: true,
      confirmLabel: 'Remove from this day',
      message:
          'Remove $patientName from the $shift shift on $selectedDay '
          '(${getDateForSelectedDay()})?',
      detail: _noticeBox(
        icon: Icons.event_repeat_rounded,
        text:
            'This affects this day only. Their recurring weekly schedule is '
            'not changed, and they will appear again on their next '
            'scheduled day.',
      ),
    );

    if (confirmed != true) return;

    try {
      await _centerScheduleService.cancelDateOccurrence(
        dailyScheduleId: item['id'].toString(),
        clinicId: widget.clinicId,
        reason: 'Removed from the $selectedDay $shift list by the center admin',
      );

      await loadSelectedDaySchedule();
      widget.onScheduleChanged?.call();

      if (!mounted) return;

      _showMessage(
        '$patientName removed from the $shift shift for $selectedDay only. '
        'Their recurring schedule is unchanged.',
      );
    } catch (e) {
      debugPrint('Remove patient error: $e');

      if (!mounted) return;
      _showMessage(_friendlyError(e), isError: true);
    }
  }

  /// Moves a patient to the other shift FOR THIS DATE ONLY, by updating
  /// the single occurrence row they already have -- so no duplicate
  /// session can appear, and their recurring default shift
  /// (patient_schedule_days.shift_id) is untouched.
  Future<void> movePatient(dynamic item, String fromShift) async {
    final toShift = fromShift == 'AM' ? 'PM' : 'AM';
    final patientName = getPatientName(item);
    final dayIndex = days.indexOf(selectedDay);
    final date = getDateForDay(dayIndex < 0 ? 0 : dayIndex);

    final confirmed = await showAdminConfirm(
      context: context,
      title: 'Move to $toShift shift',
      icon: Icons.swap_horiz_rounded,
      confirmLabel: 'Move to $toShift',
      message:
          'Move $patientName from the $fromShift shift to the $toShift '
          'shift on $selectedDay?',
      detail: _noticeBox(
        icon: Icons.event_repeat_rounded,
        text:
            'This applies to this day only \u2014 their normal default shift '
            'stays $fromShift.',
      ),
    );

    if (confirmed != true) return;

    try {
      await _centerScheduleService.moveOccurrenceToShift(
        dailyScheduleId: item['id'].toString(),
        clinicId: widget.clinicId,
        date: date,
        toShiftCode: toShift,
      );

      await loadSelectedDaySchedule();
      widget.onScheduleChanged?.call();

      if (!mounted) return;

      _showMessage(
        '$patientName moved to the $toShift shift for $selectedDay only.',
      );
    } catch (e) {
      debugPrint('Move patient error: $e');

      if (!mounted) return;
      _showMessage(_friendlyError(e), isError: true);
    }
  }

  Future<void> openSessionModal(dynamic item, String shift) async {
    final dailyScheduleId = item['id']?.toString() ?? '';
    final patientName = getPatientName(item);

    if (!mounted) return;

    bool isCompleted = _service.isSessionCompleted(item);
    bool beforeWeightSaved = item['before_weight'] != null;
    bool beforeBpSaved =
        item['before_systolic'] != null && item['before_diastolic'] != null;
    bool afterWeightSaved = item['after_weight'] != null;

    final beforeWeightController = TextEditingController(
      text: item['before_weight']?.toString() ?? '',
    );
    final beforeSystolicController = TextEditingController(
      text: item['before_systolic']?.toString() ?? '',
    );
    final beforeDiastolicController = TextEditingController(
      text: item['before_diastolic']?.toString() ?? '',
    );
    final afterWeightController = TextEditingController(
      text: item['after_weight']?.toString() ?? '',
    );
    final durationHoursController = TextEditingController(
      text: item['duration_hours']?.toString() ?? '',
    );
    final durationMinutesController = TextEditingController(
      text: item['duration_minutes']?.toString() ?? '',
    );

    bool isSavingBefore = false;
    bool isSavingAfter = false;
    bool isCompleting = false;

    await showAdminDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> saveBefore() async {
              // Each value is checked on its own so the admin is told
              // which reading is wrong, instead of one message covering
              // three fields. The blood pressure pair is checked
              // together: a systolic below its own diastolic is a
              // transposed entry.
              final beforeError = AdminValidators.firstError([
                () => AdminValidators.weightKg(
                  beforeWeightController.text,
                  label: 'weight before dialysis',
                ),
                () => AdminValidators.bloodPressure(
                  systolic: beforeSystolicController.text,
                  diastolic: beforeDiastolicController.text,
                  systolicLabel: 'before-dialysis systolic reading',
                  diastolicLabel: 'before-dialysis diastolic reading',
                ),
              ]);

              if (beforeError != null) {
                _showValidation(beforeError);
                return;
              }

              final weight = double.parse(beforeWeightController.text.trim());
              final systolic = int.parse(beforeSystolicController.text.trim());
              final diastolic = int.parse(
                beforeDiastolicController.text.trim(),
              );

              setModalState(() => isSavingBefore = true);

              try {
                await _service.saveBeforeDialysisData(
                  dailyScheduleId: dailyScheduleId,
                  clinicId: widget.clinicId,
                  beforeWeight: weight,
                  beforeSystolic: systolic,
                  beforeDiastolic: diastolic,
                );

                setModalState(() {
                  beforeWeightSaved = true;
                  beforeBpSaved = true;
                  isSavingBefore = false;
                });

                if (!mounted) return;
                await _showFeedbackDialog(
                  ctx: dialogContext,
                  success: true,
                  message: 'Before-dialysis data saved.',
                );
              } catch (e) {
                debugPrint('Save before-dialysis data error: $e');
                setModalState(() => isSavingBefore = false);
                if (!mounted) return;
                await _showFeedbackDialog(
                  ctx: dialogContext,
                  success: false,
                  message: 'Failed to save before-dialysis data: $e',
                );
              }
            }

            Future<void> completeSession() async {
              final confirmed = await showAdminDialog<bool>(
                context: dialogContext,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('Complete Dialysis Session'),
                  content: Text(
                    'Confirm that $patientName has completed their dialysis session for the $shift shift?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(confirmContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(confirmContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Confirm Completed'),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return;

              setModalState(() => isCompleting = true);

              try {
                await _service.markSessionCompleted(
                  dailyScheduleId: dailyScheduleId,
                  clinicId: widget.clinicId,
                );

                setModalState(() {
                  isCompleted = true;
                  isCompleting = false;
                });

                if (!mounted) return;
                await _showFeedbackDialog(
                  ctx: dialogContext,
                  success: true,
                  message: '$patientName\'s dialysis session marked completed.',
                );
              } catch (e) {
                debugPrint('Complete dialysis session error: $e');
                setModalState(() => isCompleting = false);
                if (!mounted) return;
                await _showFeedbackDialog(
                  ctx: dialogContext,
                  success: false,
                  message: 'Failed to update session status: $e',
                );
              }
            }

            Future<void> saveAfter() async {
              // The 0-8h / 0-59m bounds are the CHECK constraints
              // daily_schedules already carries (see
              // supabase/dialysis_session_duration.sql), so a value the
              // form rejects is exactly one the database would reject.
              final afterError = AdminValidators.firstError([
                () => AdminValidators.weightKg(
                  afterWeightController.text,
                  label: 'weight after dialysis',
                ),
                () => AdminValidators.wholeNumber(
                  durationHoursController.text,
                  label: 'session duration in hours',
                  min: 0,
                  max: 8,
                ),
                () => AdminValidators.wholeNumber(
                  durationMinutesController.text,
                  label: 'session duration in minutes',
                  min: 0,
                  max: 59,
                ),
              ]);

              if (afterError != null) {
                _showValidation(afterError);
                return;
              }

              final weight = double.parse(afterWeightController.text.trim());
              final hours = int.parse(durationHoursController.text.trim());
              final minutes = int.parse(durationMinutesController.text.trim());

              if (hours == 0 && minutes == 0) {
                _showValidation(
                  'The session duration cannot be zero. Enter how long the '
                  'session actually ran.',
                );
                return;
              }

              setModalState(() => isSavingAfter = true);

              try {
                await _service.saveAfterDialysisData(
                  dailyScheduleId: dailyScheduleId,
                  clinicId: widget.clinicId,
                  afterWeight: weight,
                  durationHours: hours,
                  durationMinutes: minutes,
                );

                setModalState(() {
                  afterWeightSaved = true;
                  isSavingAfter = false;
                });

                if (!mounted) return;
                await _showFeedbackDialog(
                  ctx: dialogContext,
                  success: true,
                  message: "$patientName's after-dialysis data saved.",
                );

                if (!mounted) return;
                Navigator.of(dialogContext).pop();
              } catch (e) {
                debugPrint('Save after-dialysis data error: $e');
                setModalState(() => isSavingAfter = false);
                if (!mounted) return;
                await _showFeedbackDialog(
                  ctx: dialogContext,
                  success: false,
                  message: 'Failed to save after-dialysis data: $e',
                );
              }
            }

            final canComplete =
                beforeWeightSaved && beforeBpSaved && !isCompleted;
            final beforeEnabled = !isCompleted;
            final afterEnabled = isCompleted && !afterWeightSaved;
            final isFullyCompleted = isCompleted && afterWeightSaved;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 560,
                constraints: const BoxConstraints(maxHeight: 680),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.rXl),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.medical_services_rounded,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patientName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: textDark,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$shift Shift • $selectedDay',
                                  style: const TextStyle(
                                    color: textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _statusChip(isCompleted),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: border),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sessionSectionCard(
                              title: 'Before Dialysis',
                              icon: Icons.play_circle_fill_rounded,
                              accent: teal,
                              enabled: beforeEnabled,
                              children: [
                                _sessionInputField(
                                  label: 'Weight Before Dialysis (kg)',
                                  controller: beforeWeightController,
                                  icon: Icons.scale_rounded,
                                  enabled: beforeEnabled,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _sessionInputField(
                                        label: 'Systolic',
                                        controller: beforeSystolicController,
                                        icon: Icons.favorite_rounded,
                                        enabled: beforeEnabled,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _sessionInputField(
                                        label: 'Diastolic',
                                        controller: beforeDiastolicController,
                                        icon: Icons.favorite_border_rounded,
                                        enabled: beforeEnabled,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (beforeEnabled)
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: isSavingBefore
                                          ? null
                                          : saveBefore,
                                      icon: isSavingBefore
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.save_rounded,
                                              size: 16,
                                            ),
                                      label: Text(
                                        isSavingBefore
                                            ? 'Saving...'
                                            : 'Save Before-Dialysis Data',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: teal,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  )
                                else
                                  _lockedNote(
                                    'Before-dialysis data is locked once the session is completed.',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: (!canComplete || isCompleting)
                                    ? null
                                    : completeSession,
                                icon: isCompleting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        isCompleted
                                            ? Icons.check_circle_rounded
                                            : Icons.task_alt_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  isCompleted
                                      ? 'Dialysis Session Completed'
                                      : (canComplete
                                            ? 'Mark Dialysis Session Completed'
                                            : 'Enter Before-Dialysis Data First'),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isCompleted
                                      ? AppTheme.borderStrong
                                      : green,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(
                                    0xFFCBD5E1,
                                  ),
                                  disabledForegroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _sessionSectionCard(
                              title: 'After Dialysis',
                              icon: Icons.flag_circle_rounded,
                              accent: isFullyCompleted
                                  ? green
                                  : (isCompleted
                                        ? primary
                                        : AppTheme.iconMuted),
                              enabled: isCompleted,
                              children: [
                                _sessionInputField(
                                  label: 'Weight After Dialysis (kg)',
                                  controller: afterWeightController,
                                  icon: Icons.monitor_weight_rounded,
                                  enabled: afterEnabled,
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.timer_rounded,
                                      size: 14,
                                      color: afterEnabled
                                          ? primary
                                          : AppTheme.iconMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Session Duration',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: afterEnabled
                                            ? textDark
                                            : textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _sessionInputField(
                                        label: 'Hours (0-8)',
                                        controller: durationHoursController,
                                        icon: Icons.hourglass_bottom_rounded,
                                        enabled: afterEnabled,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(1),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _sessionInputField(
                                        label: 'Minutes (0-59)',
                                        controller: durationMinutesController,
                                        icon: Icons.timer_rounded,
                                        enabled: afterEnabled,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(2),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (afterEnabled)
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: isSavingAfter
                                          ? null
                                          : saveAfter,
                                      icon: isSavingAfter
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.save_rounded,
                                              size: 16,
                                            ),
                                      label: Text(
                                        isSavingAfter
                                            ? 'Saving...'
                                            : 'Save After-Dialysis Data',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primary,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: const Color(
                                          0xFFCBD5E1,
                                        ),
                                        disabledForegroundColor: Colors.white,
                                      ),
                                    ),
                                  )
                                else if (isFullyCompleted)
                                  _lockedNote(
                                    'Session record locked — dialysis session fully documented.',
                                    positive: true,
                                  )
                                else
                                  _lockedNote(
                                    'Complete the dialysis session to unlock after-dialysis inputs.',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await loadSelectedDaySchedule();
  }

  /// Feedback from inside the session modal.
  ///
  /// This used to be a small dialog of its own, pushed on top of the
  /// session modal with its own three-second timer and its own styling --
  /// a second, parallel notification system. It now delegates to the one
  /// [AdminNotice] system, which already layers above the modal, so the
  /// timings and the look match the rest of the panel.
  ///
  /// [ctx] is kept in the signature because every caller passes the
  /// modal's own context, which is the one still mounted at that point.
  Future<void> _showFeedbackDialog({
    required BuildContext ctx,
    required bool success,
    required String message,
  }) {
    return success
        ? AdminNotice.success(ctx, message)
        : AdminNotice.error(ctx, message);
  }

  Widget _lockedNote(String message, {bool positive = false}) {
    return Row(
      children: [
        Icon(
          positive ? Icons.verified_rounded : Icons.lock_rounded,
          size: 14,
          color: positive ? green : textMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 11,
              color: positive ? green : textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(bool completed) {
    final color = completed ? green : orange;

    return Container(
      margin: const EdgeInsets.only(left: 8, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        completed ? 'Completed' : 'Pending',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _sessionSectionCard({
    required String title,
    required IconData icon,
    required Color accent,
    required bool enabled,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: enabled ? textDark : textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _sessionInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool enabled,
    TextInputType keyboardType = const TextInputType.numberWithOptions(
      decimal: true,
    ),
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(
        color: enabled ? textDark : textMuted,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          size: 18,
          color: enabled ? primary : AppTheme.iconMuted,
        ),
        filled: true,
        fillColor: enabled ? softBg : AppTheme.surfaceTint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
    );
  }

  Widget buildDayTabs() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(days.length, (index) {
              final day = days[index];
              final date = getDateForDay(index);
              final isSelected = selectedDay == day;
              final double itemWidth = constraints.maxWidth >= 650
                  ? (constraints.maxWidth - 50) / 6
                  : 112;

              return _DayTab(
                onTap: () async {
                  if (isLoading) return;
                  setState(() => selectedDay = day);
                  await loadSelectedDaySchedule();
                },
                child: AnimatedContainer(
                  duration: AppTheme.motion(context, AppTheme.fast),
                  curve: AppTheme.ease,
                  width: itemWidth,
                  margin: EdgeInsets.only(
                    right: index == days.length - 1 ? 0 : 10,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: isSelected ? teal : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSelected ? teal : border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isSelected ? 0.08 : 0.03,
                        ),
                        blurRadius: 9,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        day,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: isSelected ? Colors.white : textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget buildShiftTable({
    required String title,
    required String shift,
    required List<dynamic> patients,
  }) {
    final int capacity = _capacityFor(shift);
    final bool isFull = patients.length >= capacity;

    // Never hide a scheduled patient: if a shift is somehow over its
    // configured capacity, show every one of them rather than cutting the
    // list at the capacity figure.
    final int cappedRows = capacity > 12 ? 12 : capacity;
    final int rowsToShow = patients.length > cappedRows
        ? patients.length
        : cappedRows;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          '${patients.length}/$capacity filled · '
                          '${capacity - patients.length < 0 ? 0 : capacity - patients.length} vacant',
                          style: const TextStyle(
                            fontSize: 11,
                            color: textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceTint,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 12,
                                  color: textMuted,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _getShiftTime(shift),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: textMuted,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: isFull || isLoading
                    ? null
                    : () => openAddModal(shift),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.borderStrong,
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Table(
              border: TableBorder.all(color: border, width: 0.8),
              columnWidths: const {
                0: FixedColumnWidth(34),
                1: FlexColumnWidth(),
                2: FixedColumnWidth(62),
              },
              children: List.generate(rowsToShow, (index) {
                final patient = index < patients.length
                    ? patients[index]
                    : null;

                return TableRow(
                  decoration: BoxDecoration(
                    color: index.isEven ? AppTheme.surface : Colors.white,
                  ),
                  children: [
                    numberCell('${index + 1}'),
                    patientCell(patient, shift),
                    tableActionCell(patient, shift),
                  ],
                );
              }),
            ),
          ),
          if (capacity > rowsToShow) ...[
            const SizedBox(height: 10),
            Text(
              '+ ${capacity - rowsToShow} more machine slots',
              style: const TextStyle(
                color: textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget numberCell(String text) {
    return Container(
      height: 34,
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: textMuted,
        ),
      ),
    );
  }

  Widget patientCell(dynamic patient, String shift) {
    final bool isEmpty = patient == null;
    final String text = isEmpty ? 'Available slot' : getPatientName(patient);

    // A session counts as recurring when the patient's saved schedule
    // puts them on this day and shift; anything else is a change made for
    // this date only -- either an approved reschedule request (the row
    // carries its id) or a manual addition/move by the admin.
    final patientId = isEmpty ? null : patient['patient_id']?.toString();
    final bool isRecurring =
        patientId != null && _recurringShifts[patientId] == shift;
    final bool isRescheduled =
        !isEmpty && patient['reschedule_request_id'] != null;

    return InkWell(
      onTap: isEmpty ? null : () => openSessionModal(patient, shift),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w800,
                  color: isEmpty ? AppTheme.iconMuted : textDark,
                ),
              ),
            ),
            if (!isEmpty)
              _sourceChip(
                isRecurring: isRecurring,
                isRescheduled: isRescheduled,
              ),
            if (!isEmpty) _statusChip(_service.isSessionCompleted(patient)),
          ],
        ),
      ),
    );
  }

  Widget _sourceChip({required bool isRecurring, required bool isRescheduled}) {
    final Color color;
    final String label;
    final String tooltip;

    if (isRescheduled) {
      color = purple;
      label = 'Rescheduled';
      tooltip =
          'Here for this date only, from an approved reschedule request. '
          'Their recurring weekly schedule is unchanged.';
    } else if (isRecurring) {
      color = primary;
      label = 'Recurring';
      tooltip = "From the patient's recurring weekly schedule";
    } else {
      color = orange;
      label = 'Added';
      tooltip = 'Added or moved by an admin for this date only';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget tableActionCell(dynamic patient, String shift) {
    if (patient == null) {
      return const SizedBox(height: 34);
    }

    final isCompleted = _service.isSessionCompleted(patient);
    final otherShift = shift == 'AM' ? 'PM' : 'AM';

    return Container(
      height: 34,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: isCompleted
                ? 'A completed session cannot be moved'
                : 'Move to $otherShift shift (this day only)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 26),
            icon: Icon(
              Icons.swap_horiz_rounded,
              size: 16,
              color: isCompleted ? AppTheme.borderStrong : primary,
            ),
            onPressed: isCompleted ? null : () => movePatient(patient, shift),
          ),
          IconButton(
            tooltip: isCompleted
                ? 'A completed session cannot be removed'
                : 'Remove from this day only',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 26),
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: isCompleted ? AppTheme.borderStrong : AppTheme.danger,
            ),
            onPressed: isCompleted ? null : () => removePatient(patient),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip() {
    final totalAssigned = amPatients.length + pmPatients.length;

    // Same date-level capacity the shift cards use, so the strip can
    // never disagree with them.
    final dateCapacity = _dateCapacity;
    final totalCapacity = dateCapacity != null
        ? dateCapacity.capacity
        : (_shifts.isEmpty
              ? widget.machineCount * 2
              : _shifts.fold<int>(0, (sum, s) => sum + s.capacity));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          _summaryItem(
            'Selected Day',
            selectedDay,
            Icons.today_rounded,
            primary,
          ),
          const SizedBox(width: 12),
          _summaryItem(
            'AM Patients',
            amPatients.length.toString(),
            Icons.wb_sunny_rounded,
            green,
          ),
          const SizedBox(width: 12),
          _summaryItem(
            'PM Patients',
            pmPatients.length.toString(),
            Icons.nights_stay_rounded,
            AppTheme.accentPurple,
          ),
          const SizedBox(width: 12),
          _summaryItem(
            'Capacity Used',
            '$totalAssigned/$totalCapacity',
            Icons.event_seat_rounded,
            AppTheme.accentOrange,
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: primary,
              ),
              const SizedBox(width: 6),
              Text(
                DateFormat('MMMM yyyy').format(_currentWeekStart),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: textDark,
                ),
              ),
            ],
          ),
        ),
        buildDayTabs(),
        const SizedBox(height: 14),
        _buildSummaryStrip(),
        const SizedBox(height: 14),
        if (isLoading)
          // A skeleton in the shape of the two shift tables, rather than
          // a bare spinner: the section keeps its size, so the rest of the
          // dashboard doesn't jump while a day loads. Deliberately shows
          // no names or numbers - a loading state must never be mistaken
          // for schedule data.
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 740) {
                return const Column(
                  children: [
                    _ShiftTableSkeleton(title: 'AM Shift'),
                    SizedBox(height: 12),
                    _ShiftTableSkeleton(title: 'PM Shift'),
                  ],
                );
              }

              return const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _ShiftTableSkeleton(title: 'AM Shift')),
                  SizedBox(width: 14),
                  Expanded(child: _ShiftTableSkeleton(title: 'PM Shift')),
                ],
              );
            },
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 740) {
                return Column(
                  children: [
                    buildShiftTable(
                      title: 'AM Shift',
                      shift: 'AM',
                      patients: amPatients,
                    ),
                    const SizedBox(height: 12),
                    buildShiftTable(
                      title: 'PM Shift',
                      shift: 'PM',
                      patients: pmPatients,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: buildShiftTable(
                      title: 'AM Shift',
                      shift: 'AM',
                      patients: amPatients,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: buildShiftTable(
                      title: 'PM Shift',
                      shift: 'PM',
                      patients: pmPatients,
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// A day tab. Separate from the table so hovering one doesn't rebuild the
/// whole section.
class _DayTab extends StatefulWidget {
  final Future<void> Function() onTap;
  final Widget child;

  const _DayTab({required this.onTap, required this.child});

  @override
  State<_DayTab> createState() => _DayTabState();
}

class _DayTabState extends State<_DayTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onTap(),
        child: AnimatedOpacity(
          duration: AppTheme.motion(context, AppTheme.fast),
          opacity: _hovered ? 0.88 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The placeholder shown in a shift table's place while the day loads.
class _ShiftTableSkeleton extends StatelessWidget {
  final String title;

  const _ShiftTableSkeleton({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AdminSkeleton(width: 170, height: 10),
          const SizedBox(height: 16),
          for (var i = 0; i < 6; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: const [
                AdminSkeleton(width: 26, height: 26, radius: 13),
                SizedBox(width: 10),
                Expanded(child: AdminSkeleton(height: 11)),
                SizedBox(width: 10),
                AdminSkeleton(width: 54, height: 11),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
