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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            elevation: 0,
            backgroundColor: const Color(0xFFB3261E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'We could not load your account details right now. Please try again.\n$e',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
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
      final label = index == 1 ? 'Schedule' : 'Health Monitoring';

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          elevation: 0,
          backgroundColor: const Color(0xFF173B4F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          duration: const Duration(seconds: 4),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lock_clock_outlined,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$label is not available yet',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This feature will open once your clinic application has been approved.',
                      style: TextStyle(
                        color: Color(0xFFD9EDF3),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    final firstName = (_currentUser?.fullName ?? 'Patient')
        .trim()
        .split(' ')
        .first;

    return SafeArea(
      child: Container(
        color: const Color(0xFFF3F7FA),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF225E72),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF225E72).withOpacity(0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 58,
                          width: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.hourglass_top_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hi, $firstName',
                                style: const TextStyle(
                                  color: Color(0xFFD9EDF3),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Application under review',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Your clinic application is being checked by the dialysis center. You can still search and apply to another center while waiting for approval.',
                      style: TextStyle(
                        color: Color(0xFFD9EDF3),
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'We will update your access once a clinic approves your application.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _buildApprovalInfoCard(
                      icon: Icons.manage_search_outlined,
                      title: 'Reviewing',
                      subtitle: 'Clinic staff checks your submitted details.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildApprovalInfoCard(
                      icon: Icons.lock_open_outlined,
                      title: 'Unlocks after approval',
                      subtitle: 'Schedule and health tools will be available.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pending Applications',
                      style: TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4F7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_pendingApplications.length} pending',
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
              if (_pendingApplications.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE1EAF0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.035),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        height: 60,
                        width: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4F7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.assignment_outlined,
                          color: Color(0xFF225E72),
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'No pending application found',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF173B4F),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Start a new clinic application to request access to dialysis scheduling and monitoring features.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF5B6D7D),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                )
              else
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
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE1EAF0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF4F7),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.local_hospital_outlined,
                            color: Color(0xFF225E72),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clinicName,
                                style: const TextStyle(
                                  color: Color(0xFF173B4F),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF4D8),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      status,
                                      style: const TextStyle(
                                        color: Color(0xFF8A6200),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Please wait for the clinic to review your request. You will gain access once approved.',
                                style: TextStyle(
                                  color: Color(0xFF5B6D7D),
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              const SizedBox(height: 8),
              _buildNextStepsCard(),
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/location',
                      arguments: _buildReapplySignupData(),
                    );
                  },
                  icon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                  label: const Text(
                    'Search another dialysis center',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF2C5F7D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApprovalInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4F7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF225E72), size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF173B4F),
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF5B6D7D),
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStepsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4E7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                color: Color(0xFF225E72),
                size: 22,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'What you can do while waiting',
                  style: TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStepItem(
            number: '1',
            text: 'Keep your profile information updated.',
          ),
          const SizedBox(height: 10),
          _buildStepItem(
            number: '2',
            text: 'Search another dialysis center if you need more options.',
          ),
          const SizedBox(height: 10),
          _buildStepItem(
            number: '3',
            text: 'Wait for approval to unlock schedule and health features.',
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem({required String number, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 24,
          width: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF225E72),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF5B6D7D),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
        backgroundColor: const Color(0xFFF3F7FA),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF225E72)),
                SizedBox(height: 16),
                Text(
                  'Loading your account...',
                  style: TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
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
