import 'package:admin_panel/services/schedule_service.dart';
import 'package:flutter/material.dart';
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
                    patientCell(
                      patient == null
                          ? 'Available slot'
                          : getPatientName(patient),
                      patient == null,
                    ),
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

  Widget patientCell(String text, bool isEmpty) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w800,
          color: isEmpty ? const Color(0xFFB0BBC7) : textDark,
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
