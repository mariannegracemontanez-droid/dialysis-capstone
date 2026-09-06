import 'package:admin_panel/services/schedule_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class TodayScheduleSection extends StatefulWidget {
  final String clinicId;
  final int machineCount;

  const TodayScheduleSection({
    super.key,
    required this.clinicId,
    required this.machineCount,
  });

  @override
  State<TodayScheduleSection> createState() => _TodayScheduleSectionState();
}

class _TodayScheduleSectionState extends State<TodayScheduleSection> {
  final ScheduleService _service = ScheduleService();
  final SupabaseClient _supabase = Supabase.instance.client;

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

  static const Color primary = Color(0xFF245C78);
  static const Color border = Color(0xFFE1E8EF);
  static const Color textDark = Color(0xFF1F2D3D);
  static const Color textMuted = Color(0xFF6B7A8C);
  static const Color green = Color(0xFF10B981);
  static const Color teal = Color(0xFF70C8BF);
  static const Color softBg = Color(0xFFF8FAFC);
  static const Color orange = Color(0xFFF59E0B);

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

  Future<void> loadShiftTimes() async {
    try {
      final response = await _supabase
          .from('daily_schedules')
          .select('shift, start_time, end_time')
          .eq('clinic_id', widget.clinicId);

      final nextShiftTimes = {'AM': 'Time not set', 'PM': 'Time not set'};

      for (final slot in response) {
        final shift = slot['shift']?.toString().toUpperCase();

        if (shift == 'AM' || shift == 'PM') {
          final startTime = _formatTimeValue(slot['start_time']);
          final endTime = _formatTimeValue(slot['end_time']);

          if (startTime.isNotEmpty && endTime.isNotEmpty) {
            nextShiftTimes[shift!] = '$startTime - $endTime';
          }
        }
      }

      if (!mounted) return;

      setState(() {
        shiftTimes = nextShiftTimes;
      });
    } catch (e) {
      debugPrint('Load shift times error: $e');
    }
  }

  Future<void> loadSelectedDaySchedule() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final selectedDate = getDateForSelectedDay();

      await loadShiftTimes();

      final data = await _service.getDailyAssignments(
        clinicId: widget.clinicId,
        scheduleDate: selectedDate,
      );

      if (!mounted) return;

      setState(() {
        amPatients = data.where((item) => item['shift'] == 'AM').toList();
        pmPatients = data.where((item) => item['shift'] == 'PM').toList();
      });
    } catch (e) {
      debugPrint('Load schedule error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load schedule: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> openAddModal(String shift) async {
    try {
      final selectedDate = getDateForSelectedDay();

      final patients = await _service.getEligiblePatients(
        widget.clinicId,
        selectedDay,
      );

      final latestAssignments = await _service.getDailyAssignments(
        clinicId: widget.clinicId,
        scheduleDate: selectedDate,
      );

      final assignedPatientIds = latestAssignments
          .map((item) => item['patient_id']?.toString())
          .where((id) => id != null)
          .toSet();

      final availablePatients = patients.where((item) {
        return !assignedPatientIds.contains(item['patient_id']?.toString());
      }).toList();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) {
          bool dialogIsAdding = false;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(24),
                child: Container(
                  width: 520,
                  constraints: const BoxConstraints(maxHeight: 560),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.16),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
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
                                color: green.withOpacity(0.12),
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
                                    '$selectedDay • $selectedDate',
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
                          child: availablePatients.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'No available patients scheduled for this day.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: textMuted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: availablePatients.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final item = availablePatients[index];
                                    final patientName = getPatientName(item);

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: dialogIsAdding
                                          ? null
                                          : () async {
                                              setDialogState(() {
                                                dialogIsAdding = true;
                                              });

                                              try {
                                                await _service
                                                    .assignDailySchedule(
                                                      weeklyScheduleId:
                                                          item['id'],
                                                      patientId:
                                                          item['patient_id'],
                                                      clinicId: widget.clinicId,
                                                      shift: shift,
                                                      scheduleDate:
                                                          selectedDate,
                                                    );

                                                if (!mounted) return;

                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                                await loadSelectedDaySchedule();

                                                if (!mounted) return;

                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '$patientName added to $shift Shift.',
                                                    ),
                                                    backgroundColor: green,
                                                  ),
                                                );
                                              } catch (e) {
                                                debugPrint(
                                                  'Add patient error: $e',
                                                );

                                                if (!mounted) return;

                                                setDialogState(() {
                                                  dialogIsAdding = false;
                                                });

                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Failed to add patient: $e',
                                                    ),
                                                    backgroundColor: Colors.red,
                                                  ),
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
                                                  color: Color(0xFF0369A1),
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 11),
                                            Expanded(
                                              child: Text(
                                                patientName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: textDark,
                                                ),
                                              ),
                                            ),
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
                                                    color: Color(0xFF94A3B8),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading patients: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> removePatient(dynamic item) async {
    try {
      await _service.deleteDailySchedule(
        dailyScheduleId: item['id'].toString(),
        clinicId: widget.clinicId,
      );

      await loadSelectedDaySchedule();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient removed from schedule.'),
          backgroundColor: green,
        ),
      );
    } catch (e) {
      debugPrint('Remove patient error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove patient: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> saveBefore() async {
              final weight = double.tryParse(
                beforeWeightController.text.trim(),
              );
              final systolic = int.tryParse(
                beforeSystolicController.text.trim(),
              );
              final diastolic = int.tryParse(
                beforeDiastolicController.text.trim(),
              );

              if (weight == null ||
                  weight <= 0 ||
                  systolic == null ||
                  diastolic == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please enter a valid before-dialysis weight and blood pressure.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

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
              final confirmed = await showDialog<bool>(
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
                  message:
                      '$patientName\'s dialysis session marked completed.',
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
              final weight = double.tryParse(
                afterWeightController.text.trim(),
              );
              final hours = int.tryParse(durationHoursController.text.trim());
              final minutes = int.tryParse(
                durationMinutesController.text.trim(),
              );

              if (weight == null || weight <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please enter a valid after-dialysis weight.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (hours == null || hours < 0 || hours > 8) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Session duration hours must be between 0 and 8.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (minutes == null || minutes < 0 || minutes > 59) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Session duration minutes must be between 0 and 59.',
                    ),
                    backgroundColor: Colors.red,
                  ),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
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
                              color: primary.withOpacity(0.12),
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
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(),
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
                                      ? const Color(0xFFCBD5E1)
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
                                        : const Color(0xFF94A3B8)),
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
                                          : const Color(0xFFB0BBC7),
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

  Future<void> _showFeedbackDialog({
    required BuildContext ctx,
    required bool success,
    required String message,
  }) async {
    final color = success ? green : const Color(0xFFEF4444);
    final icon = success ? Icons.check_circle_rounded : Icons.error_rounded;

    await showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (feedbackContext) {
        bool dismissed = false;
        void dismiss() {
          if (dismissed) return;
          dismissed = true;
          if (feedbackContext.mounted) {
            Navigator.of(feedbackContext).pop();
          }
        }

        Timer(const Duration(seconds: 3), dismiss);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: dismiss,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tap anywhere to dismiss',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
        color: color.withOpacity(0.12),
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
        color: enabled ? Colors.white : const Color(0xFFF8FAFC),
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
                  color: accent.withOpacity(0.14),
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
          color: enabled ? primary : const Color(0xFFB0BBC7),
        ),
        filled: true,
        fillColor: enabled ? softBg : const Color(0xFFF1F5F9),
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

              return GestureDetector(
                onTap: () async {
                  setState(() => selectedDay = day);
                  await loadSelectedDaySchedule();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
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
                        color: Colors.black.withOpacity(
                          isSelected ? 0.08 : 0.03,
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
    final bool isFull = patients.length >= widget.machineCount;
    final int rowsToShow = widget.machineCount > 12 ? 12 : widget.machineCount;

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
                          '${patients.length}/${widget.machineCount} slots filled',
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
                              color: const Color(0xFFF1F5F9),
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
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
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
                2: FixedColumnWidth(42),
              },
              children: List.generate(rowsToShow, (index) {
                final patient = index < patients.length
                    ? patients[index]
                    : null;

                return TableRow(
                  decoration: BoxDecoration(
                    color: index.isEven
                        ? const Color(0xFFFBFDFF)
                        : Colors.white,
                  ),
                  children: [
                    numberCell('${index + 1}'),
                    patientCell(patient, shift),
                    tableActionCell(patient),
                  ],
                );
              }),
            ),
          ),
          if (widget.machineCount > rowsToShow) ...[
            const SizedBox(height: 10),
            Text(
              '+ ${widget.machineCount - rowsToShow} more machine slots',
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
                  color: isEmpty ? const Color(0xFFB0BBC7) : textDark,
                ),
              ),
            ),
            if (!isEmpty) _statusChip(_service.isSessionCompleted(patient)),
          ],
        ),
      ),
    );
  }

  Widget tableActionCell(dynamic patient) {
    return Container(
      height: 34,
      alignment: Alignment.center,
      child: patient == null
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: 'Remove',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Color(0xFFEF4444),
              ),
              onPressed: () => removePatient(patient),
            ),
    );
  }

  Widget _buildSummaryStrip() {
    final totalAssigned = amPatients.length + pmPatients.length;
    final totalCapacity = widget.machineCount * 2;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
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
            const Color(0xFF8E44AD),
          ),
          const SizedBox(width: 12),
          _summaryItem(
            'Capacity Used',
            '$totalAssigned/$totalCapacity',
            Icons.event_seat_rounded,
            const Color(0xFFF59E0B),
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
              color: color.withOpacity(0.11),
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
          const Padding(
            padding: EdgeInsets.all(30),
            child: CircularProgressIndicator(color: primary),
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
