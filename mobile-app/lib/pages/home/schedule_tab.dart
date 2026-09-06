import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/appointment_service.dart';
import '../../services/health_monitoring_service.dart';
import '../../services/notification_service.dart';
import '../../services/reschedule_service.dart';

class AppointmentPage extends StatefulWidget {
  const AppointmentPage({super.key});

  @override
  State<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends State<AppointmentPage> {
  final AppointmentService _appointmentService = AppointmentService();
  final HealthMonitoringService _healthService = HealthMonitoringService();
  final RescheduleService _rescheduleService = RescheduleService();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showReschedule = false;

  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _weeklySchedule;
  List<String> _scheduledDays = [];
  DateTime? _scheduleCreatedAt;

  // Dates (yyyy-MM-dd) the patient actually has a logged BP or weight
  // reading for — used to tell a completed session apart from a missed
  // one when rendering past scheduled dates.
  Set<String> _loggedSessionDates = {};

  // Reschedule request state.
  bool _isLoadingRequests = true;
  bool _isSubmittingRequest = false;
  String? _requestErrorMessage;
  List<Map<String, dynamic>> _myRequests = [];
  DateTime? _requestedDate;
  String _requestReason = 'Medical emergency';
  final TextEditingController _requestNotesController =
      TextEditingController();

  static const List<String> _rescheduleReasons = [
    'Medical emergency',
    'Personal conflict',
    'Travel',
    'Other',
  ];

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
    _loadMyRequests();
  }

  @override
  void dispose() {
    _requestNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadSchedule() async {
    try {
      final results = await Future.wait([
        _appointmentService.getMySchedule(),
        _healthService.getBloodPressureRecords(),
        _healthService.getWeightRecords(),
      ]);

      if (!mounted) return;

      final data = results[0] as Map<String, dynamic>?;
      final bpRecords = results[1] as List<Map<String, dynamic>>;
      final weightRecords = results[2] as List<Map<String, dynamic>>;

      final loggedDates = <String>{};
      for (final record in [...bpRecords, ...weightRecords]) {
        final sessionDate = record['session_date']?.toString();
        if (sessionDate != null && sessionDate.isNotEmpty) {
          loggedDates.add(sessionDate.split('T').first);
        }
      }

      setState(() {
        _weeklySchedule = data?['weekly_schedule'];
        _scheduledDays = _parseScheduledDays(
          data?['weekly_schedule']?['scheduled_days'],
        );
        _scheduleCreatedAt = DateTime.tryParse(
          data?['weekly_schedule']?['created_at']?.toString() ?? '',
        );
        _loggedSessionDates = loggedDates;
        _isLoading = false;
      });

      await _checkScheduleReminders();
    } catch (e) {
      debugPrint('Load schedule error: $e');

      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMyRequests() async {
    try {
      final requests = await _rescheduleService.getMyRequests();
      if (!mounted) return;
      setState(() {
        _myRequests = requests;
        _isLoadingRequests = false;
      });
    } catch (e) {
      debugPrint('Load reschedule requests error: $e');
      if (!mounted) return;
      setState(() => _isLoadingRequests = false);
    }
  }

  bool _hasLoggedSessionOn(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    return _loggedSessionDates.contains(key);
  }

  Future<void> _pickRequestedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _requestedDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _requestedDate = picked);
    }
  }

  Future<void> _submitRescheduleRequest() async {
    if (_requestedDate == null) {
      setState(
        () => _requestErrorMessage = 'Please select your preferred date.',
      );
      return;
    }

    setState(() {
      _isSubmittingRequest = true;
      _requestErrorMessage = null;
    });

    try {
      await _rescheduleService.submitRequest(
        originalDate: _selectedDay ?? DateTime.now(),
        requestedDate: _requestedDate!,
        reason: _requestReason,
        notes: _requestNotesController.text.trim().isEmpty
            ? null
            : _requestNotesController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _requestedDate = null;
        _requestNotesController.clear();
      });

      await _loadMyRequests();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reschedule request sent. Your clinic will review it soon.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestErrorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequest = false);
      }
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
    final scheduleStart = _scheduleCreatedAt == null
        ? null
        : DateTime(
            _scheduleCreatedAt!.year,
            _scheduleCreatedAt!.month,
            _scheduleCreatedAt!.day,
          );
    final pastDates = <DateTime>[];

    for (int i = 1; i <= 30; i++) {
      final date = today.subtract(Duration(days: i));
      if (scheduleStart != null && date.isBefore(scheduleStart)) continue;
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
                        ? const Color(0xFF225E72)
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

  Widget _buildHistoryList() {
    final historyDates = _getPastScheduleDates();

    if (historyDates.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3EDF2)),
        ),
        child: const Text(
          'No past scheduled sessions yet.',
          style: TextStyle(color: Color(0xFF5B6D7D), fontSize: 13),
        ),
      );
    }

    return Column(
      children: historyDates.map((date) {
        final attended = _hasLoggedSessionOn(date);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: attended ? Colors.white : const Color(0xFFFFF3F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: attended
                  ? const Color(0xFFE1EAF0)
                  : const Color(0xFFF7C9BE),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: attended
                      ? const Color(0xFFE8F1F5)
                      : const Color(0xFFFBE2DB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  attended ? Icons.check_circle_outline : Icons.error_outline,
                  color: attended
                      ? const Color(0xFF225E72)
                      : const Color(0xFFC0432A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, MMMM d, yyyy').format(date),
                      style: const TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      attended
                          ? 'Dialysis session completed'
                          : 'Patient did not take dialysis session today',
                      style: TextStyle(
                        color: attended
                            ? const Color(0xFF5B6D7D)
                            : const Color(0xFFC0432A),
                        fontSize: 11.5,
                        fontWeight: attended
                            ? FontWeight.normal
                            : FontWeight.w700,
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
  }

  Widget _buildRescheduleTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE1EAF0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Request a Reschedule',
                style: TextStyle(
                  color: Color(0xFF173B4F),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Need to move a dialysis session? Send a request and your '
                'clinic will review and confirm it.',
                style: TextStyle(color: Color(0xFF7A8A94), fontSize: 13),
              ),
              const SizedBox(height: 18),
              const Text(
                'Preferred New Date',
                style: TextStyle(
                  color: Color(0xFF173B4F),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickRequestedDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE3EDF2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: Color(0xFF5F7280),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _requestedDate == null
                            ? 'Select a date'
                            : DateFormat(
                                'EEEE, MMMM d, yyyy',
                              ).format(_requestedDate!),
                        style: TextStyle(
                          color: _requestedDate == null
                              ? const Color(0xFF6F7F89)
                              : const Color(0xFF173B4F),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason',
                style: TextStyle(
                  color: Color(0xFF173B4F),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _requestReason,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF4F8FA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE3EDF2)),
                  ),
                ),
                items: _rescheduleReasons.map((reason) {
                  return DropdownMenuItem(value: reason, child: Text(reason));
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _requestReason = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Notes (optional)',
                style: TextStyle(
                  color: Color(0xFF173B4F),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _requestNotesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Anything else your clinic should know',
                  filled: true,
                  fillColor: const Color(0xFFF4F8FA),
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE3EDF2)),
                  ),
                ),
              ),
              if (_requestErrorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.20)),
                  ),
                  child: Text(
                    _requestErrorMessage!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmittingRequest
                      ? null
                      : _submitRescheduleRequest,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF225E72),
                    disabledBackgroundColor: const Color(
                      0xFF225E72,
                    ).withOpacity(0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmittingRequest
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Text(
                          'Send Request',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Your Reschedule Requests',
          style: TextStyle(
            color: Color(0xFF173B4F),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (_isLoadingRequests)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF225E72)),
            ),
          )
        else if (_myRequests.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8FA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3EDF2)),
            ),
            child: const Text(
              'You haven\'t sent any reschedule requests yet.',
              style: TextStyle(color: Color(0xFF5B6D7D), fontSize: 13),
            ),
          )
        else
          ..._myRequests.map((request) {
            final status =
                request['status']?.toString().toLowerCase().trim() ??
                'pending';
            final statusColor = status == 'approved'
                ? const Color(0xFF2A9D65)
                : status == 'declined'
                ? const Color(0xFFC0432A)
                : const Color(0xFFB4690E);
            final requestedDate = DateTime.tryParse(
              request['requested_date']?.toString() ?? '',
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE1EAF0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          requestedDate == null
                              ? 'Requested date pending'
                              : 'New date: ${DateFormat('MMM d, yyyy').format(requestedDate)}',
                          style: const TextStyle(
                            color: Color(0xFF173B4F),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reason: ${request['reason'] ?? 'N/A'}',
                    style: const TextStyle(
                      color: Color(0xFF5B6D7D),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSchedule = _scheduledDays.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
              decoration: const BoxDecoration(
                color: Color(0xFF225E72),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Schedule',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'View your assigned dialysis schedule and appointment history.',
                    style: TextStyle(
                      color: Color(0xFFD9EDF3),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE1EAF0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F1F5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.event_available_outlined,
                              color: Color(0xFF225E72),
                              size: 26,
                            ),
                          ),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Assigned Schedule',
                                  style: TextStyle(
                                    color: Color(0xFF173B4F),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),

                                const SizedBox(height: 5),

                                Text(
                                  hasSchedule
                                      ? _formatDays()
                                      : 'No schedule assigned yet',
                                  style: const TextStyle(
                                    color: Color(0xFF5B6D7D),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F1F5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showReschedule = false;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: !_showReschedule
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Calendar',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: !_showReschedule
                                        ? const Color(0xFF225E72)
                                        : const Color(0xFF7A8A94),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showReschedule = true;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: _showReschedule
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Reschedule',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _showReschedule
                                        ? const Color(0xFF225E72)
                                        : const Color(0xFF7A8A94),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF225E72),
                          ),
                        ),
                      )
                    else if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.20),
                          ),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (_showReschedule)
                      _buildRescheduleTab()
                    else
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE1EAF0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Scheduled Days',
                              style: TextStyle(
                                color: Color(0xFF173B4F),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),

                            const SizedBox(height: 6),

                            const Text(
                              'Highlighted dates show your dialysis schedule.',
                              style: TextStyle(
                                color: Color(0xFF7A8A94),
                                fontSize: 13,
                              ),
                            ),

                            const SizedBox(height: 18),

                            _buildScheduleCalendar(),

                            const SizedBox(height: 18),

                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F8FA),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE3EDF2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF225E72),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      hasSchedule
                                          ? 'Scheduled dialysis days: ${_scheduledDays.map((day) => day.substring(0, 3)).join(', ')}'
                                          : 'Scheduled dialysis days will appear once assigned.',
                                      style: const TextStyle(
                                        color: Color(0xFF5B6D7D),
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            const Text(
                              'History',
                              style: TextStyle(
                                color: Color(0xFF173B4F),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),

                            const SizedBox(height: 6),

                            const Text(
                              'Past scheduled sessions, based on your logged '
                              'blood pressure and weight readings.',
                              style: TextStyle(
                                color: Color(0xFF7A8A94),
                                fontSize: 12,
                              ),
                            ),

                            const SizedBox(height: 14),

                            _buildHistoryList(),
                          ],
                        ),
                      ),
                  ],
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
