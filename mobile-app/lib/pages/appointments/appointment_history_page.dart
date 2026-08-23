import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/appointment_service.dart';

class AppointmentHistoryPage extends StatefulWidget {
  const AppointmentHistoryPage({super.key});

  @override
  State<AppointmentHistoryPage> createState() => _AppointmentHistoryPageState();
}

class _AppointmentHistoryPageState extends State<AppointmentHistoryPage> {
  final AppointmentService _appointmentService = AppointmentService();

  bool _isLoading = true;
  String? _errorMessage;
  List<String> _scheduledDays = [];
  DateTime? _scheduleCreatedAt;

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

      if (!mounted) return;

      setState(() {
        _scheduledDays = _parseScheduledDays(
          data?['weekly_schedule']?['scheduled_days'],
        );
        _scheduleCreatedAt = DateTime.tryParse(
          data?['weekly_schedule']?['created_at']?.toString() ?? '',
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
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
        .toList();
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

  @override
  Widget build(BuildContext context) {
    final historyDates = _getPastScheduleDates();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
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
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Appointment History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2C5F7D),
                      ),
                    )
                  : _errorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : historyDates.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Appointment History',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your completed appointments will appear here once you have finished your dialysis sessions.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      children: [
                        const Text(
                          'Completed Sessions',
                          style: TextStyle(
                            color: Color(0xFF173B4F),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...historyDates.map((date) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFE1EAF0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F1F5),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.check_circle_outline,
                                    color: Color(0xFF2C5F7D),
                                  ),
                                ),
                                const SizedBox(width: 14),
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
                                          fontWeight: FontWeight.w800,
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
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
