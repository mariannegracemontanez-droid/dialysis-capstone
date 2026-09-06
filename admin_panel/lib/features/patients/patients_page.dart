import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/patient_service.dart';
import '../../services/center_schedule_service.dart';
import '../../services/schedule_recommendation_service.dart';
import '../../models/patient.dart';
import '../../models/center_schedule.dart';
import '../../models/schedule_recommendation.dart';
import '../dashboard/dashboard_page.dart';
import '../../services/health_monitoring_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

late Future<Map<String, dynamic>?> _adminInfo;

class PatientsPage extends ConsumerStatefulWidget {
  const PatientsPage({super.key});

  @override
  ConsumerState<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends ConsumerState<PatientsPage> {
  final PatientService _service = PatientService();
  int _selectedNavIndex = 1;
  final HealthMonitoringService _healthService = HealthMonitoringService();
  final CenterScheduleService _centerScheduleService = CenterScheduleService();
  final ScheduleRecommendationService _recommendationService =
      ScheduleRecommendationService();

  /// Every patient-list section keeps a stable height of roughly ten
  /// rows and scrolls internally, so the page doesn't grow without bound
  /// as the center takes on more patients.
  static const double _listRowHeight = 58;
  static const int _visibleRows = 10;
  static const double _listMaxHeight = _listRowHeight * _visibleRows;

  final ScrollController _pendingScroll = ScrollController();
  final ScrollController _activeScroll = ScrollController();
  final ScrollController _weeklyScroll = ScrollController();
  final ScrollController _declinedScroll = ScrollController();
  // Separate controller: the medical history list can be on screen at
  // the same time as the page's own lists, and one controller cannot be
  // attached to two scroll views.
  final ScrollController _historyScroll = ScrollController();

  static const Color primary = Color(0xFF245C78);
  static const Color primaryDark = Color(0xFF153D54);
  static const Color background = Color(0xFFF4F8FB);
  static const Color cardBorder = Color(0xFFE3EAF0);
  static const Color textDark = Color(0xFF243447);
  static const Color textMuted = Color(0xFF6B7A8C);
  static const Color softBlue = Color(0xFFEAF5FA);

  late Future<List<Patient>> _pendingPatients;
  late Future<List<Patient>> _allPatients;
  late Future<List<Patient>> _declinedPatients;
  late Future<Map<String, List<WeeklyScheduleEntry>>> _weeklySchedule;

  RealtimeChannel? _patientsChannel;
  RealtimeChannel? _monitoringChannel;
  RealtimeChannel? _scheduleChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtime();
  }

  @override
  void dispose() {
    _patientsChannel?.unsubscribe();
    _monitoringChannel?.unsubscribe();
    _scheduleChannel?.unsubscribe();
    _pendingScroll.dispose();
    _activeScroll.dispose();
    _weeklyScroll.dispose();
    _declinedScroll.dispose();
    _historyScroll.dispose();
    super.dispose();
  }

  void _loadData() {
    _pendingPatients = _service.getPatientsByStatus('pending');
    _allPatients = _service.getPatientsByStatus('active');
    _declinedPatients = _service.getPatientsByStatus('declined');
    _weeklySchedule = _loadWeeklySchedule();
    _adminInfo = _service.getCurrentAdminInfo();
  }

  /// The weekly view is derived straight from the stored recurring
  /// schedules -- nothing about it is duplicated for the UI.
  Future<Map<String, List<WeeklyScheduleEntry>>> _loadWeeklySchedule() async {
    final clinicId = await _service.getCurrentClinicId();
    if (clinicId == null) return {};
    return _centerScheduleService.getWeeklyPatientSchedule(clinicId);
  }

  void _refreshData() {
    setState(() {
      _loadData();
    });
  }

  void _setupRealtime() {
    final supabase = Supabase.instance.client;

    _patientsChannel = supabase
        .channel('patients-page-patients')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'patients',
          callback: (payload) {
            if (!mounted) return;

            setState(() {
              _loadData();
            });
          },
        )
        .subscribe();

    _monitoringChannel = supabase
        .channel('patients-page-monitoring')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blood_pressure_logs',
          callback: (payload) {
            if (!mounted) return;
            setState(() {});
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'weight_logs',
          callback: (payload) {
            if (!mounted) return;
            setState(() {});
          },
        )
        .subscribe();

    // Keeps the weekly schedule view in sync when a recurring schedule
    // is created or changed anywhere in the app.
    _scheduleChannel = supabase
        .channel('patients-page-schedules')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'patient_schedule_days',
          callback: (payload) {
            if (!mounted) return;
            setState(() {
              _weeklySchedule = _loadWeeklySchedule();
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'weekly_schedules',
          callback: (payload) {
            if (!mounted) return;
            setState(() {
              _weeklySchedule = _loadWeeklySchedule();
            });
          },
        )
        .subscribe();
  }

  String _formatTime(dynamic value) {
    if (value == null) return '';
    final text = value.toString();
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  String formatDay(String? day) {
    if (day == null) return 'N/A';

    final text = day.toLowerCase();

    return text[0].toUpperCase() + text.substring(1);
  }

  String _safeText(dynamic value, {String fallback = 'N/A'}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return text;
  }

  /// Blank text fields clear the stored value rather than saving an
  /// empty string, so "not recorded" stays distinguishable from "".
  String? _nullIfBlank(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  String _getInitial(String name) {
    if (name.trim().isEmpty) return 'P';
    return name.trim()[0].toUpperCase();
  }

  String capitalizeWords(String text) {
    return text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map(
          (word) =>
              word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'N/A';

    try {
      final date = DateTime.parse(value.toString());

      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  Widget _buildNoScheduleState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: const Text(
        'No schedule set',
        style: TextStyle(color: Color(0xFF718096), fontWeight: FontWeight.w600),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Colors.red.shade600
            : const Color(0xFF2A5F7E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(18),
      ),
    );
  }

  void _showMedicalDocPreview(String fileName, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 720,
            constraints: const BoxConstraints(maxHeight: 760),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    color: const Color(0xFF2A5F7E),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            fileName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Container(
                      width: double.infinity,
                      color: const Color(0xFFF8FAFC),
                      padding: const EdgeInsets.all(18),
                      child: InteractiveViewer(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Text(
                                'Unable to preview this file.',
                                style: TextStyle(
                                  color: Color(0xFF718096),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMedicalDocsList(Patient patient) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _service.getPatientMedicalDocs(patient.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF2A5F7E)),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error);
        }

        final docs = snapshot.data ?? [];

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4EAF0)),
            ),
            child: const Text(
              'No medical documents uploaded.',
              style: TextStyle(
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4EAF0)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(bottom: BorderSide(color: Color(0xFFE4EAF0))),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        'FILE NAME',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'UPLOADED',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              ...docs.map((doc) {
                final fileName = _safeText(doc['name'] ?? doc['file_name']);

                final imageUrl = _safeText(doc['url'] ?? doc['file_url']);

                final uploadedAt = doc['uploaded_at'];

                return InkWell(
                  onTap: imageUrl == 'N/A'
                      ? null
                      : () => _showMedicalDocPreview(fileName, imageUrl),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFF1F5F9)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF3F7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.description_rounded,
                                  size: 18,
                                  color: Color(0xFF2A5F7E),
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF1E293B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),

                                    const SizedBox(height: 3),

                                    Text(
                                      imageUrl == 'N/A'
                                          ? 'Missing file'
                                          : 'Tap to preview',
                                      style: TextStyle(
                                        color: imageUrl == 'N/A'
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFF64748B),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        Expanded(
                          flex: 2,
                          child: Text(
                            uploadedAt == null
                                ? 'N/A'
                                : _formatDate(uploadedAt),
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeeklyScheduleList(Patient patient) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _service.getPatientSchedule(patient.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(color: Color(0xFF2A5F7E)),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error);
        }

        final schedules = snapshot.data ?? [];

        if (schedules.isEmpty) {
          return _buildNoScheduleState();
        }

        final dynamic rawDays = schedules.first['scheduled_days'];
        final List days = rawDays is List ? rawDays : [];

        if (days.isEmpty) {
          return _buildNoScheduleState();
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: days.map((item) {
            String day = 'N/A';
            dynamic startTime;
            dynamic endTime;

            if (item is Map) {
              day =
                  (item['day'] ??
                          item['day_of_week'] ??
                          item['scheduled_day'] ??
                          'N/A')
                      .toString();

              startTime = item['start_time'];
              endTime = item['end_time'];
            } else {
              day = item.toString();
            }

            if (day.trim().isEmpty || day.toLowerCase() == 'null') {
              day = 'N/A';
            } else {
              day = day[0].toUpperCase() + day.substring(1).toLowerCase();
            }

            final hasTime =
                startTime != null &&
                endTime != null &&
                startTime.toString().trim().isNotEmpty &&
                endTime.toString().trim().isNotEmpty &&
                startTime.toString().toLowerCase() != 'null' &&
                endTime.toString().toLowerCase() != 'null';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3F7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD7E8F0)),
              ),
              child: Text(
                hasTime
                    ? '$day • ${_formatTime(startTime)} - ${_formatTime(endTime)}'
                    : day,
                style: const TextStyle(
                  color: Color(0xFF2A5F7E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 20),
                  _buildPatientSummaryCards(),
                  const SizedBox(height: 20),
                  _buildPendingPatientsSection(),
                  const SizedBox(height: 20),
                  _buildAllPatientsSection(),
                  const SizedBox(height: 20),
                  _buildWeeklyAndDeclinedRow(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryDark, primary, Color(0xFF4FA6BC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Patients Management',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Review requests, monitor active patients, and manage clinical information in one organized workspace.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: FutureBuilder<List<Patient>>(
            future: _allPatients,
            builder: (context, snapshot) {
              return _buildSummaryCard(
                title: 'Active Patients',
                value: (snapshot.data?.length ?? 0).toString(),
                icon: Icons.verified_user_rounded,
                color: primary,
                subtitle: 'Accepted patient records',
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FutureBuilder<List<Patient>>(
            future: _pendingPatients,
            builder: (context, snapshot) {
              return _buildSummaryCard(
                title: 'Pending Requests',
                value: (snapshot.data?.length ?? 0).toString(),
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFF59E0B),
                subtitle: 'Needs admin review',
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FutureBuilder<List<Patient>>(
            future: _declinedPatients,
            builder: (context, snapshot) {
              return _buildSummaryCard(
                title: 'Declined',
                value: (snapshot.data?.length ?? 0).toString(),
                icon: Icons.person_off_rounded,
                color: const Color(0xFFEF4444),
                subtitle: 'Rejected applications',
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF91A0AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryDark, primary],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _buildLogo(),
          const SizedBox(height: 34),
          _buildNavItem(0, Icons.dashboard_rounded, 'Dashboard'),
          _buildNavItem(1, Icons.people_alt_rounded, 'Patients'),
          const Spacer(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'images/CureNurture_CircleLogo.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.local_hospital_rounded,
                  color: primary,
                  size: 29,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CureNurture',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                FutureBuilder<Map<String, dynamic>?>(
                  future: _adminInfo,
                  builder: (context, snapshot) {
                    final rawName = snapshot.data?['adminName'] ?? 'Admin';
                    final adminName = capitalizeWords(rawName.toString());

                    return Text(
                      adminName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _selectedNavIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() => _selectedNavIndex = index);

            if (index == 0) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const DashboardPage()),
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withOpacity(0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? Colors.white.withOpacity(0.22)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : Colors.white70,
                  size: 21,
                ),
                const SizedBox(width: 13),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        '© 2026 CureNurture',
        style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required Widget child,
    int? count,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: textMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count total',
                      style: TextStyle(
                        fontSize: 12,
                        color: accentColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: CircularProgressIndicator(color: Color(0xFF2A5F7E))),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFF9AA9B8)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF2D3748),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF718096), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object? error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Error loading data: $error',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingPatientsSection() {
    return FutureBuilder<List<Patient>>(
      future: _pendingPatients,
      builder: (context, snapshot) {
        final patients = snapshot.data ?? [];

        return _sectionCard(
          title: 'Pending Patient Requests',
          subtitle: 'Accept or decline new patient applications.',
          icon: Icons.pending_actions_rounded,
          accentColor: const Color(0xFFF59E0B),
          count: snapshot.hasData ? patients.length : null,
          child: Builder(
            builder: (_) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingState();
              }

              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error);
              }

              if (patients.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.mark_email_read_outlined,
                  title: 'No pending requests',
                  subtitle: 'New patient requests will appear here.',
                );
              }

              return _scrollArea(
                controller: _pendingScroll,
                child: _buildTableWrapper(
                minWidth: 980,
                child: DataTable(
                  headingRowHeight: 54,
                  dataRowMinHeight: 58,
                  dataRowMaxHeight: 64,
                  columnSpacing: 56,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF4F7FA),
                  ),
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Contact')),
                    DataColumn(label: Text('Address')),
                    DataColumn(label: Text('Action')),
                  ],
                  rows: patients.map((patient) {
                    return DataRow(
                      cells: [
                        DataCell(_buildNameCell(patient.name)),
                        DataCell(Text(patient.phone ?? patient.email)),
                        DataCell(Text(_safeText(patient.homeAddress))),
                        DataCell(
                          _actionButton(
                            label: 'View Details',
                            icon: Icons.visibility_rounded,
                            color: const Color(0xFF2A5F7E),
                            onPressed: () =>
                                _showPendingPatientDetailsModal(patient),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAllPatientsSection() {
    return FutureBuilder<List<Patient>>(
      future: _allPatients,
      builder: (context, snapshot) {
        final patients = snapshot.data ?? [];

        return _sectionCard(
          title: 'All Patients (Active)',
          subtitle: 'Click any row to view the complete patient details.',
          icon: Icons.groups_rounded,
          accentColor: const Color(0xFF2A5F7E),
          count: snapshot.hasData ? patients.length : null,
          child: Builder(
            builder: (_) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingState();
              }

              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error);
              }

              if (patients.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No active patients yet',
                  subtitle: 'Accepted patients will be listed here.',
                );
              }

              return _scrollArea(
                controller: _activeScroll,
                child: _buildTableWrapper(
                minWidth: 1120,
                child: DataTable(
                  headingRowHeight: 54,
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 66,
                  columnSpacing: 58,
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF4F7FA),
                  ),
                  dataRowColor: WidgetStateProperty.resolveWith<Color?>((
                    states,
                  ) {
                    if (states.contains(WidgetState.hovered)) {
                      return const Color(0xFFEAF3F7);
                    }
                    return null;
                  }),
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Contact')),
                    DataColumn(label: Text('Guardian')),
                    DataColumn(label: Text('Guardian Contact')),
                    DataColumn(label: Text('Weekly Schedule')),
                    DataColumn(label: Text('')),
                  ],
                  rows: patients.map((patient) {
                    return DataRow(
                      onSelectChanged: (_) => _showPatientDetailsModal(patient),
                      cells: [
                        DataCell(_buildNameCell(patient.name)),
                        DataCell(Text(patient.phone ?? patient.email)),
                        DataCell(Text(_safeText(patient.emergencyContactName))),
                        DataCell(
                          Text(_safeText(patient.emergencyContactNumber)),
                        ),
                        const DataCell(
                          Text(
                            'View details',
                            style: TextStyle(
                              color: Color(0xFF2A5F7E),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const DataCell(
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 15,
                            color: Color(0xFF9AA9B8),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDeclinedPatientsSection() {
    return FutureBuilder<List<Patient>>(
      future: _declinedPatients,
      builder: (context, snapshot) {
        final patients = snapshot.data ?? [];

        return _sectionCard(
          title: 'Declined Patients',
          subtitle: 'Patients whose requests were declined.',
          icon: Icons.person_off_rounded,
          accentColor: const Color(0xFFEF4444),
          count: snapshot.hasData ? patients.length : null,
          child: Builder(
            builder: (_) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingState();
              }

              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error);
              }

              if (patients.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'No declined patients',
                  subtitle: 'Declined patient records will appear here.',
                );
              }

              return _scrollArea(
                controller: _declinedScroll,
                child: _buildTableWrapper(
                minWidth: 420,
                child: DataTable(
                  headingRowHeight: 54,
                  dataRowMinHeight: 58,
                  dataRowMaxHeight: 64,
                  columnSpacing: 70,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF4F7FA),
                  ),
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Contact')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: patients.map((patient) {
                    return DataRow(
                      cells: [
                        DataCell(_buildNameCell(patient.name)),
                        DataCell(Text(patient.phone ?? patient.email)),
                        DataCell(_statusPill('Declined', Colors.red)),
                      ],
                    );
                  }).toList(),
                ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Keeps a list section at a stable height of about ten rows and lets
  /// it scroll internally instead of stretching the whole page. The
  /// vertical scroll here and the horizontal scroll inside
  /// [_buildTableWrapper] are on different axes, so they don't fight.
  Widget _scrollArea({
    required Widget child,
    required ScrollController controller,
    double maxHeight = _listMaxHeight,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: controller,
          physics: const ClampingScrollPhysics(),
          child: child,
        ),
      ),
    );
  }

  /// Weekly Patient Schedule (~75%) beside Declined Patients (~25%),
  /// stacking on narrower screens.
  Widget _buildWeeklyAndDeclinedRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return Column(
            children: [
              _buildWeeklyScheduleSection(),
              const SizedBox(height: 20),
              _buildDeclinedPatientsSection(),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildWeeklyScheduleSection()),
            const SizedBox(width: 20),
            Expanded(flex: 1, child: _buildDeclinedPatientsSection()),
          ],
        );
      },
    );
  }

  Widget _buildWeeklyScheduleSection() {
    return FutureBuilder<Map<String, List<WeeklyScheduleEntry>>>(
      future: _weeklySchedule,
      builder: (context, snapshot) {
        final schedule = snapshot.data ?? {};
        final total = schedule.values.fold<int>(0, (sum, l) => sum + l.length);

        return _sectionCard(
          title: 'Weekly Patient Schedule',
          subtitle:
              'Recurring dialysis days and default shifts, taken from each '
              "patient's saved schedule.",
          icon: Icons.calendar_view_week_rounded,
          accentColor: primary,
          count: snapshot.hasData ? total : null,
          child: Builder(
            builder: (_) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingState();
              }

              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error);
              }

              if (total == 0) {
                return _buildEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No recurring schedules yet',
                  subtitle:
                      'Assign a weekly schedule from the dashboard to see '
                      'patients here.',
                );
              }

              return _buildWeeklyScheduleTable(schedule);
            },
          ),
        );
      },
    );
  }

  /// Simple six-column Mon-Sat table: each column lists the patients
  /// whose recurring scheduled_days include that day, with their default
  /// shift shown beside the name.
  Widget _buildWeeklyScheduleTable(
    Map<String, List<WeeklyScheduleEntry>> schedule,
  ) {
    final days = CenterScheduleService.allDays;
    final rowCount = schedule.values.fold<int>(
      0,
      (longest, entries) => entries.length > longest ? entries.length : longest,
    );

    return _scrollArea(
      controller: _weeklyScroll,
      child: _buildTableWrapper(
        minWidth: 900,
        child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: Colors.grey.shade200),
            verticalInside: BorderSide(color: Colors.grey.shade200),
          ),
          defaultColumnWidth: const FlexColumnWidth(),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF4F7FA)),
              children: days
                  .map(
                    (day) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      child: Text(
                        day.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            for (var row = 0; row < rowCount; row++)
              TableRow(
                children: days.map((day) {
                  final entries = schedule[day] ?? const [];
                  if (row >= entries.length) {
                    return const SizedBox(height: 42);
                  }
                  return _buildWeeklyCell(entries[row]);
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyCell(WeeklyScheduleEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.patientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: textDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            entry.shiftLabel,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: entry.shiftCode.isEmpty ? textMuted : primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableWrapper({required Widget child, required int minWidth}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE4EAF0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth > minWidth
                      ? constraints.maxWidth
                      : minWidth.toDouble(),
                ),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNameCell(String name) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFEAF3F7),
          child: Text(
            _getInitial(name),
            style: const TextStyle(
              color: Color(0xFF2A5F7E),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2D3748),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _showPendingPatientDetailsModal(Patient patient) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(22),
          child: Container(
            width: 1120,
            constraints: const BoxConstraints(maxHeight: 820),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                    color: Colors.white,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Pending Patient Application',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            foregroundColor: const Color(0xFF475569),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 290,
                            child: Column(
                              children: [
                                _buildPatientProfileCard(patient),
                                const SizedBox(height: 14),
                                _buildPatientInfoMiniCard(patient),
                              ],
                            ),
                          ),

                          const SizedBox(width: 18),

                          Expanded(
                            child: Column(
                              children: [
                                _buildApplicationReviewCard(patient),
                                const SizedBox(height: 14),
                                _buildMedicalDocumentsReviewCard(patient),
                                const SizedBox(height: 14),
                                _buildAcceptanceCard(patient),
                                const SizedBox(height: 14),
                                _buildPendingDecisionPanel(patient),
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
          ),
        );
      },
    );
  }

  void _showPatientDetailsModal(Patient patient) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(22),
          child: Container(
            width: 1120,
            constraints: const BoxConstraints(maxHeight: 820),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                    color: Colors.white,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Patient Medical Profile',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            foregroundColor: const Color(0xFF475569),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 290,
                            child: Column(
                              children: [
                                _buildPatientProfileCard(patient),
                                const SizedBox(height: 14),
                                _buildPatientInfoMiniCard(patient),
                                const SizedBox(height: 14),
                                _buildPatientScheduleMiniCard(patient),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _showEditPatientModal(patient);
                                    },
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Edit Patient'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2A5F7E),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _showDeletePatientConfirmation(patient);
                                    },
                                    icon: const Icon(
                                      Icons.person_remove_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Delete Patient'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFDC2626),
                                      side: const BorderSide(
                                        color: Color(0xFFFCA5A5),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 18),

                          Expanded(
                            child: Column(
                              children: [
                                _buildPatientHealthSummaryCards(patient),
                                const SizedBox(height: 14),
                                _buildHealthMonitoringSection(patient),
                                const SizedBox(height: 18),
                                _buildMedicalHistorySection(patient),
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
          ),
        );
      },
    );
  }

  Widget _buildApplicationReviewCard(Patient patient) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.fact_check_rounded,
                color: Color(0xFF2A5F7E),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Application Review',
                style: TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Review the submitted patient profile and clinical information before accepting the application.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _reviewSummaryTile(
                  icon: Icons.person_rounded,
                  label: 'Patient',
                  value: patient.name,
                  color: const Color(0xFF2A5F7E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _reviewSummaryTile(
                  icon: Icons.bloodtype_rounded,
                  label: 'Blood Type',
                  value: _safeText(patient.bloodType),
                  color: const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _reviewSummaryTile(
                  icon: Icons.medical_services_rounded,
                  label: 'Dialysis Stage',
                  value: _safeText(patient.dialysisStage),
                  color: const Color(0xFF8E44AD),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFEA580C),
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Make sure the patient details and uploaded documents are valid before approving this request.',
                    style: TextStyle(
                      color: Color(0xFF9A3412),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewSummaryTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalDocumentsReviewCard(Patient patient) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.folder_copy_rounded,
                color: Color(0xFF2A5F7E),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Medical Documents',
                style: TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Open each submitted file to verify patient requirements.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _buildMedicalDocsList(patient),
        ],
      ),
    );
  }

  Future<AcceptanceEvaluation?> _evaluateAcceptance(Patient patient) async {
    final clinicId = patient.clinicId ?? await _service.getCurrentClinicId();
    if (clinicId == null) return null;

    return _recommendationService.evaluateAcceptance(
      patientId: patient.id,
      clinicId: clinicId,
    );
  }

  /// Capacity-based acceptance guidance, produced by the same engine that
  /// generates schedule recommendations -- so it can never say the center
  /// can take a patient the scheduler then fails to place. Advisory only:
  /// the Accept/Decline decision stays with the admin below.
  Widget _buildAcceptanceCard(Patient patient) {
    return FutureBuilder<AcceptanceEvaluation?>(
      future: _evaluateAcceptance(patient),
      builder: (context, snapshot) {
        final evaluation = snapshot.data;

        Color accent;
        IconData icon;
        String headline;
        String detail;

        if (snapshot.connectionState == ConnectionState.waiting) {
          accent = textMuted;
          icon = Icons.hourglass_top_rounded;
          headline = 'Checking center capacity...';
          detail = "Analyzing this center's weekly schedule and shift capacity.";
        } else if (snapshot.hasError || evaluation == null) {
          accent = textMuted;
          icon = Icons.help_outline_rounded;
          headline = 'Capacity check unavailable';
          detail =
              "The center's schedule configuration could not be read, so "
              'capacity could not be evaluated.';
        } else {
          switch (evaluation.verdict) {
            case AcceptanceVerdict.canAccommodate:
              accent = const Color(0xFF16A34A);
              icon = Icons.verified_rounded;
              break;
            case AcceptanceVerdict.reviewRequired:
              accent = const Color(0xFFF59E0B);
              icon = Icons.info_rounded;
              break;
            case AcceptanceVerdict.cannotAccommodate:
              accent = const Color(0xFFEF4444);
              icon = Icons.report_problem_rounded;
              break;
          }
          headline = evaluation.headline;
          detail = evaluation.detail;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Center Capacity Assessment',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: textMuted,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          headline,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 13,
                  color: textMuted,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (evaluation?.suggestion != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: evaluation!.suggestion!.days
                      .map(
                        (day) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: softBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            day,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Indicative only. The schedule and its default shift are '
                  'chosen when the patient is actually scheduled.',
                  style: TextStyle(fontSize: 11, color: textMuted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingDecisionPanel(Patient patient) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Final Decision',
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Accepting the patient will move them to active records and schedule assignment.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                _confirmPendingDecision(patient: patient, isAccept: false),
            icon: const Icon(Icons.close_rounded, size: 17),
            label: const Text('Decline'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: const BorderSide(color: Color(0xFFFCA5A5)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () =>
                _confirmPendingDecision(patient: patient, isAccept: true),
            icon: const Icon(Icons.check_rounded, size: 17),
            label: const Text('Accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientProfileCard(Patient patient) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3F7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                _getInitial(patient.name),
                style: const TextStyle(
                  color: Color(0xFF2A5F7E),
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            patient.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            patient.email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _profileSmallBadge(
            Icons.medical_information_rounded,
            _safeText(patient.dialysisStage),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientInfoMiniCard(Patient patient) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Information',
            style: TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          _infoLine('Phone', _safeText(patient.phone)),
          _infoLine('Blood Type', _safeText(patient.bloodType)),
          _infoLine(
            'Date of Birth',
            patient.birthDate?.toString().split(' ')[0] ?? 'N/A',
          ),
          _infoLine('Condition', _safeText(patient.existingCondition)),
          _infoLine('Guardian', _safeText(patient.emergencyContactName)),
          _infoLine(
            'Guardian Contact',
            _safeText(patient.emergencyContactNumber),
          ),
          _infoLine('Address', _safeText(patient.homeAddress)),
        ],
      ),
    );
  }

  Widget _buildPatientScheduleMiniCard(Patient patient) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: Color(0xFF2A5F7E),
              ),
              SizedBox(width: 8),
              Text(
                'Weekly Schedule',
                style: TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildWeeklyScheduleList(patient),
        ],
      ),
    );
  }

  Widget _buildPatientHealthSummaryCards(Patient patient) {
    return FutureBuilder(
      future: Future.wait([
        _healthService.getLatestBloodPressure(patientId: patient.id),
        _healthService.getLatestWeight(patientId: patient.id),
      ]),
      builder: (context, snapshot) {
        final data = snapshot.data ?? [];

        final bp = data.isNotEmpty ? data[0] : null;
        final weight = data.length > 1 ? data[1] : null;

        final latestBp = bp == null
            ? 'No record'
            : '${bp['systolic']}/${bp['diastolic']}';

        final latestWeight = weight == null
            ? 'No record'
            : '${weight['after_weight']} kg';

        return Row(
          children: [
            Expanded(
              child: _healthSummaryCard(
                icon: Icons.favorite_rounded,
                label: 'Blood Pressure',
                value: latestBp,
                unit: bp == null ? '' : 'mmHg',
                color: const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _healthSummaryCard(
                icon: Icons.monitor_weight_rounded,
                label: 'Latest Weight',
                value: latestWeight,
                unit: '',
                color: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _healthSummaryCard(
                icon: Icons.water_drop_rounded,
                label: 'Blood Type',
                value: _safeText(patient.bloodType),
                unit: '',
                color: const Color(0xFF2A5F7E),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _healthSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      height: 126,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileSmallBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD7E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF2A5F7E)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF2A5F7E),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientModalHeader(Patient patient) {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                _getInitial(patient.name),
                style: const TextStyle(
                  color: Color(0xFF2A5F7E),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  patient.email,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _profileBadge(
                      Icons.bloodtype_rounded,
                      _safeText(patient.bloodType),
                    ),
                    _profileBadge(
                      Icons.medical_information_rounded,
                      _safeText(patient.dialysisStage),
                    ),
                    _profileBadge(
                      Icons.phone_rounded,
                      _safeText(patient.phone),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1F5F9),
              foregroundColor: const Color(0xFF475569),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F7FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDEAF0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF2A5F7E)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF2A5F7E),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientInfoSection(Patient patient) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Patient Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Complete patient profile, medical details, and emergency contact information.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: _profilePanel(
                title: 'Personal Details',
                icon: Icons.person_rounded,
                children: [
                  _profileInfoRow(
                    Icons.email_rounded,
                    'Email',
                    _safeText(patient.email),
                  ),
                  _profileInfoRow(
                    Icons.phone_rounded,
                    'Phone',
                    _safeText(patient.phone),
                  ),
                  _profileInfoRow(
                    Icons.cake_rounded,
                    'Date of Birth',
                    patient.birthDate?.toString().split(' ')[0] ?? 'N/A',
                  ),
                  _profileInfoRow(
                    Icons.location_on_rounded,
                    'Address',
                    _safeText(patient.homeAddress),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _profilePanel(
                    title: 'Clinical Details',
                    icon: Icons.medical_services_rounded,
                    children: [
                      _profileInfoRow(
                        Icons.bloodtype_rounded,
                        'Blood Type',
                        _safeText(patient.bloodType),
                      ),
                      _profileInfoRow(
                        Icons.local_hospital_rounded,
                        'Dialysis Stage',
                        _safeText(patient.dialysisStage),
                      ),
                      _profileInfoRow(
                        Icons.health_and_safety_rounded,
                        'Existing Condition',
                        _safeText(patient.existingCondition),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _profilePanel(
                    title: 'Emergency Contact',
                    icon: Icons.emergency_rounded,
                    children: [
                      _profileInfoRow(
                        Icons.family_restroom_rounded,
                        'Guardian',
                        _safeText(patient.emergencyContactName),
                      ),
                      _profileInfoRow(
                        Icons.contact_phone_rounded,
                        'Guardian Contact',
                        _safeText(patient.emergencyContactNumber),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Dated medical change history for the patient. Read-only: rows are
  /// written by the database trigger whenever a medical field changes,
  /// so nothing here can be edited or removed from the app.
  Widget _buildMedicalHistorySection(Patient patient) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _service.getMedicalHistory(patient.id),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Medical Information History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Every recorded change to this patient\'s medical and '
              'scheduling information, newest first.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              _buildLoadingState()
            else if (snapshot.hasError)
              _buildErrorState(snapshot.error)
            else if (entries.isEmpty)
              _buildEmptyState(
                icon: Icons.history_rounded,
                title: 'No recorded changes yet',
                subtitle:
                    'Updates to dialysis stage, condition, blood type or '
                    'required sessions will be listed here.',
              )
            else
              _scrollArea(
                controller: _historyScroll,
                maxHeight: 320,
                child: Column(
                  children: entries.map(_buildMedicalHistoryRow).toList(),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMedicalHistoryRow(Map<String, dynamic> entry) {
    final createdAt = DateTime.tryParse(entry['created_at']?.toString() ?? '');
    final oldValue = _safeText(entry['old_value'], fallback: 'Not set');
    final newValue = _safeText(entry['new_value'], fallback: 'Not set');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _safeText(entry['field'], fallback: 'Medical information'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
              ),
              Text(
                createdAt == null
                    ? ''
                    : '${createdAt.toLocal()}'.split('.').first,
                style: const TextStyle(fontSize: 11, color: textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  oldValue,
                  style: const TextStyle(
                    fontSize: 12,
                    color: textMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  newValue,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profilePanel({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: const Color(0xFF2A5F7E)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _profileInfoRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF2A5F7E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGroup({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primary, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final useThreeColumns = constraints.maxWidth >= 880;
              final useTwoColumns = constraints.maxWidth >= 560;
              final columns = useThreeColumns
                  ? 3
                  : useTwoColumns
                  ? 2
                  : 1;
              final spacing = 12.0;
              final width =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: 12,
                children: children.map((child) {
                  return SizedBox(width: width, child: child);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHealthMonitoringSection(Patient patient) {
    return FutureBuilder(
      future: Future.wait([
        _healthService.getLatestBloodPressure(patientId: patient.id),
        _healthService.getLatestWeight(patientId: patient.id),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data ?? [];

        final bp = data.isNotEmpty ? data[0] : null;
        final weight = data.length > 1 ? data[1] : null;

        String latestBp = 'No record yet';

        if (bp != null) {
          latestBp = '${bp['systolic']}/${bp['diastolic']} mmHg';
        }

        String latestWeight = 'No record yet';

        if (weight != null) {
          latestWeight = '${weight['after_weight']} kg';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.monitor_heart_rounded,
                  color: Color(0xFF2A5F7E),
                  size: 21,
                ),
                SizedBox(width: 8),
                Text(
                  'Health Monitoring',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: Color(0xFF26364A),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),
            const Text(
              'Track blood pressure and dialysis weight records per session.',
              style: TextStyle(
                color: Color(0xFF718096),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildHealthMonitoringCard(
                    icon: Icons.favorite_rounded,
                    title: 'Blood Pressure Monitoring',
                    subtitle: 'Record systolic and diastolic BP every session.',
                    latestLabel: 'Latest BP',
                    latestValue: latestBp,
                    buttonLabel: 'Add BP Record',
                    accentColor: const Color(0xFFEF4444),
                    onPressed: () {
                      _showAddBloodPressureModal(patient);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildHealthMonitoringCard(
                    icon: Icons.monitor_weight_rounded,
                    title: 'Weight Monitoring',
                    subtitle: 'Record before and after dialysis weight.',
                    latestLabel: 'Latest Weight',
                    latestValue: latestWeight,
                    buttonLabel: 'Add Weight Record',
                    accentColor: const Color(0xFF2563EB),
                    onPressed: () {
                      _showAddWeightModal(patient);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _buildBloodPressureRecords(patient),

            const SizedBox(height: 22),
            _buildBloodPressureChart(patient),

            const SizedBox(height: 18),
            _buildWeightRecords(patient),

            const SizedBox(height: 22),
            _buildWeightChart(patient),
          ],
        );
      },
    );
  }

  void _showEditPatientModal(Patient patient) {
    final emailController = TextEditingController(text: patient.email);
    final phoneController = TextEditingController(text: patient.phone ?? '');
    final addressController = TextEditingController(
      text: patient.homeAddress ?? patient.address ?? '',
    );
    final guardianNameController = TextEditingController(
      text: patient.emergencyContactName ?? '',
    );
    final guardianContactController = TextEditingController(
      text: patient.emergencyContactNumber ?? '',
    );
    final dialysisStageController = TextEditingController(
      text: patient.dialysisStage ?? '',
    );
    final existingConditionController = TextEditingController(
      text: patient.existingCondition ?? '',
    );
    final sessionsController = TextEditingController();

    // Required sessions/week lives on the patient record and drives both
    // schedule validation and the recommendation, so it's loaded on open
    // rather than re-typed from memory.
    _centerScheduleService.getSessionsPerWeek(patient.id).then((value) {
      if (value != null) sessionsController.text = value.toString();
    });

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 720,
            constraints: const BoxConstraints(maxHeight: 720),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Edit Patient Information',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF26364A),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Locked Information',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Color(0xFF26364A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLockedField('Name', patient.name),
                    _buildLockedField(
                      'Date of Birth',
                      patient.birthDate?.toString().split(' ')[0] ?? 'N/A',
                    ),
                    _buildLockedField(
                      'Blood Type',
                      _safeText(patient.bloodType),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Editable Information',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Color(0xFF26364A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildEditField(
                      label: 'Email',
                      controller: emailController,
                      icon: Icons.email_rounded,
                    ),
                    _buildEditField(
                      label: 'Phone',
                      controller: phoneController,
                      icon: Icons.phone_rounded,
                    ),
                    _buildEditField(
                      label: 'Address',
                      controller: addressController,
                      icon: Icons.location_on_rounded,
                      maxLines: 2,
                    ),
                    _buildEditField(
                      label: 'Emergency Contact Name',
                      controller: guardianNameController,
                      icon: Icons.family_restroom_rounded,
                    ),
                    _buildEditField(
                      label: 'Emergency Contact Number',
                      controller: guardianContactController,
                      icon: Icons.contact_phone_rounded,
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Medical & Dialysis Information',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Color(0xFF26364A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Every change here is kept in the patient\'s medical '
                      'history with a timestamp -- previous values are never '
                      'erased.',
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    const SizedBox(height: 12),
                    _buildEditField(
                      label: 'Dialysis Stage',
                      controller: dialysisStageController,
                      icon: Icons.local_hospital_rounded,
                    ),
                    _buildEditField(
                      label: 'Existing Condition',
                      controller: existingConditionController,
                      icon: Icons.health_and_safety_rounded,
                      maxLines: 2,
                    ),
                    _buildEditField(
                      label: 'Required Sessions per Week (1-6)',
                      controller: sessionsController,
                      icon: Icons.event_repeat_rounded,
                    ),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final sessionsText = sessionsController.text.trim();
                            int? sessions;

                            if (sessionsText.isNotEmpty) {
                              sessions = int.tryParse(sessionsText);
                              if (sessions == null ||
                                  sessions < 1 ||
                                  sessions > 6) {
                                _showMessage(
                                  'Required sessions per week must be a '
                                  'number between 1 and 6.',
                                  isError: true,
                                );
                                return;
                              }
                            }

                            try {
                              await _service.updatePatientInfo(
                                patientId: patient.id,
                                email: emailController.text.trim(),
                                phone: phoneController.text.trim(),
                                homeAddress: addressController.text.trim(),
                                emergencyContactName: guardianNameController
                                    .text
                                    .trim(),
                                emergencyContactNumber:
                                    guardianContactController.text.trim(),
                                includeMedicalFields: true,
                                dialysisStage: _nullIfBlank(
                                  dialysisStageController.text,
                                ),
                                existingCondition: _nullIfBlank(
                                  existingConditionController.text,
                                ),
                                sessionsPerWeek: sessions,
                              );

                              if (!mounted) return;

                              Navigator.pop(context);
                              _refreshData();
                              _showMessage('Patient information updated');
                            } catch (e) {
                              _showMessage('Error: $e', isError: true);
                            }
                          },
                          icon: const Icon(Icons.save_rounded, size: 17),
                          label: const Text('Save Changes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A5F7E),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHealthMonitoringCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String latestLabel,
    required String latestValue,
    required String buttonLabel,
    required Color accentColor,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF26364A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF718096),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4EAF0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latestLabel,
                  style: const TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  latestValue,
                  style: const TextStyle(
                    color: Color(0xFF26364A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A5F7E),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartContainer({
    required String title,
    required String subtitle,
    required Widget child,
    required String analysis,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_rounded,
                color: Color(0xFF2A5F7E),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Color(0xFF26364A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF718096),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          child,
          const SizedBox(height: 18),
          _buildAnalysisBox(analysis),
        ],
      ),
    );
  }

  Widget _buildAnalysisBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF2A5F7E),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF2A5F7E),
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartEmptyState({
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.show_chart_rounded,
            color: Color(0xFF9AA9B8),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF26364A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF718096),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloodPressureRecords(Patient patient) {
    return FutureBuilder<List<dynamic>>(
      future: _healthService.getBloodPressureLogs(patientId: patient.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final records = snapshot.data ?? [];

        if (records.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4EAF0)),
            ),
            child: const Text(
              'No blood pressure records yet.',
              style: TextStyle(
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4EAF0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    color: Color(0xFF2A5F7E),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Recent Blood Pressure Records',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Color(0xFF26364A),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              ...records.reversed.take(5).map((record) {
                final systolic = record['systolic']?.toString() ?? '-';

                final diastolic = record['diastolic']?.toString() ?? '-';

                final date = record['session_date']?.toString() ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4EAF0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Color(0xFFEF4444),
                        ),
                      ),

                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$systolic / $diastolic mmHg',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF26364A),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              date,
                              style: const TextStyle(
                                color: Color(0xFF718096),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF3F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _healthService.analyzeBloodPressure(
                            systolic: int.tryParse(systolic) ?? 0,
                            diastolic: int.tryParse(diastolic) ?? 0,
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2A5F7E),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBloodPressureChart(Patient patient) {
    return FutureBuilder<List<dynamic>>(
      future: _healthService.getBloodPressureLogs(patientId: patient.id),
      builder: (context, snapshot) {
        final records = snapshot.data ?? [];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (records.length < 2) {
          return _buildChartEmptyState(
            title: 'Blood Pressure Chart',
            message: 'At least 2 BP records are needed to show a trend chart.',
          );
        }

        final sorted = [...records];
        sorted.sort((a, b) {
          return a['session_date'].toString().compareTo(
            b['session_date'].toString(),
          );
        });

        final systolicSpots = <FlSpot>[];
        final diastolicSpots = <FlSpot>[];

        for (int i = 0; i < sorted.length; i++) {
          systolicSpots.add(
            FlSpot(
              i.toDouble(),
              double.tryParse(sorted[i]['systolic'].toString()) ?? 0,
            ),
          );

          diastolicSpots.add(
            FlSpot(
              i.toDouble(),
              double.tryParse(sorted[i]['diastolic'].toString()) ?? 0,
            ),
          );
        }

        final latest = sorted.last;
        final latestSystolic = int.tryParse(latest['systolic'].toString()) ?? 0;
        final latestDiastolic =
            int.tryParse(latest['diastolic'].toString()) ?? 0;

        return _buildChartContainer(
          title: 'Blood Pressure Trend',
          subtitle: 'Systolic and diastolic readings per dialysis session.',
          child: SizedBox(
            height: 260,
            child: LineChart(
              LineChartData(
                minY: 40,
                maxY: 200,
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();

                        if (index < 0 || index >= sorted.length) {
                          return const SizedBox.shrink();
                        }

                        final date = sorted[index]['session_date'].toString();

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            date.length >= 10 ? date.substring(5, 10) : date,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF718096),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 42),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: const Color(0xFFE4EAF0)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: systolicSpots,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    color: const Color(0xFFEF4444),
                  ),
                  LineChartBarData(
                    spots: diastolicSpots,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    color: const Color(0xFF2563EB),
                  ),
                ],
              ),
            ),
          ),
          analysis: _healthService.analyzeBloodPressure(
            systolic: latestSystolic,
            diastolic: latestDiastolic,
          ),
        );
      },
    );
  }

  Widget _buildWeightRecords(Patient patient) {
    return FutureBuilder<List<dynamic>>(
      future: _healthService.getWeightLogs(patientId: patient.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final records = snapshot.data ?? [];

        if (records.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4EAF0)),
            ),
            child: const Text(
              'No weight records yet.',
              style: TextStyle(
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4EAF0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.monitor_weight_rounded,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Recent Weight Records',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Color(0xFF26364A),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              ...records.reversed.take(5).map((record) {
                final before = record['before_weight']?.toString() ?? '-';

                final after = record['after_weight']?.toString() ?? '-';

                final date = record['session_date']?.toString() ?? '';

                final beforeDouble = double.tryParse(before) ?? 0;

                final afterDouble = double.tryParse(after) ?? 0;

                final difference = (beforeDouble - afterDouble).toStringAsFixed(
                  1,
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4EAF0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.monitor_weight_rounded,
                          color: Color(0xFF2563EB),
                        ),
                      ),

                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Before: $before kg • After: $after kg',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF26364A),
                                fontSize: 14,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              'Weight Removed: $difference kg',
                              style: const TextStyle(
                                color: Color(0xFF2563EB),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              date,
                              style: const TextStyle(
                                color: Color(0xFF718096),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF3F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _healthService.analyzeWeightDifference(
                            beforeWeight: beforeDouble,
                            afterWeight: afterDouble,
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2A5F7E),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeightChart(Patient patient) {
    return FutureBuilder<List<dynamic>>(
      future: _healthService.getWeightLogs(patientId: patient.id),
      builder: (context, snapshot) {
        final records = snapshot.data ?? [];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (records.length < 2) {
          return _buildChartEmptyState(
            title: 'Weight Chart',
            message:
                'At least 2 weight records are needed to show a trend chart.',
          );
        }

        final sorted = [...records];
        sorted.sort((a, b) {
          return a['session_date'].toString().compareTo(
            b['session_date'].toString(),
          );
        });

        final beforeSpots = <FlSpot>[];
        final afterSpots = <FlSpot>[];

        for (int i = 0; i < sorted.length; i++) {
          beforeSpots.add(
            FlSpot(
              i.toDouble(),
              double.tryParse(sorted[i]['before_weight'].toString()) ?? 0,
            ),
          );

          afterSpots.add(
            FlSpot(
              i.toDouble(),
              double.tryParse(sorted[i]['after_weight'].toString()) ?? 0,
            ),
          );
        }

        final latest = sorted.last;

        final beforeWeight =
            double.tryParse(latest['before_weight'].toString()) ?? 0;

        final afterWeight =
            double.tryParse(latest['after_weight'].toString()) ?? 0;

        final minY =
            sorted
                .map((e) => double.tryParse(e['after_weight'].toString()) ?? 0)
                .reduce((a, b) => a < b ? a : b) -
            5;

        final maxY =
            sorted
                .map((e) => double.tryParse(e['before_weight'].toString()) ?? 0)
                .reduce((a, b) => a > b ? a : b) +
            5;

        return _buildChartContainer(
          title: 'Weight Monitoring Trend',
          subtitle: 'Before and after dialysis weight per session.',
          child: SizedBox(
            height: 260,
            child: LineChart(
              LineChartData(
                minY: minY < 0 ? 0 : minY,
                maxY: maxY,
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();

                        if (index < 0 || index >= sorted.length) {
                          return const SizedBox.shrink();
                        }

                        final date = sorted[index]['session_date'].toString();

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            date.length >= 10 ? date.substring(5, 10) : date,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF718096),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 42),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: const Color(0xFFE4EAF0)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: beforeSpots,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    color: const Color(0xFF2563EB),
                  ),
                  LineChartBarData(
                    spots: afterSpots,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    color: const Color(0xFF16A34A),
                  ),
                ],
              ),
            ),
          ),
          analysis: _healthService.analyzeWeightDifference(
            beforeWeight: beforeWeight,
            afterWeight: afterWeight,
          ),
        );
      },
    );
  }

  void _showAddBloodPressureModal(Patient patient) {
    final systolicController = TextEditingController();
    final diastolicController = TextEditingController();
    final notesController = TextEditingController();

    DateTime selectedDate = DateTime.now();

    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.favorite_rounded,
                          color: Color(0xFFEF4444),
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Add Blood Pressure Record',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF26364A),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      patient.name,
                      style: const TextStyle(
                        color: Color(0xFF718096),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Session Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF26364A),
                      ),
                    ),

                    const SizedBox(height: 8),

                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2100),
                        );

                        if (picked != null) {
                          setModalState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE4EAF0)),
                        ),
                        child: Text(
                          selectedDate.toString().split(' ')[0],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF26364A),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: _buildEditField(
                            label: 'Systolic',
                            controller: systolicController,
                            icon: Icons.favorite_rounded,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildEditField(
                            label: 'Diastolic',
                            controller: diastolicController,
                            icon: Icons.favorite_border_rounded,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    _buildEditField(
                      label: 'Notes (Optional)',
                      controller: notesController,
                      icon: Icons.notes_rounded,
                      maxLines: 3,
                    ),

                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),

                        const SizedBox(width: 10),

                        ElevatedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final systolic = int.tryParse(
                                    systolicController.text.trim(),
                                  );

                                  final diastolic = int.tryParse(
                                    diastolicController.text.trim(),
                                  );

                                  if (systolic == null || diastolic == null) {
                                    _showMessage(
                                      'Please enter valid BP values.',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  try {
                                    setModalState(() {
                                      isSaving = true;
                                    });

                                    final clinicId = await _service
                                        .getCurrentClinicId();

                                    if (clinicId == null) {
                                      throw Exception('No clinic found.');
                                    }

                                    await _healthService.addBloodPressureLog(
                                      patientId: patient.id,
                                      clinicId: clinicId,
                                      sessionDate: selectedDate
                                          .toIso8601String()
                                          .split('T')[0],
                                      systolic: systolic,
                                      diastolic: diastolic,
                                      notes: notesController.text.trim(),
                                    );

                                    if (!mounted) return;

                                    Navigator.pop(dialogContext);

                                    _showMessage(
                                      'Blood pressure record added.',
                                    );

                                    setState(() {});
                                  } catch (e) {
                                    _showMessage('Error: $e', isError: true);
                                  } finally {
                                    if (mounted) {
                                      setModalState(() {
                                        isSaving = false;
                                      });
                                    }
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 17),
                          label: Text(isSaving ? 'Saving...' : 'Save Record'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A5F7E),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddWeightModal(Patient patient) {
    final beforeController = TextEditingController();
    final afterController = TextEditingController();
    final notesController = TextEditingController();

    DateTime selectedDate = DateTime.now();

    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.monitor_weight_rounded,
                          color: Color(0xFF2563EB),
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Add Weight Record',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF26364A),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      patient.name,
                      style: const TextStyle(
                        color: Color(0xFF718096),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Session Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF26364A),
                      ),
                    ),

                    const SizedBox(height: 8),

                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2100),
                        );

                        if (picked != null) {
                          setModalState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE4EAF0)),
                        ),
                        child: Text(
                          selectedDate.toString().split(' ')[0],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF26364A),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: _buildEditField(
                            label: 'Before Dialysis (kg)',
                            controller: beforeController,
                            icon: Icons.scale_rounded,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildEditField(
                            label: 'After Dialysis (kg)',
                            controller: afterController,
                            icon: Icons.monitor_weight_rounded,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    _buildEditField(
                      label: 'Notes (Optional)',
                      controller: notesController,
                      icon: Icons.notes_rounded,
                      maxLines: 3,
                    ),

                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),

                        const SizedBox(width: 10),

                        ElevatedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final beforeWeight = double.tryParse(
                                    beforeController.text.trim(),
                                  );

                                  final afterWeight = double.tryParse(
                                    afterController.text.trim(),
                                  );

                                  if (beforeWeight == null ||
                                      afterWeight == null) {
                                    _showMessage(
                                      'Please enter valid weights.',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  try {
                                    setModalState(() {
                                      isSaving = true;
                                    });

                                    final clinicId = await _service
                                        .getCurrentClinicId();

                                    if (clinicId == null) {
                                      throw Exception('No clinic found.');
                                    }

                                    await _healthService.addWeightLog(
                                      patientId: patient.id,
                                      clinicId: clinicId,
                                      sessionDate: selectedDate
                                          .toIso8601String()
                                          .split('T')[0],
                                      beforeWeight: beforeWeight,
                                      afterWeight: afterWeight,
                                      notes: notesController.text.trim(),
                                    );

                                    if (!mounted) return;

                                    Navigator.pop(dialogContext);

                                    _showMessage('Weight record added.');

                                    setState(() {});
                                  } catch (e) {
                                    _showMessage('Error: $e', isError: true);
                                  } finally {
                                    if (mounted) {
                                      setModalState(() {
                                        isSaving = false;
                                      });
                                    }
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 17),
                          label: Text(isSaving ? 'Saving...' : 'Save Record'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A5F7E),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLockedField(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 18, color: Color(0xFF9AA9B8)),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Color(0xFF718096),
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF26364A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF2A5F7E)),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4EAF0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4EAF0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A5F7E), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: softBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primary, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptPatient(Patient patient) async {
    try {
      await _service.acceptPatient(patient.id);
      _refreshData();
      _showMessage('Patient accepted, awaiting schedule');
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }
  }

  Future<void> _confirmPendingDecision({
    required Patient patient,
    required bool isAccept,
  }) async {
    if (isAccept) {
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (confirmContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
                SizedBox(width: 10),
                Text('Accept Patient?'),
              ],
            ),
            content: Text(
              'Please make sure you have carefully reviewed ${patient.name}’s patient details and medical requirements before you accept this request.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(confirmContext).pop(false),
                child: const Text('Review Again'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(confirmContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Accept'),
              ),
            ],
          );
        },
      );

      if (confirm != true) return;

      try {
        await _service.acceptPatient(patient.id);
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        _refreshData();
        _showMessage('Patient accepted, awaiting schedule');
      } catch (e) {
        _showMessage('Error: $e', isError: true);
      }
      return;
    }

    await _showDeclinePatientConfirmation(patient);
  }

  Future<void> _showDeclinePatientConfirmation(Patient patient) async {
    final reasonController = TextEditingController();
    bool isSaving = false;
    String? errorText;

    final declined = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 560,
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.person_off_rounded,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Decline Patient Request',
                                style: TextStyle(
                                  color: Color(0xFF1E293B),
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                patient.name,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Reason for declining',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText:
                            'Example: Submitted documents are incomplete or requirements were not verified.',
                        hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                        errorText: errorText,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A5F7E),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: const Text(
                        'This reason will be saved in the patient record and can be shown in the mobile app.',
                        style: TextStyle(
                          color: Color(0xFF9A3412),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving
                                ? null
                                : () => Navigator.of(dialogContext).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Review Again'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final reason = reasonController.text.trim();

                                    if (reason.isEmpty) {
                                      setModalState(() {
                                        errorText =
                                            'Decline reason is required.';
                                      });
                                      return;
                                    }

                                    try {
                                      setModalState(() {
                                        isSaving = true;
                                        errorText = null;
                                      });

                                      final clinicId = await _service
                                          .getCurrentClinicId();

                                      if (clinicId == null) {
                                        throw Exception(
                                          'No clinic assigned to this admin account.',
                                        );
                                      }

                                      await Supabase.instance.client
                                          .from('patients')
                                          .update({
                                            'status': 'declined',
                                            'decline_reason': reason,
                                          })
                                          .eq('id', patient.id)
                                          .eq('clinic_id', clinicId);

                                      if (!mounted) return;
                                      Navigator.of(dialogContext).pop(true);
                                    } catch (e) {
                                      setModalState(() {
                                        isSaving = false;
                                        errorText = 'Unable to save reason.';
                                      });
                                      _showMessage('Error: $e', isError: true);
                                    }
                                  },
                            icon: isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.close_rounded, size: 17),
                            label: Text(isSaving ? 'Saving...' : 'Decline'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    reasonController.dispose();

    if (declined == true) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _refreshData();
      _showMessage('Patient declined and reason was saved.');
    }
  }

  Future<void> _showDeletePatientConfirmation(Patient patient) async {
    final notesController = TextEditingController();
    String? selectedReason;
    String? reasonError;
    String? notesError;
    bool isSaving = false;

    const deletionReasons = [
      'Transferred to another dialysis center',
      'Change of treatment modality (e.g., switched to home dialysis or transplant)',
      'Kidney transplant completed',
      'Physician recommended transfer to another facility/hospital',
      'Patient accepted to another center',
      'Deceased',
      'Others',
    ];

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 640,
                constraints: const BoxConstraints(maxHeight: 760),
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.person_remove_rounded,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Delete Patient Record',
                                  style: TextStyle(
                                    color: Color(0xFF1E293B),
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  patient.name,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Text(
                          'This will remove the patient from the active list by changing the status to deleted. The reason and deletion time will remain saved for records and review.',
                          style: TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Reason category',
                        style: TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: deletionReasons.map((reason) {
                          final isSelected = selectedReason == reason;
                          return ChoiceChip(
                            label: Text(reason),
                            selected: isSelected,
                            onSelected: isSaving
                                ? null
                                : (_) {
                                    setModalState(() {
                                      selectedReason = reason;
                                      reasonError = null;
                                    });
                                  },
                            selectedColor: const Color(0xFFEAF3F7),
                            backgroundColor: const Color(0xFFF8FAFC),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF2A5F7E)
                                  : const Color(0xFFE2E8F0),
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF2A5F7E)
                                  : const Color(0xFF334155),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          );
                        }).toList(),
                      ),
                      if (reasonError != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          reasonError!,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const Text(
                        'Detailed reason',
                        style: TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText:
                              'Add details or supporting notes for this patient removal.',
                          hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                          errorText: notesError,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF2A5F7E),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving
                                  ? null
                                  : () =>
                                        Navigator.of(dialogContext).pop(false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final category = selectedReason;
                                      final notes = notesController.text.trim();

                                      if (category == null) {
                                        setModalState(() {
                                          reasonError =
                                              'Please select a reason category.';
                                        });
                                        return;
                                      }

                                      if (notes.isEmpty) {
                                        setModalState(() {
                                          notesError =
                                              'Detailed reason is required.';
                                        });
                                        return;
                                      }

                                      final finalReason = category == 'Others'
                                          ? notes
                                          : '$category - $notes';

                                      try {
                                        setModalState(() {
                                          isSaving = true;
                                          reasonError = null;
                                          notesError = null;
                                        });

                                        final clinicId = await _service
                                            .getCurrentClinicId();

                                        if (clinicId == null) {
                                          throw Exception(
                                            'No clinic assigned to this admin account.',
                                          );
                                        }

                                        await Supabase.instance.client
                                            .from('patients')
                                            .update({
                                              'status': 'deleted',
                                              'delete_reason': finalReason,
                                              'deleted_at': DateTime.now()
                                                  .toIso8601String(),
                                            })
                                            .eq('id', patient.id)
                                            .eq('clinic_id', clinicId);

                                        if (!mounted) return;
                                        Navigator.of(dialogContext).pop(true);
                                      } catch (e) {
                                        setModalState(() {
                                          isSaving = false;
                                          notesError = 'Unable to save reason.';
                                        });
                                        _showMessage(
                                          'Error: $e',
                                          isError: true,
                                        );
                                      }
                                    },
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.delete_forever_rounded,
                                      size: 17,
                                    ),
                              label: Text(isSaving ? 'Saving...' : 'Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    notesController.dispose();

    if (deleted == true) {
      if (!mounted) return;
      _refreshData();
      _showMessage('Patient deleted and reason was saved.');
    }
  }
}
