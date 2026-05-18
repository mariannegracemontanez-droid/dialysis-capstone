import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/signup_data.dart';
import '../../models/user_model.dart';
import '../../services/auth/auth_service.dart';
import '../../services/appointment_service.dart';
import '../../services/notification_service.dart';
import '../../services/patient_service.dart';
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
  bool _hasPatientAccess = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingApplications = [];
  RealtimeChannel? _patientChannel;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _setupPatientRealtime();
  }

  void _setupPatientRealtime() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _patientChannel = Supabase.instance.client
        .channel('patient-status-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'patients',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'profile_id',
            value: user.id,
          ),
          callback: (payload) async {
            debugPrint('Patient realtime update: ${payload.newRecord}');

            if (!mounted) return;

            await _loadUserData();
          },
        )
        .subscribe();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        setState(() {
          _currentUser = null;
          _hasPatientAccess = false;
          _pendingApplications = [];
          _isLoading = false;
        });
        return;
      }

      final access = await PatientService().hasPatientAccess(user.id);
      final pendingApplications = access
          ? <Map<String, dynamic>>[]
          : await PatientService().getPendingApplications(user.id);

      setState(() {
        _currentUser = user;
        _hasPatientAccess = access;
        _pendingApplications = pendingApplications;
        _isLoading = false;
        if (!_hasPatientAccess) {
          _selectedNavIndex = 0;
        }
      });

      if (access) {
        await _maybeCreateScheduleReminders();
      }
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
    if (!_hasPatientAccess) return;

    final reminderService = NotificationService();
    final appointmentService = AppointmentService();

    try {
      final scheduleData = await appointmentService.getMySchedule();
      final rawDays = scheduleData?['weekly_schedule']?['scheduled_days'];
      if (rawDays == null) return;

      final scheduledDays = _parseScheduledDays(rawDays);
      final now = DateTime.now();
      final today = DateFormat('EEEE').format(now);
      final tomorrow = DateFormat(
        'EEEE',
      ).format(now.add(const Duration(days: 1)));
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
    if (!_hasPatientAccess && (index == 1 || index == 2)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Schedule and Health Monitoring are available after a clinic application is approved.',
          ),
          backgroundColor: Color(0xFF3D3740),
        ),
      );
      return;
    }

    setState(() {
      _selectedNavIndex = index;
    });
  }

  SignupData _buildReapplySignupData() {
    final user = _currentUser;
    return SignupData(
      fullName: user?.fullName ?? '',
      email: user?.email ?? '',
      phone: user?.phone ?? '',
      password: '',
      profileId: user?.id ?? '',
      patientId: '',
    );
  }

  Widget _buildWaitingForApprovalTab() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Waiting for Approval',
              style: TextStyle(
                color: Color(0xFF173B4F),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your application is currently under review. You can apply to another dialysis center while you wait.',
              style: TextStyle(
                color: Color(0xFF6B7C86),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_pendingApplications.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBFD),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE1EAF0)),
                        ),
                        child: const Text(
                          'No pending applications were found. Tap the button below to start a new clinic application.',
                          style: TextStyle(
                            color: Color(0xFF5B6D7D),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Pending Clinic Applications',
                        style: TextStyle(
                          color: Color(0xFF173B4F),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ..._pendingApplications.map((application) {
                        final clinicName =
                            application['clinic_name']?.toString() ?? 'Clinic';
                        final status =
                            application['status']?.toString().toUpperCase() ??
                            'PENDING';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                clinicName,
                                style: const TextStyle(
                                  color: Color(0xFF173B4F),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Status: $status',
                                style: const TextStyle(
                                  color: Color(0xFF5B6D7D),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushNamed(
                            '/location',
                            arguments: _buildReapplySignupData(),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xFF2C5F7D),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Search another dialysis center',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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

  @override
  void dispose() {
    _patientChannel?.unsubscribe();
    super.dispose();
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
      _hasPatientAccess
          ? HomeTab(
              user: _currentUser,
              onScheduleTap: () => _onNavTap(1),
              onHealthMonitoringTap: () => _onNavTap(2),
            )
          : _buildWaitingForApprovalTab(),
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
