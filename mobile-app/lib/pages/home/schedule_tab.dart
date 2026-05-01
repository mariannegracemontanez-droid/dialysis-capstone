import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key});

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  int _selectedViewIndex = 0;
  final List<DateTime> _scheduledDays = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F7FF),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4B6EFC),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(14),
                                ),
                              ),
                              child: const Icon(
                                Icons.calendar_month,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Your Assigned Schedule',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A3F6C),
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Set by your healthcare provider',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF5E6F8E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F9FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE0E8F8)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Color(0xFF2C5F7D),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Your schedule is managed by your healthcare team. If you need to reschedule, please contact the clinic directly.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF3C4B68),
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _buildViewButton('Calendar View', 0),
                          const SizedBox(width: 12),
                          _buildViewButton('History', 1),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_selectedViewIndex == 0) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE9EFF9)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              TableCalendar(
                                firstDay: DateTime.utc(2026, 1, 1),
                                lastDay: DateTime.utc(2026, 12, 31),
                                focusedDay: _focusedDay,
                                selectedDayPredicate: (day) =>
                                    isSameDay(_selectedDay, day),
                                onDaySelected: (selectedDay, focusedDay) {
                                  setState(() {
                                    _selectedDay = selectedDay;
                                    _focusedDay = focusedDay;
                                  });
                                },
                                calendarBuilders: CalendarBuilders(
                                  defaultBuilder: (context, day, focusedDay) {
                                    final isScheduled = _scheduledDays.any(
                                      (scheduled) => isSameDay(scheduled, day),
                                    );
                                    return _buildCalendarDay(day, isScheduled);
                                  },
                                  todayBuilder: (context, day, focusedDay) {
                                    final isScheduled = _scheduledDays.any(
                                      (scheduled) => isSameDay(scheduled, day),
                                    );
                                    return _buildCalendarDay(
                                      day,
                                      isScheduled,
                                      isToday: true,
                                    );
                                  },
                                  selectedBuilder: (context, day, focusedDay) {
                                    final isScheduled = _scheduledDays.any(
                                      (scheduled) => isSameDay(scheduled, day),
                                    );
                                    return _buildCalendarDay(
                                      day,
                                      isScheduled,
                                      isSelected: true,
                                    );
                                  },
                                ),
                                calendarStyle: const CalendarStyle(
                                  todayDecoration: BoxDecoration(
                                    color: Color(0xFF2C9B9E),
                                    shape: BoxShape.circle,
                                  ),
                                  selectedDecoration: BoxDecoration(
                                    color: Color(0xFF4B6EFC),
                                    shape: BoxShape.circle,
                                  ),
                                  outsideDaysVisible: false,
                                ),
                                headerStyle: const HeaderStyle(
                                  formatButtonVisible: false,
                                  titleCentered: true,
                                  titleTextStyle: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2C5F7D),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF4B6EFC),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Scheduled dialysis days',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF5E6F8E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _scheduledDays.isEmpty
                                      ? 'No schedule assigned yet.'
                                      : 'Your scheduled days are highlighted above.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8D9CB4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F9FE),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE4E9F5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'No history available yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2C5F7D),
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Completed dialysis sessions will appear here once your appointments finish.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF5B6478),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewButton(String label, int index) {
    final bool isSelected = _selectedViewIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedViewIndex = index;
          });
        },
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4B6EFC) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF4B6EFC)
                  : const Color(0xFFCBD6EA),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF4B6EFC),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarDay(
    DateTime day,
    bool isScheduled, {
    bool isToday = false,
    bool isSelected = false,
  }) {
    final Color dayColor = isScheduled ? Colors.white : const Color(0xFF374151);
    final Color bgColor = isSelected
        ? const Color(0xFF4B6EFC)
        : isScheduled
        ? const Color(0xFF4B6EFC)
        : Colors.transparent;
    final BoxDecoration decoration = BoxDecoration(
      color: bgColor,
      shape: BoxShape.circle,
    );

    return Container(
      decoration: decoration,
      margin: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: dayColor,
          fontWeight: isSelected || isScheduled
              ? FontWeight.bold
              : FontWeight.w500,
        ),
      ),
    );
  }
}
