import 'package:admin_panel/services/schedule_service.dart';
import 'package:flutter/material.dart';

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

  List<dynamic> amPatients = [];
  List<dynamic> pmPatients = [];

  @override
  void initState() {
    super.initState();
    selectedDay = _getToday();
    loadSelectedDaySchedule();
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

    if (now.weekday >= DateTime.monday &&
        now.weekday <= DateTime.saturday) {
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

  Future<void> loadSelectedDaySchedule() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final selectedDate = getDateForSelectedDay();

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
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: Text(
                'Select Patient for $shift Shift',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
              content: SizedBox(
                width: 500,
                height: 430,
                child: availablePatients.isEmpty
                    ? const Center(
                        child: Text(
                          'No available patients scheduled for this day.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: availablePatients.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = availablePatients[index];
                          final patientName = getPatientName(item);

                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: dialogIsAdding
                                ? null
                                : () async {
                                    setDialogState(() {
                                      dialogIsAdding = true;
                                    });

                                    try {
                                      await _service.assignDailySchedule(
                                        weeklyScheduleId: item['id'],
                                        patientId: item['patient_id'],
                                        clinicId: widget.clinicId,
                                        shift: shift,
                                        scheduleDate: selectedDate,
                                      );

                                      if (!mounted) return;

                                      Navigator.of(dialogContext).pop();

                                      await loadSelectedDaySchedule();

                                      if (!mounted) return;

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '$patientName added to $shift Shift.',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } catch (e) {
                                      debugPrint('Add patient error: $e');

                                      if (!mounted) return;

                                      setDialogState(() {
                                        dialogIsAdding = false;
                                      });

                                      ScaffoldMessenger.of(context).showSnackBar(
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
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.person_rounded,
                                      color: Color(0xFF0369A1),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      patientName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                  dialogIsAdding
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
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
    debugPrint('Removing daily schedule item: $item');

    await _service.deleteDailySchedule(
      dailyScheduleId: item['id'].toString(),
      clinicId: widget.clinicId,
    );

    await loadSelectedDaySchedule();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Patient removed from schedule.'),
        backgroundColor: Colors.green,
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
    return Row(
      children: List.generate(days.length, (index) {
        final day = days[index];
        final date = getDateForDay(index);
        final isSelected = selectedDay == day;

        return Expanded(
          child: GestureDetector(
            onTap: () async {
              setState(() => selectedDay = day);
              await loadSelectedDaySchedule();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF7FCBC4) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF7FCBC4)
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isSelected ? 0.10 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    day,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget buildShiftTable({
    required String title,
    required String shift,
    required List<dynamic> patients,
  }) {
    final bool isFull = patients.length >= widget.machineCount;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title (${patients.length}/${widget.machineCount})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: isFull || isLoading
                      ? null
                      : () => openAddModal(shift),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Table(
              border: TableBorder.all(
                color: const Color(0xFFE2E8F0),
                width: 0.8,
              ),
              columnWidths: const {
                0: FixedColumnWidth(30),
                1: FlexColumnWidth(),
                2: FixedColumnWidth(46),
              },
              children: List.generate(widget.machineCount, (index) {
                final patient =
                    index < patients.length ? patients[index] : null;

                return TableRow(
                  decoration: BoxDecoration(
                    color:
                        index.isEven ? const Color(0xFFFBFDFF) : Colors.white,
                  ),
                  children: [
                    numberCell('${index + 1}'),
                    patientCell(
                      patient == null ? '' : getPatientName(patient),
                    ),
                    tableActionCell(patient),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget numberCell(String text) {
    return Container(
      height: 38,
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget patientCell(String text) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget tableActionCell(dynamic patient) {
    return Container(
      height: 38,
      alignment: Alignment.center,
      child: patient == null
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: 'Remove',
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.close_rounded,
                size: 17,
                color: Color(0xFFEF4444),
              ),
              onPressed: () => removePatient(patient),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        buildDayTabs(),
        const SizedBox(height: 18),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.all(34),
            child: CircularProgressIndicator(),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildShiftTable(
                title: 'AM Shift',
                shift: 'AM',
                patients: amPatients,
              ),
              const SizedBox(width: 16),
              buildShiftTable(
                title: 'PM Shift',
                shift: 'PM',
                patients: pmPatients,
              ),
            ],
          ),
      ],
    );
  }
  
}