import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/appointment_service.dart';
import '../../services/notification_service.dart';

class AppointmentPage extends StatefulWidget {
  const AppointmentPage({super.key});

  @override
  State<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends State<AppointmentPage> {
  final AppointmentService _appointmentService = AppointmentService();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showHistory = false;

  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _weeklySchedule;
  List<String> _scheduledDays = [];

  static const Map<int, String> _weekdayNames = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    try {
      final data = await _appointmentService.getMySchedule();

      print('APPOINTMENT DATA: $data');
      print('WEEKLY: ${data?['weekly_schedule']}');
      print('SCHEDULED DAYS: ${data?['weekly_schedule']?['scheduled_days']}');

      if (!mounted) return;

      setState(() {
        _weeklySchedule = data?['weekly_schedule'];
        _scheduledDays = _parseScheduledDays(
          data?['weekly_schedule']?['scheduled_days'],
        );
        _isLoading = false;
      });

      print('PARSED DAYS: $_scheduledDays');
      await _checkScheduleReminders();
    } catch (e) {
      print('LOAD SCHEDULE ERROR: $e');

      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _checkScheduleReminders() async {
    if (_scheduledDays.isEmpty) return;

    try {
      final now = DateTime.now();
      final todayName = _weekdayNames[now.weekday]!;
      final tomorrowName =
          _weekdayNames[now.add(const Duration(days: 1)).weekday]!;
      final startOfDay = DateTime(now.year, now.month, now.day);
      final notificationService = NotificationService();

      if (_scheduledDays.contains(todayName)) {
        final exists = await notificationService.hasNotificationOfTypeSince(
          'schedule_today',
          startOfDay,
        );
        if (!exists) {
          await notificationService.createNotification(
            title: 'Dialysis Schedule Today',
            message: 'You have a dialysis schedule today.',
            type: 'schedule_today',
          );
        }
      }

      if (_scheduledDays.contains(tomorrowName)) {
        final exists = await notificationService.hasNotificationOfTypeSince(
          'schedule_tomorrow',
          startOfDay,
        );
        if (!exists) {
          await notificationService.createNotification(
            title: 'Dialysis Schedule Tomorrow',
            message: 'You have a dialysis schedule tomorrow.',
            type: 'schedule_tomorrow',
          );
        }
      }
    } catch (e) {
      debugPrint('Schedule reminder error: $e');
    }
  }

  List<String> _parseScheduledDays(dynamic scheduledDays) {
    if (scheduledDays == null) return [];

    final rawList = <String>[];

    if (scheduledDays is List) {
      rawList.addAll(
        scheduledDays
            .map((item) => item?.toString() ?? '')
            .where((value) => value.isNotEmpty),
      );
    } else if (scheduledDays is String) {
      final trimmed = scheduledDays.trim();

      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) {
            rawList.addAll(
              decoded
                  .map((item) => item?.toString() ?? '')
                  .where((value) => value.isNotEmpty),
            );
          }
        } catch (_) {
          rawList.addAll(
            trimmed
                .substring(1, trimmed.length - 1)
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty),
          );
        }
      } else {
        rawList.addAll(
          trimmed
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty),
        );
      }
    } else if (scheduledDays is Map) {
      final dayValue = scheduledDays['day']?.toString();
      if (dayValue != null && dayValue.isNotEmpty) {
        rawList.add(dayValue);
      }
    }

    return rawList
        .map(_normalizeDayName)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) {
        final indexA = _weekdayNames.entries
            .firstWhere((e) => e.value == a)
            .key;
        final indexB = _weekdayNames.entries
            .firstWhere((e) => e.value == b)
            .key;
        return indexA.compareTo(indexB);
      });
  }

  String _normalizeDayName(String rawDay) {
    final value = rawDay.trim().toLowerCase();

    switch (value) {
      case 'monday':
      case 'mon':
      case 'm':
      case '1':
        return 'Monday';

      case 'tuesday':
      case 'tue':
      case 'tues':
      case 't':
      case '2':
        return 'Tuesday';

      case 'wednesday':
      case 'wed':
      case 'w':
      case '3':
        return 'Wednesday';

      case 'thursday':
      case 'thu':
      case 'thurs':
      case 'th':
      case '4':
        return 'Thursday';

      case 'friday':
      case 'fri':
      case 'f':
      case '5':
        return 'Friday';

      case 'saturday':
      case 'sat':
      case 'sa':
      case '6':
        return 'Saturday';

      case 'sunday':
      case 'sun':
      case 'su':
      case '7':
        return 'Sunday';

      default:
        return '';
    }
  }

  bool _isScheduledDay(DateTime day) {
    if (_scheduledDays.isEmpty) return false;

    final weekdayName = _weekdayNames[day.weekday];
    return _scheduledDays.contains(weekdayName);
  }

  bool _isSameDate(DateTime? a, DateTime b) {
    if (a == null) return false;

    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDays() {
    if (_scheduledDays.isEmpty) return 'No schedule assigned yet';
    return _scheduledDays.join(', ');
  }

  List<DateTime> _getPastScheduleDates() {
    if (_scheduledDays.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pastDates = <DateTime>[];

    for (int i = 1; i <= 30; i++) {
      final date = today.subtract(Duration(days: i));
      final dayName = _weekdayNames[date.weekday];

      if (_scheduledDays.contains(dayName)) {
        pastDates.add(date);
      }
    }

    return pastDates;
  }

  String _monthName(int month) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month];
  }

  Widget _buildScheduleCalendar() {
    final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final lastDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    final startWeekday = firstDayOfMonth.weekday % 7;
    final totalDays = lastDayOfMonth.day;

    final days = <DateTime?>[];

    for (int i = 0; i < startWeekday; i++) {
      days.add(null);
    }

    for (int day = 1; day <= totalDays; day++) {
      days.add(DateTime(_focusedDay.year, _focusedDay.month, day));
    }

    while (days.length % 7 != 0) {
      days.add(null);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E7EC)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CalendarArrowButton(
                icon: Icons.chevron_left,
                onTap: () {
                  setState(() {
                    _focusedDay = DateTime(
                      _focusedDay.year,
                      _focusedDay.month - 1,
                      1,
                    );
                  });
                },
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthName(_focusedDay.month)} ${_focusedDay.year}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
              ),
              _CalendarArrowButton(
                icon: Icons.chevron_right,
                onTap: () {
                  setState(() {
                    _focusedDay = DateTime(
                      _focusedDay.year,
                      _focusedDay.month + 1,
                      1,
                    );
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _DayLabel('Su'),
              _DayLabel('Mo'),
              _DayLabel('Tu'),
              _DayLabel('We'),
              _DayLabel('Th'),
              _DayLabel('Fr'),
              _DayLabel('Sa'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final day = days[index];

              if (day == null) {
                return const SizedBox();
              }

              final isScheduled = _isScheduledDay(day);
              final isSelected = _isSameDate(_selectedDay, day);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDay = day;
                  });
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isScheduled
                        ? const Color(0xFF5145F6)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(color: const Color(0xFF1D4356), width: 2)
                        : null,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: isScheduled
                          ? Colors.white
                          : const Color(0xFF374151),
                      fontSize: 12,
                      fontWeight: isScheduled
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSchedule = _scheduledDays.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF2C5F7D),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: const Text(
                'My Schedule',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F7F8),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Assigned Schedule',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2C5F7D),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              hasSchedule
                                  ? 'Set by your healthcare provider'
                                  : 'No schedule assigned yet',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF5B6D7D),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (hasSchedule)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    color: Color(0xFF2C5F7D),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _formatDays(),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _showHistory = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _showHistory
                                    ? Colors.white
                                    : const Color(0xFF2C5F7D),
                                side: BorderSide(
                                  color: _showHistory
                                      ? const Color(0xFF2C5F7D)
                                      : Colors.transparent,
                                ),
                                foregroundColor: _showHistory
                                    ? const Color(0xFF2C5F7D)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text('Calendar View'),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _showHistory = true;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _showHistory
                                    ? const Color(0xFFEAF6F8)
                                    : Colors.white,
                                side: const BorderSide(
                                  color: Color(0xFF2C5F7D),
                                ),
                                foregroundColor: const Color(0xFF2C5F7D),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text('History'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                      else if (_showHistory)
                        Builder(
                          builder: (context) {
                            final historyDates = _getPastScheduleDates();

                            if (historyDates.isEmpty) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F7F8),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'No completed dialysis sessions yet.',
                                  style: TextStyle(color: Color(0xFF5B6D7D)),
                                ),
                              );
                            }

                            return Column(
                              children: historyDates.map((date) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F7F8),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF2C5F7D,
                                          ).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.check_circle_outline,
                                          color: Color(0xFF2C5F7D),
                                        ),
                                      ),

                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              DateFormat(
                                                'EEEE, MMMM d, yyyy',
                                              ).format(date),
                                              style: const TextStyle(
                                                color: Color(0xFF173B4F),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),

                                            const SizedBox(height: 4),

                                            const Text(
                                              'Dialysis session completed',
                                              style: TextStyle(
                                                color: Color(0xFF5B6D7D),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7F8),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Scheduled Days',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2937),
                                ),
                              ),

                              const SizedBox(height: 14),

                              _buildScheduleCalendar(),

                              const SizedBox(height: 18),

                              Container(
                                height: 1,
                                color: const Color(0xFFDDE6EA),
                              ),

                              const SizedBox(height: 14),

                              Row(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF5145F6),
                                      shape: BoxShape.circle,
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  Expanded(
                                    child: Text(
                                      hasSchedule
                                          ? 'Scheduled dialysis days (${_scheduledDays.map((day) => day.substring(0, 3)).join('/')})'
                                          : 'Scheduled dialysis days',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF5B6D7D),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  final String label;

  const _DayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF8A98A8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CalendarArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CalendarArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF6B7280)),
      ),
    );
  }
}
