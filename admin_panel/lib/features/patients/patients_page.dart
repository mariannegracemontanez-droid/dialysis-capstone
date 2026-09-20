import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/patient_service.dart';
import '../../services/center_schedule_service.dart';
import '../../services/schedule_recommendation_service.dart';
import '../../models/patient.dart';
import '../../models/center_schedule.dart';
import '../../models/schedule_recommendation.dart';
import '../dashboard/dashboard_page.dart';
import '../auth/logout.dart';
import '../center/center_profile_page.dart';
import 'session_history_modal.dart';
import '../../widgets/admin_header.dart';
import '../../services/health_monitoring_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/admin_validators.dart';
import '../../widgets/admin_card_row.dart';
import '../../widgets/admin_modal.dart';
import '../../widgets/admin_notice.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_title.dart';
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

  /// The page's own scroll controller, so the page scrollbar is bound to
  /// the page rather than to whichever inner list also claimed the
  /// PrimaryScrollController.
  final ScrollController _pageScroll = ScrollController();

  // Presentation only: the page palette now comes from the shared Admin
  // theme, so it matches the Dashboard and the Super Admin portal. The
  // names are unchanged, so nothing below had to move.
  static const Color primary = AppTheme.blue1;
  static const Color background = AppTheme.canvas;
  static const Color cardBorder = AppTheme.border;
  static const Color textDark = AppTheme.textPrimary;
  static const Color textMuted = AppTheme.textMuted;
  static const Color softBlue = AppTheme.accentSoft;

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
    _pageScroll.dispose();
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
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Text(
        'No schedule set',
        style: TextStyle(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Every outcome this page reports goes through the one notice system,
  /// so it lands above whatever modal is open rather than in a snack bar
  /// underneath it.
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    if (isError) {
      AdminNotice.error(context, message);
    } else {
      AdminNotice.success(context, message);
    }
  }

  /// Something the admin should know that is not a failure.
  void _showInfo(String message) {
    if (!mounted) return;
    AdminNotice.info(context, message);
  }

  /// A field the admin has to correct before the save can go through.
  ///
  /// An error notice, not an info one: it waits to be acknowledged and
  /// an outside click will not dismiss it, so a rejected save can never
  /// be mistaken for a successful one.
  void _showValidation(String message) {
    if (!mounted) return;
    AdminNotice.error(context, message, title: 'Check this before saving');
  }

  /// Strips Dart's "Exception: " prefix so a rejected status change reads
  /// as the plain explanation PatientService wrote.
  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  void _showMedicalDocPreview(String fileName, String imageUrl) {
    showAdminDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 720,
            constraints: const BoxConstraints(maxHeight: 760),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rXl),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.shadowMd,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rXl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    color: AppTheme.blue1,
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
                      color: AppTheme.surfaceTint,
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
                                  color: AppTheme.textMuted,
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
              child: CircularProgressIndicator(color: AppTheme.blue1),
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
              color: AppTheme.surfaceTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Text(
              'No medical documents uploaded.',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceTint,
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        'FILE NAME',
                        style: TextStyle(
                          color: AppTheme.textMuted,
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
                          color: AppTheme.textMuted,
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
                        bottom: BorderSide(color: AppTheme.surfaceTint),
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
                                  color: AppTheme.accentSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.description_rounded,
                                  size: 18,
                                  color: AppTheme.blue1,
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
                                        color: AppTheme.textPrimary,
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
                                            ? AppTheme.danger
                                            : AppTheme.textMuted,
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
                              color: AppTheme.textSecondary,
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
            child: CircularProgressIndicator(color: AppTheme.blue1),
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
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderStrong),
              ),
              child: Text(
                hasTime
                    ? '$day • ${_formatTime(startTime)} - ${_formatTime(endTime)}'
                    : day,
                style: const TextStyle(
                  color: AppTheme.blue1,
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
    return AdminTitle(
      page: 'Patients',
      child: Scaffold(
        backgroundColor: background,
        body: Row(
          // Stretch, so the sidebar and the content area both fill the
          // viewport height and the page's scrollbar runs its full length.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildAdminHeader(),
                  Expanded(child: _buildPageBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = AppTheme.pagePadding(MediaQuery.of(context).size.width);

        // Padding sits inside the scroll view so the scrollbar
        // rides the true right edge of the viewport.
        return Scrollbar(
          controller: _pageScroll,
          child: SingleChildScrollView(
            controller: _pageScroll,
            padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.maxContentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeader(),
                    const SizedBox(height: 20),
                    _buildPatientSummaryCards(constraints.maxWidth),
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
          ),
        );
      },
    );
  }

  /// Existing navigation, unchanged - only the sidebar's appearance moved
  /// into the shared widget.
  void _onNavSelect(int index) {
    setState(() => _selectedNavIndex = index);

    if (index == AdminNav.dashboard) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    }
  }

  /// The panel's one logout, shared with the Dashboard. The Patients page
  /// previously had no way to sign out from its sidebar at all.
  void _logout() => adminLogout(context);

  Widget _buildPageHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.surface, AppTheme.headerTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const title = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppTheme.rLg),
                    ),
                    border: Border.fromBorderSide(
                      BorderSide(color: AppTheme.borderStrong),
                    ),
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color: AppTheme.blue1,
                    size: 23,
                  ),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PATIENT MANAGEMENT', style: AppTheme.eyebrow),
                    SizedBox(height: 6),
                    Text('Patients', style: AppTheme.pageTitle),
                    SizedBox(height: 7),
                    Text(
                      'Review requests, monitor active patients, and manage '
                      'clinical information in one organized workspace.',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12.5,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final refresh = SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Refresh'),
              style: AppTheme.secondaryButton(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          );

          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 16), refresh],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: title),
              const SizedBox(width: 16),
              refresh,
            ],
          );
        },
      ),
    );
  }

  Widget _buildPatientSummaryCards(double width) {
    final cards = <Widget>[
      FutureBuilder<List<Patient>>(
        future: _allPatients,
        builder: (context, snapshot) {
          return _buildSummaryCard(
            title: 'Active Patients',
            value: snapshot.data?.length.toString(),
            loading: snapshot.connectionState == ConnectionState.waiting,
            icon: Icons.verified_user_rounded,
            color: AppTheme.accentGreen,
            soft: AppTheme.accentGreenSoft,
            subtitle: 'Accepted patient records',
          );
        },
      ),
      FutureBuilder<List<Patient>>(
        future: _pendingPatients,
        builder: (context, snapshot) {
          return _buildSummaryCard(
            title: 'Pending Requests',
            value: snapshot.data?.length.toString(),
            loading: snapshot.connectionState == ConnectionState.waiting,
            icon: Icons.pending_actions_rounded,
            color: AppTheme.accentOrange,
            soft: AppTheme.accentOrangeSoft,
            subtitle: 'Needs admin review',
          );
        },
      ),
      FutureBuilder<List<Patient>>(
        future: _declinedPatients,
        builder: (context, snapshot) {
          return _buildSummaryCard(
            title: 'Declined',
            value: snapshot.data?.length.toString(),
            loading: snapshot.connectionState == ConnectionState.waiting,
            icon: Icons.person_off_rounded,
            color: AppTheme.danger,
            soft: AppTheme.dangerSoft,
            subtitle: 'Rejected applications',
          );
        },
      ),
    ];

    return AdminCardRow(cards: cards, width: width);
  }

  Widget _buildSummaryCard({
    required String title,
    required String? value,
    required IconData icon,
    required Color color,
    required Color soft,
    required String subtitle,
    bool loading = false,
  }) {
    return AdminHoverCard(
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: AppTheme.motion(context, AppTheme.fast),
          curve: AppTheme.ease,
          padding: const EdgeInsets.all(18),
          decoration: AppTheme.card(hovered: hovered),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: AppTheme.iconBox(soft, radius: AppTheme.rLg),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.eyebrow,
                    ),
                    const SizedBox(height: 7),
                    // A placeholder while the count is in flight, never a
                    // zero that could be mistaken for a real figure.
                    if (loading && value == null)
                      const AdminSkeleton(width: 48, height: 24)
                    else
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value ?? '0',
                          style: const TextStyle(
                            color: AppTheme.blue3,
                            fontSize: 26,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _adminInfo,
      builder: (context, snapshot) {
        final rawClinic = snapshot.data?['clinicName'];

        return AdminSidebar(
          selectedIndex: _selectedNavIndex,
          onSelect: _onNavSelect,
          onLogout: _logout,
          centerName: rawClinic == null
              ? null
              : capitalizeWords(rawClinic.toString()),
        );
      },
    );
  }

  /// The Admin header: the head nurse's name, shown once for the whole
  /// shell, and the way through to Center Profile.
  Widget _buildAdminHeader() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _adminInfo,
      builder: (context, snapshot) {
        final rawName = snapshot.data?['adminName'];
        final rawClinic = snapshot.data?['clinicName'];

        return AdminHeader(
          adminName: rawName == null
              ? null
              : capitalizeWords(rawName.toString()),
          centerName: rawClinic == null
              ? null
              : capitalizeWords(rawClinic.toString()),
          onOpenCenterProfile: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CenterProfilePage()),
            ).then((_) {
              // Capacity and shifts drive schedule validation on this
              // page, so re-read them on the way back.
              if (mounted) _refreshData();
            });
          },
        );
      },
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
            color: Colors.black.withValues(alpha: 0.04),
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
                    color: accentColor.withValues(alpha: 0.11),
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
                      color: accentColor.withValues(alpha: 0.10),
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

  /// A placeholder in the shape of the rows that are coming, so a list
  /// keeps its height while it loads instead of collapsing and snapping
  /// back. It shows no names or figures - only neutral blocks - so it can
  /// never be read as patient data.
  Widget _buildLoadingState({int rows = 4}) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          const SizedBox(
            height: 34,
            child: Row(
              children: [
                AdminSkeleton(width: 32, height: 32, radius: 16),
                SizedBox(width: 12),
                Expanded(flex: 3, child: AdminSkeleton(height: 11)),
                SizedBox(width: 16),
                Expanded(flex: 4, child: AdminSkeleton(height: 11)),
                SizedBox(width: 16),
                Expanded(flex: 2, child: AdminSkeleton(height: 11)),
              ],
            ),
          ),
        ],
      ],
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
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: AppTheme.iconBox(
              AppTheme.accentBlueSoft,
              radius: AppTheme.rLg,
            ),
            child: Icon(icon, size: 22, color: AppTheme.blue1),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
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
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: Color(0xFFF0CFCF)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Error loading data: $error',
              style: TextStyle(
                color: AppTheme.danger,
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
          accentColor: AppTheme.accentOrange,
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
                    headingRowColor: WidgetStateProperty.all(AppTheme.canvas),
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: AppTheme.border,
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
                              color: AppTheme.blue1,
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
          accentColor: AppTheme.blue1,
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
                    headingRowColor: WidgetStateProperty.all(AppTheme.canvas),
                    dataRowColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.hovered)) {
                        return AppTheme.accentSoft;
                      }
                      return null;
                    }),
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: AppTheme.border,
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
                        onSelectChanged: (_) =>
                            _showPatientDetailsModal(patient),
                        cells: [
                          DataCell(_buildNameCell(patient.name)),
                          DataCell(Text(patient.phone ?? patient.email)),
                          DataCell(
                            Text(_safeText(patient.emergencyContactName)),
                          ),
                          DataCell(
                            Text(_safeText(patient.emergencyContactNumber)),
                          ),
                          const DataCell(
                            Text(
                              'View details',
                              style: TextStyle(
                                color: AppTheme.blue1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const DataCell(
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 15,
                              color: AppTheme.iconMuted,
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
          accentColor: AppTheme.danger,
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
                    headingRowColor: WidgetStateProperty.all(AppTheme.canvas),
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: AppTheme.border,
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
            horizontalInside: BorderSide(color: AppTheme.border),
            verticalInside: BorderSide(color: AppTheme.border),
          ),
          defaultColumnWidth: const FlexColumnWidth(),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: AppTheme.canvas),
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
          border: Border.all(color: AppTheme.border),
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
          backgroundColor: AppTheme.accentSoft,
          child: Text(
            _getInitial(name),
            style: const TextStyle(
              color: AppTheme.blue1,
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
            color: AppTheme.textPrimary,
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
        color: color.withValues(alpha: 0.10),
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
    showAdminDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(22),
          child: Container(
            width: 1120,
            constraints: const BoxConstraints(maxHeight: 820),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rXl),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.shadowMd,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rXl),
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
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.surfaceTint,
                            foregroundColor: AppTheme.textSecondary,
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
    showAdminDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(22),
          child: Container(
            width: 1120,
            constraints: const BoxConstraints(maxHeight: 820),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rXl),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.shadowMd,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rXl),
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
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.surfaceTint,
                            foregroundColor: AppTheme.textSecondary,
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
                                      backgroundColor: AppTheme.blue1,
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
                                // Their real dialysis sessions -- NOT the
                                // recurring weekly schedule shown in the
                                // card above.
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => showSessionHistory(
                                      context: context,
                                      patient: patient,
                                    ),
                                    icon: const Icon(
                                      Icons.history_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('View Session History'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.accentTeal,
                                      side: const BorderSide(
                                        color: AppTheme.borderStrong,
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
                                      foregroundColor: AppTheme.danger,
                                      side: const BorderSide(
                                        color: AppTheme.dangerSoft,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_rounded, color: AppTheme.blue1, size: 20),
              SizedBox(width: 8),
              Text(
                'Application Review',
                style: TextStyle(
                  color: AppTheme.textPrimary,
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
              color: AppTheme.textMuted,
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
                  color: AppTheme.blue1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _reviewSummaryTile(
                  icon: Icons.bloodtype_rounded,
                  label: 'Blood Type',
                  value: _safeText(patient.bloodType),
                  color: AppTheme.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _reviewSummaryTile(
                  icon: Icons.medical_services_rounded,
                  label: 'Dialysis Stage',
                  value: _safeText(patient.dialysisStage),
                  color: AppTheme.accentPurple,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accentOrangeSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accentOrangeSoft),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.accentOrange,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Make sure the patient details and uploaded documents are valid before approving this request.',
                    style: TextStyle(
                      color: AppTheme.accentOrange,
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
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
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
              color: AppTheme.textPrimary,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.folder_copy_rounded, color: AppTheme.blue1, size: 20),
              SizedBox(width: 8),
              Text(
                'Medical Documents',
                style: TextStyle(
                  color: AppTheme.textPrimary,
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
              color: AppTheme.textMuted,
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
          detail =
              "Analyzing this center's weekly schedule and shift capacity.";
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
              accent = AppTheme.accentGreen;
              icon = Icons.verified_rounded;
              break;
            case AcceptanceVerdict.reviewRequired:
              accent = AppTheme.accentOrange;
              icon = Icons.info_rounded;
              break;
            case AcceptanceVerdict.cannotAccommodate:
              accent = AppTheme.danger;
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
                      color: accent.withValues(alpha: 0.12),
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
        border: Border.all(color: AppTheme.border),
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
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Accepting the patient will move them to active records and schedule assignment.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
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
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: AppTheme.dangerSoft),
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
              backgroundColor: AppTheme.accentGreen,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                _getInitial(patient.name),
                style: const TextStyle(
                  color: AppTheme.blue1,
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
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            patient.email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Information',
            style: TextStyle(
              color: AppTheme.textPrimary,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: AppTheme.blue1,
              ),
              SizedBox(width: 8),
              Text(
                'Weekly Schedule',
                style: TextStyle(
                  color: AppTheme.textPrimary,
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
                color: AppTheme.danger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _healthSummaryCard(
                icon: Icons.monitor_weight_rounded,
                label: 'Latest Weight',
                value: latestWeight,
                unit: '',
                color: AppTheme.blue1,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _healthSummaryCard(
                icon: Icons.water_drop_rounded,
                label: 'Blood Type',
                value: _safeText(patient.bloodType),
                unit: '',
                color: AppTheme.blue1,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
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
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
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
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.blue1),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.blue1,
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
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
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
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                _getInitial(patient.name),
                style: const TextStyle(
                  color: AppTheme.blue1,
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
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  patient.email,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
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
              backgroundColor: AppTheme.surfaceTint,
              foregroundColor: AppTheme.textSecondary,
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
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.blue1),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.blue1,
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
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Complete patient profile, medical details, and emergency contact information.',
          style: TextStyle(
            color: AppTheme.textMuted,
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
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Every recorded change to this patient\'s medical and '
              'scheduling information, newest first.',
              style: TextStyle(
                color: AppTheme.textMuted,
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
        color: AppTheme.surfaceTint,
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
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: AppTheme.blue1),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: AppTheme.blue1),
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
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
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
        color: AppTheme.surfaceTint,
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
                  color: AppTheme.blue1,
                  size: 21,
                ),
                SizedBox(width: 8),
                Text(
                  'Health Monitoring',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: AppTheme.blue4,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),
            const Text(
              'Track blood pressure and dialysis weight records per session.',
              style: TextStyle(
                color: AppTheme.textMuted,
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
                    accentColor: AppTheme.danger,
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
                    accentColor: AppTheme.blue1,
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

    showAdminDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 720,
            constraints: const BoxConstraints(maxHeight: 720),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rXl),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.shadowMd,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rXl),
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
                        color: AppTheme.blue4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Locked Information',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppTheme.blue4,
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
                        color: AppTheme.blue4,
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
                        color: AppTheme.blue4,
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

                            // Every editable field is checked before the
                            // update is sent, so an invalid value can
                            // never reach the patient record. Sessions
                            // per week keeps its existing 1-6 rule -- the
                            // range the scheduling validation and the
                            // recommendation both already assume.
                            final validationError = AdminValidators.firstError([
                              () => AdminValidators.email(emailController.text),
                              () => AdminValidators.phone(phoneController.text),
                              () => AdminValidators.requiredText(
                                addressController.text,
                                label: 'home address',
                                maxLength: 250,
                              ),
                              () => AdminValidators.requiredText(
                                guardianNameController.text,
                                label: 'emergency contact name',
                                maxLength: 100,
                              ),
                              () => AdminValidators.phone(
                                guardianContactController.text,
                                label: 'emergency contact number',
                              ),
                              () => AdminValidators.optionalText(
                                dialysisStageController.text,
                                label: 'dialysis stage',
                                maxLength: 100,
                              ),
                              () => AdminValidators.optionalText(
                                existingConditionController.text,
                                label: 'existing condition',
                                maxLength: 500,
                              ),
                              () => AdminValidators.wholeNumber(
                                sessionsText,
                                label: 'required sessions per week',
                                min: 1,
                                max: 6,
                                required: false,
                              ),
                            ]);

                            if (validationError != null) {
                              _showValidation(validationError);
                              return;
                            }

                            final sessions = sessionsText.isEmpty
                                ? null
                                : int.parse(sessionsText);

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
                              _showMessage(
                                'The patient record has been saved.',
                              );
                            } catch (e) {
                              _showMessage(
                                'The patient\'s information could not be '
                                'updated. $e',
                                isError: true,
                              );
                            }
                          },
                          icon: const Icon(Icons.save_rounded, size: 17),
                          label: const Text('Save Changes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.blue1,
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
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
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
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.blue4,
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
              color: AppTheme.textMuted,
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
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latestLabel,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  latestValue,
                  style: const TextStyle(
                    color: AppTheme.blue4,
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
                backgroundColor: AppTheme.blue1,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_rounded,
                color: AppTheme.blue1,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppTheme.blue4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.textMuted,
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
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderStrong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppTheme.blue1,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.blue1,
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
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.show_chart_rounded,
            color: AppTheme.iconMuted,
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
                    color: AppTheme.blue4,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
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
              color: AppTheme.surfaceTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Text(
              'No blood pressure records yet.',
              style: TextStyle(
                color: AppTheme.textMuted,
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
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded, color: AppTheme.blue1, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Recent Blood Pressure Records',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AppTheme.blue4,
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
                    color: AppTheme.surfaceTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.dangerSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: AppTheme.danger,
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
                                color: AppTheme.blue4,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              date,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
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
                          color: AppTheme.accentSoft,
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
                            color: AppTheme.blue1,
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
                              color: AppTheme.textMuted,
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
                  border: Border.all(color: AppTheme.border),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: systolicSpots,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    color: AppTheme.danger,
                  ),
                  LineChartBarData(
                    spots: diastolicSpots,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    color: AppTheme.blue1,
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
              color: AppTheme.surfaceTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Text(
              'No weight records yet.',
              style: TextStyle(
                color: AppTheme.textMuted,
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
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.monitor_weight_rounded,
                    color: AppTheme.blue1,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Recent Weight Records',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AppTheme.blue4,
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
                    color: AppTheme.surfaceTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlueSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.monitor_weight_rounded,
                          color: AppTheme.blue1,
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
                                color: AppTheme.blue4,
                                fontSize: 14,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              'Weight Removed: $difference kg',
                              style: const TextStyle(
                                color: AppTheme.blue1,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              date,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
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
                          color: AppTheme.accentSoft,
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
                            color: AppTheme.blue1,
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
                              color: AppTheme.textMuted,
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
                  border: Border.all(color: AppTheme.border),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: beforeSpots,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    color: AppTheme.blue1,
                  ),
                  LineChartBarData(
                    spots: afterSpots,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    color: AppTheme.accentGreen,
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

    showAdminDialog(
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
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.rXl),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.favorite_rounded,
                          color: AppTheme.danger,
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Add Blood Pressure Record',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.blue4,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      patient.name,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Session Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.blue4,
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
                          color: AppTheme.surfaceTint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          selectedDate.toString().split(' ')[0],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.blue4,
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
                                  final bpError = AdminValidators.bloodPressure(
                                    systolic: systolicController.text,
                                    diastolic: diastolicController.text,
                                  );

                                  if (bpError != null) {
                                    _showValidation(bpError);
                                    return;
                                  }

                                  final systolic = int.parse(
                                    systolicController.text.trim(),
                                  );

                                  final diastolic = int.parse(
                                    diastolicController.text.trim(),
                                  );

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
                                    _showMessage(
                                      'The blood pressure record could not '
                                      'be saved. $e',
                                      isError: true,
                                    );
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
                            backgroundColor: AppTheme.blue1,
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

    showAdminDialog(
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
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.rXl),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.monitor_weight_rounded,
                          color: AppTheme.blue1,
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Add Weight Record',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.blue4,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      patient.name,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Session Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.blue4,
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
                          color: AppTheme.surfaceTint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          selectedDate.toString().split(' ')[0],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.blue4,
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
                                  final weightError =
                                      AdminValidators.firstError([
                                        () => AdminValidators.weightKg(
                                          beforeController.text,
                                          label: 'weight before dialysis',
                                        ),
                                        () => AdminValidators.weightKg(
                                          afterController.text,
                                          label: 'weight after dialysis',
                                        ),
                                      ]);

                                  if (weightError != null) {
                                    _showValidation(weightError);
                                    return;
                                  }

                                  final beforeWeight = double.parse(
                                    beforeController.text.trim(),
                                  );

                                  final afterWeight = double.parse(
                                    afterController.text.trim(),
                                  );

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
                                    _showMessage(
                                      'The weight record could not be '
                                      'saved. $e',
                                      isError: true,
                                    );
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
                            backgroundColor: AppTheme.blue1,
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
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 18, color: AppTheme.iconMuted),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.blue4,
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
          prefixIcon: Icon(icon, color: AppTheme.blue1),
          filled: true,
          fillColor: AppTheme.surfaceTint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.blue1, width: 1.5),
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

  /// Accepting reserves the patient at this center (`no_sched`) -- it does
  /// NOT schedule them. They move to `active` only once a recurring
  /// schedule is actually saved.
  Future<void> _acceptPatient(Patient patient) async {
    try {
      await _service.acceptPatient(patient.id);
      _refreshData();
      _showMessage(
        '${patient.name} accepted. They are now reserved at your center and '
        'waiting for a schedule — assign one from No Schedule Patients on '
        'the Dashboard.',
      );
    } catch (e) {
      _showMessage(_friendlyError(e), isError: true);
    }
  }

  Future<void> _confirmPendingDecision({
    required Patient patient,
    required bool isAccept,
  }) async {
    if (isAccept) {
      final confirm = await showAdminDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (confirmContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen),
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
                  backgroundColor: AppTheme.accentGreen,
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
        _showMessage(
          '${patient.name} accepted. They are now reserved at your center and '
          'waiting for a schedule — assign one from No Schedule Patients on '
          'the Dashboard.',
        );
      } catch (e) {
        // The dialog stays closed only on success; on failure the patient
        // is unchanged and the admin sees why.
        _showMessage(_friendlyError(e), isError: true);
      }
      return;
    }

    await _showDeclinePatientConfirmation(patient);
  }

  Future<void> _showDeclinePatientConfirmation(Patient patient) async {
    final reasonController = TextEditingController();
    bool isSaving = false;
    String? errorText;

    final declined = await showAdminDialog<bool>(
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
                      color: Colors.black.withValues(alpha: 0.18),
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
                            color: AppTheme.dangerSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.person_off_rounded,
                            color: AppTheme.danger,
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
                                  color: AppTheme.textPrimary,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                patient.name,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
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
                        color: AppTheme.textSecondary,
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
                          color: AppTheme.iconMuted,
                          fontWeight: FontWeight.w500,
                        ),
                        errorText: errorText,
                        filled: true,
                        fillColor: AppTheme.surfaceTint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppTheme.blue1,
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
                        color: AppTheme.accentOrangeSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accentOrangeSoft),
                      ),
                      child: const Text(
                        'This reason will be saved in the patient record and can be shown in the mobile app.',
                        style: TextStyle(
                          color: AppTheme.accentOrange,
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

                                    // The reason is saved on the patient
                                    // record and can be shown to them in
                                    // the mobile app, so it has to be a
                                    // real sentence rather than a stray
                                    // character.
                                    final reasonError =
                                        AdminValidators.requiredText(
                                          reason,
                                          label: 'decline reason',
                                          minLength: 5,
                                          maxLength: 500,
                                        );

                                    if (reasonError != null) {
                                      setModalState(() {
                                        errorText = reasonError;
                                      });
                                      return;
                                    }

                                    try {
                                      setModalState(() {
                                        isSaving = true;
                                        errorText = null;
                                      });

                                      // Routed through PatientService so the
                                      // write is verified: a raw update here
                                      // matched zero rows silently whenever
                                      // the clinic or status didn't line up,
                                      // and still reported success.
                                      await _service.declinePatientWithReason(
                                        patientId: patient.id,
                                        reason: reason,
                                      );

                                      if (!mounted) return;
                                      Navigator.of(dialogContext).pop(true);
                                    } catch (e) {
                                      setModalState(() {
                                        isSaving = false;
                                        errorText = 'Unable to save reason.';
                                      });
                                      _showMessage(
                                        _friendlyError(e),
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
                                : const Icon(Icons.close_rounded, size: 17),
                            label: Text(isSaving ? 'Saving...' : 'Decline'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.danger,
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

    final deleted = await showAdminDialog<bool>(
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
                      color: Colors.black.withValues(alpha: 0.18),
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
                              color: AppTheme.dangerSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.person_remove_rounded,
                              color: AppTheme.danger,
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
                                    color: AppTheme.textPrimary,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  patient.name,
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
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
                          color: AppTheme.dangerSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.dangerSoft),
                        ),
                        child: const Text(
                          'This will remove the patient from the active list by changing the status to deleted. The reason and deletion time will remain saved for records and review.',
                          style: TextStyle(
                            color: AppTheme.danger,
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
                          color: AppTheme.textSecondary,
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
                            selectedColor: AppTheme.accentSoft,
                            backgroundColor: AppTheme.surfaceTint,
                            side: BorderSide(
                              color: isSelected
                                  ? AppTheme.blue1
                                  : AppTheme.border,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppTheme.blue1
                                  : AppTheme.textSecondary,
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
                            color: AppTheme.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const Text(
                        'Detailed reason',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
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
                            color: AppTheme.iconMuted,
                            fontWeight: FontWeight.w500,
                          ),
                          errorText: notesError,
                          filled: true,
                          fillColor: AppTheme.surfaceTint,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppTheme.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppTheme.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppTheme.blue1,
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

                                      final notesProblem =
                                          AdminValidators.requiredText(
                                            notes,
                                            label: 'detailed reason',
                                            minLength: 5,
                                            maxLength: 500,
                                          );

                                      if (notesProblem != null) {
                                        setModalState(() {
                                          notesError = notesProblem;
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

                                        // Routed through PatientService so the
                                        // write is verified rather than
                                        // silently matching zero rows.
                                        await _service.deletePatientWithReason(
                                          patientId: patient.id,
                                          reason: finalReason,
                                          deletedAt: DateTime.now(),
                                        );

                                        if (!mounted) return;
                                        Navigator.of(dialogContext).pop(true);
                                      } catch (e) {
                                        setModalState(() {
                                          isSaving = false;
                                          notesError = 'Unable to save reason.';
                                        });
                                        _showMessage(
                                          _friendlyError(e),
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
                                backgroundColor: AppTheme.danger,
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
