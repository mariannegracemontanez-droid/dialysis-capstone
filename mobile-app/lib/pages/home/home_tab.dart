import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../services/appointment_service.dart';
import '../../services/health_monitoring_service.dart';
import '../appointments/appointment_history_page.dart';
import '../notifications/notification_page.dart';

class HomeTab extends StatefulWidget {
  final UserModel? user;
  final VoidCallback onScheduleTap;
  final VoidCallback onHealthMonitoringTap;
  const HomeTab({
    super.key,
    this.user,
    required this.onScheduleTap,
    required this.onHealthMonitoringTap,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final TextEditingController _searchController = TextEditingController();
  final AppointmentService _appointmentService = AppointmentService();
  final HealthMonitoringService _healthService = HealthMonitoringService();
  final PageController _tipsController = PageController();

  final int _dailyGoalMl = 1000;
  Timer? _tipsAutoScrollTimer;
  String _searchText = '';
  bool _isScheduleLoading = true;
  bool _isHealthSummaryLoading = true;

  List<String> _scheduledDays = [];
  DateTime? _nextScheduleDate;

  int _todayTotalMl = 0;
  int _currentTipIndex = 0;

  Map<String, dynamic>? _latestBloodPressure;
  Map<String, dynamic>? _latestWeightLog;

  RealtimeChannel? _healthSummaryChannel;

  final List<Map<String, String>> _dailyMotivations = const [
    {
      'title': 'You are doing great',
      'message':
          'Every small healthy choice today helps your treatment journey.',
    },
    {
      'title': 'One step at a time',
      'message':
          'Your progress may be slow sometimes, but every effort still matters.',
    },
    {
      'title': 'Stay strong today',
      'message':
          'Your strength and consistency are important parts of your recovery.',
    },
    {
      'title': 'Take care of yourself',
      'message':
          'Listening to your body and following your care plan makes a difference.',
    },
    {
      'title': 'Keep moving forward',
      'message':
          'Small healthy habits every day can lead to better long-term wellness.',
    },
    {
      'title': 'You are not alone',
      'message':
          'Your healthcare team and loved ones are supporting your journey.',
    },
    {
      'title': 'Your health matters',
      'message':
          'Taking care of yourself today is an investment for your future.',
    },
  ];

  final List<Map<String, dynamic>> _healthTips = const [
    {
      'title': 'Limit salty foods',
      'message':
          'Too much sodium can make you feel thirsty and may increase fluid buildup.',
      'icon': Icons.restaurant_menu_rounded,
    },
    {
      'title': 'Track your water intake',
      'message':
          'Small daily tracking habits can help you stay within your recommended fluid limit.',
      'icon': Icons.water_drop_outlined,
    },
    {
      'title': 'Watch potassium intake',
      'message':
          'Some fruits and foods may contain high potassium levels that need moderation.',
      'icon': Icons.local_dining_outlined,
    },
    {
      'title': 'Take medications on time',
      'message':
          'Follow your prescribed medicines consistently to help manage your condition.',
      'icon': Icons.medication_outlined,
    },
    {
      'title': 'Eat balanced meals',
      'message':
          'Healthy meals with proper nutrients can help support your overall health.',
      'icon': Icons.food_bank_outlined,
    },
    {
      'title': 'Get enough rest',
      'message':
          'Proper sleep helps your body recover and maintain better daily energy.',
      'icon': Icons.bedtime_outlined,
    },
    {
      'title': 'Do not skip sessions',
      'message':
          'Attending dialysis regularly helps your body remove extra waste and fluids.',
      'icon': Icons.event_available_rounded,
    },
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
    _loadUpcomingSchedule();
    _loadHealthSummary();
    _setupHealthSummaryRealtime();
    _startHealthTipsAutoScroll();
  }

  Future<void> _loadUpcomingSchedule() async {
    try {
      final data = await _appointmentService.getMySchedule();

      final days = _parseScheduledDays(
        data?['weekly_schedule']?['scheduled_days'],
      );

      final nextDate = _getNextScheduleDate(days);

      if (!mounted) return;

      setState(() {
        _scheduledDays = days;
        _nextScheduleDate = nextDate;
        _isScheduleLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isScheduleLoading = false;
      });
    }
  }

  Future<void> _loadHealthSummary() async {
    try {
      final results = await Future.wait([
        _healthService.getTodayWaterTotal(),
        _healthService.getLatestBloodPressure(),
        _healthService.getLatestWeightLog(),
      ]);

      if (!mounted) return;

      setState(() {
        _todayTotalMl = results[0] as int;
        _latestBloodPressure = results[1] as Map<String, dynamic>?;
        _latestWeightLog = results[2] as Map<String, dynamic>?;
        _isHealthSummaryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isHealthSummaryLoading = false;
      });
    }
  }

  void _setupHealthSummaryRealtime() {
    _healthSummaryChannel = Supabase.instance.client
        .channel('home-health-summary')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'water_intake_logs',
          callback: (_) {
            if (!mounted) return;
            _loadHealthSummary();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blood_pressure_logs',
          callback: (_) {
            if (!mounted) return;
            _loadHealthSummary();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'weight_logs',
          callback: (_) {
            if (!mounted) return;
            _loadHealthSummary();
          },
        )
        .subscribe();
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

  DateTime? _getNextScheduleDate(List<String> days) {
    if (days.isEmpty) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (int i = 0; i <= 7; i++) {
      final date = today.add(Duration(days: i));
      final dayName = _weekdayNames[date.weekday];

      if (days.contains(dayName)) {
        return date;
      }
    }

    return null;
  }

  String _getScheduleLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    if (date == today) return 'Today';
    if (date == tomorrow) return 'Tomorrow';

    return DateFormat('EEEE').format(date);
  }

  double get _waterProgressValue => min(_todayTotalMl / _dailyGoalMl, 1.0);

  String _getBpSummary() {
    if (_latestBloodPressure == null) return 'No BP record yet';

    final systolic = _latestBloodPressure!['systolic']?.toString() ?? '--';
    final diastolic = _latestBloodPressure!['diastolic']?.toString() ?? '--';

    return '$systolic/$diastolic mmHg';
  }

  String _getWeightSummary() {
    if (_latestWeightLog == null) return 'No weight record yet';

    final before =
        double.tryParse(_latestWeightLog!['before_weight'].toString()) ?? 0;
    final after =
        double.tryParse(_latestWeightLog!['after_weight'].toString()) ?? 0;

    return '${before.toStringAsFixed(1)}kg → ${after.toStringAsFixed(1)}kg';
  }

  List<Widget> _buildSearchResults() {
    final query = _searchText.toLowerCase().trim();

    final results = <Widget>[];

    if (query.contains('schedule') ||
        query.contains('dialysis') ||
        query.contains('appointment')) {
      results.add(_buildUpcomingScheduleSection());
    }

    if (query.contains('water') ||
        query.contains('bp') ||
        query.contains('blood') ||
        query.contains('weight') ||
        query.contains('health')) {
      results.add(_buildTodayStatusCard());
    }

    if (query.contains('tip') ||
        query.contains('food') ||
        query.contains('salt') ||
        query.contains('intake')) {
      results.add(_buildHealthTipsCarousel());
    }

    if (query.contains('monitor') ||
        query.contains('tracking') ||
        query.contains('logs')) {
      results.add(_buildHealthMonitoringCard());
    }

    if (results.isEmpty) {
      results.add(
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1EAF0)),
          ),
          child: Text(
            'No results found for "$_searchText".',
            style: const TextStyle(color: Color(0xFF5B6D7D), fontSize: 14),
          ),
        ),
      );
    }

    return results;
  }

  void _startHealthTipsAutoScroll() {
    _tipsAutoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_tipsController.hasClients || _healthTips.isEmpty)
        return;

      final nextPage = _currentTipIndex + 1 >= _healthTips.length
          ? 0
          : _currentTipIndex + 1;

      _tipsController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tipsController.dispose();
    _tipsAutoScrollTimer?.cancel();
    _healthSummaryChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.user?.fullName ?? 'Patient';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(userName),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                children: _searchText.isNotEmpty
                    ? [const SizedBox(height: 8), ..._buildSearchResults()]
                    : [
                        _buildMotivationalCard(),
                        const SizedBox(height: 22),
                        _buildUpcomingScheduleSection(),
                        const SizedBox(height: 22),
                        _buildTodayStatusCard(),
                        const SizedBox(height: 22),
                        _buildHealthTipsCarousel(),
                        const SizedBox(height: 22),
                        _buildHealthMonitoringCard(),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String userName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
      decoration: const BoxDecoration(
        color: Color(0xFF225E72),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Hello, $userName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const NotificationPage(),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'How are you feeling today?',
            style: TextStyle(
              color: Color(0xFFD9EDF3),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchText = value;
                });
              },
              decoration: const InputDecoration(
                hintText: 'Search appointments, health logs...',
                hintStyle: TextStyle(color: Color(0xFF8B9AA6), fontSize: 14),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Color(0xFF225E72),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> get _todayMotivation {
    final dayIndex = DateTime.now().day % _dailyMotivations.length;
    return _dailyMotivations[dayIndex];
  }

  Widget _buildMotivationalCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4E7EE)),
      ),
      child: Row(
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF225E72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _todayMotivation['title'] ?? '',
                  style: const TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _todayMotivation['message'] ?? '',
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
    );
  }

  Widget _buildUpcomingScheduleSection() {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Upcoming Schedules',
                style: TextStyle(
                  color: Color(0xFF173B4F),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: widget.onScheduleTap,
              child: const Text(
                'View all',
                style: TextStyle(
                  color: Color(0xFF225E72),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1F5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.calendar_month_outlined,
                      color: Color(0xFF225E72),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dialysis Session',
                          style: TextStyle(
                            color: Color(0xFF173B4F),
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _nextScheduleDate == null
                              ? 'Schedule status'
                              : '${_getScheduleLabel(_nextScheduleDate!)} schedule',
                          style: const TextStyle(
                            color: Color(0xFF7A8A94),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8FA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE3EDF2)),
                ),
                child: _isScheduleLoading
                    ? const Text(
                        'Loading your upcoming schedule...',
                        style: TextStyle(
                          color: Color(0xFF5B6D7D),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      )
                    : _nextScheduleDate == null
                    ? const Text(
                        'No schedule assigned yet. Your upcoming dialysis schedule will appear here once available.',
                        style: TextStyle(
                          color: Color(0xFF5B6D7D),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_getScheduleLabel(_nextScheduleDate!)} • ${DateFormat('MMMM d, yyyy').format(_nextScheduleDate!)}',
                            style: const TextStyle(
                              color: Color(0xFF173B4F),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your next dialysis session is scheduled on ${DateFormat('EEEE').format(_nextScheduleDate!)}.',
                            style: const TextStyle(
                              color: Color(0xFF5B6D7D),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Weekly schedule: ${_scheduledDays.join(', ')}',
                            style: const TextStyle(
                              color: Color(0xFF7A8A94),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.onScheduleTap,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFF225E72),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'VIEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const AppointmentHistoryPage(),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF225E72)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'HISTORY',
                        style: TextStyle(
                          color: Color(0xFF225E72),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTodayStatusCard() {
    final waterPercent = (_waterProgressValue * 100).clamp(0, 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: _isHealthSummaryLoading
          ? const Text(
              'Loading today’s health status...',
              style: TextStyle(color: Color(0xFF5B6D7D), fontSize: 13),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today’s Health Status',
                  style: TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                _buildStatusRow(
                  icon: Icons.water_drop_outlined,
                  title: 'Water Goal',
                  value:
                      '$waterPercent% • $_todayTotalMl mL / $_dailyGoalMl mL',
                  color: const Color(0xFF1D9BD1),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _waterProgressValue,
                    minHeight: 9,
                    backgroundColor: const Color(0xFFE8F1F5),
                    color: const Color(0xFF1D9BD1),
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatusRow(
                  icon: Icons.favorite_border_rounded,
                  title: 'Blood Pressure',
                  value: _getBpSummary(),
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                _buildStatusRow(
                  icon: Icons.monitor_weight_outlined,
                  title: 'Latest Weight',
                  value: _getWeightSummary(),
                  color: const Color(0xFF225E72),
                ),
                const SizedBox(height: 12),
                _buildStatusRow(
                  icon: Icons.event_available_rounded,
                  title: 'Dialysis Schedule',
                  value: _nextScheduleDate == null
                      ? 'No upcoming schedule'
                      : '${_getScheduleLabel(_nextScheduleDate!)} • ${DateFormat('MMM d').format(_nextScheduleDate!)}',
                  color: const Color(0xFF2F8F72),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF7A8A94),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF173B4F),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHealthTipsCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Health Tips',
                    style: TextStyle(
                      color: Color(0xFF173B4F),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Simple care reminders for your daily routine',
                    style: TextStyle(
                      color: Color(0xFF7A8A94),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4F7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD4E7EE)),
              ),
              child: Text(
                '${_currentTipIndex + 1}/${_healthTips.length}',
                style: const TextStyle(
                  color: Color(0xFF225E72),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 176,
          child: PageView.builder(
            controller: _tipsController,
            itemCount: _healthTips.length,
            onPageChanged: (index) {
              setState(() {
                _currentTipIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final tip = _healthTips[index];

              final List<Color> cardColors = [
                const Color(0xFF225E72),
                const Color(0xFF2F8F72),
                const Color(0xFF1D7FA3),
                const Color(0xFF476A8A),
              ];

              final Color cardColor = cardColors[index % cardColors.length];

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: cardColor.withOpacity(0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -18,
                      top: -20,
                      child: Container(
                        height: 92,
                        width: 92,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 18,
                      bottom: -32,
                      child: Container(
                        height: 88,
                        width: 88,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          height: 62,
                          width: 62,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                            ),
                          ),
                          child: Icon(
                            tip['icon'] as IconData,
                            color: Colors.white,
                            size: 31,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Daily Care Tip',
                                  style: TextStyle(
                                    color: Color(0xFFEAF7FA),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                tip['title'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                tip['message'].toString(),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFE4F3F7),
                                  fontSize: 13,
                                  height: 1.42,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _healthTips.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 7,
              width: _currentTipIndex == index ? 24 : 7,
              decoration: BoxDecoration(
                color: _currentTipIndex == index
                    ? const Color(0xFF225E72)
                    : const Color(0xFFD5E2E8),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHealthMonitoringCard() {
    return GestureDetector(
      onTap: widget.onHealthMonitoringTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF225E72),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Health Monitoring',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Track water intake, health logs, and daily care updates.',
                    style: TextStyle(
                      color: Color(0xFFD9EDF3),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: widget.onHealthMonitoringTap,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(10, 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Learn More',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              height: 74,
              width: 74,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.water_drop_outlined,
                color: Colors.white,
                size: 34,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
