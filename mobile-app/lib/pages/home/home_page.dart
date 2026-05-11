import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/auth/auth_service.dart';
import '../../services/appointment_service.dart';
import '../../services/fcm_service.dart';
import '../../services/notification_service.dart';
import '../../models/user_model.dart';
import 'health_monitoring_page.dart';
import 'home_tab.dart';
import 'schedule_tab.dart';
import 'profile_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _authService = AuthService();
  UserModel? _currentUser;
  int _selectedNavIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _authService.getCurrentUser();
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });

      await _maybeCreateScheduleReminders();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading user: $e')));
      }
    }
  }

  Future<void> _maybeCreateScheduleReminders() async {
    final reminderService = NotificationService();
    final appointmentService = AppointmentService();

    try {
      final scheduleData = await appointmentService.getMySchedule();
      final rawDays = scheduleData?['weekly_schedule']?['scheduled_days'];
      if (rawDays == null) return;

      final scheduledDays = _parseScheduledDays(rawDays);
      final now = DateTime.now();
      final today = DateFormat('EEEE').format(now);
      final tomorrow = DateFormat('EEEE').format(now.add(const Duration(days: 1)));
      final startOfDay = DateTime(now.year, now.month, now.day);

      if (scheduledDays.contains(today)) {
        final exists = await reminderService.hasNotificationOfTypeSince(
          'schedule_today',
          startOfDay,
        );
        if (!exists) {
          await reminderService.createNotification(
            title: 'Dialysis Schedule Today',
            message: 'You have a dialysis schedule today.',
            type: 'schedule_today',
          );
        }
      }

      if (scheduledDays.contains(tomorrow)) {
        final exists = await reminderService.hasNotificationOfTypeSince(
          'schedule_tomorrow',
          startOfDay,
        );
        if (!exists) {
          await reminderService.createNotification(
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

    if (scheduledDays is List) {
      return scheduledDays
          .map((item) => item?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .map(_normalizeDayName)
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) {
          final order = {
            'Monday': 1,
            'Tuesday': 2,
            'Wednesday': 3,
            'Thursday': 4,
            'Friday': 5,
            'Saturday': 6,
            'Sunday': 7,
          };
          return (order[a] ?? 0).compareTo(order[b] ?? 0);
        });
    }

    if (scheduledDays is String) {
      final trimmed = scheduledDays.trim();
      final values = trimmed.startsWith('[') && trimmed.endsWith(']')
          ? trimmed.substring(1, trimmed.length - 1).split(',')
          : trimmed.split(',');

      return values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .map(_normalizeDayName)
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
    }

    if (scheduledDays is Map) {
      final dayValue = scheduledDays['day']?.toString() ?? '';
      final normalizedDay = _normalizeDayName(dayValue);
      return normalizedDay.isEmpty ? [] : [normalizedDay];
    }

    return [];
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

  void _onNavTap(int index) {
    setState(() {
      _selectedNavIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('CureNurture')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final pages = <Widget>[
      HomeTab(user: _currentUser, onScheduleTap: () => _onNavTap(1)),
      const AppointmentPage(),
      const HealthMonitoringPage(),
      ProfileTab(user: _currentUser),
    ];

    return Scaffold(
      body: pages[_selectedNavIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedNavIndex,
        onTap: _onNavTap,
        selectedItemColor: const Color(0xFF2C5F7D),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Health'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
