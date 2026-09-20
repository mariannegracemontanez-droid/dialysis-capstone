// ignore_for_file: prefer_final_fields, unused_field

import 'package:admin_panel/features/dashboard/today_schedule_section.dart';
import 'package:admin_panel/services/dashboard_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/patient.dart';
import '../../theme/app_theme.dart';
import '../../utils/admin_validators.dart';
import '../../widgets/admin_card_row.dart';
import '../../widgets/admin_modal.dart';
import '../../widgets/admin_notice.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_title.dart';
import '../auth/logout.dart';
import '../center/center_profile_page.dart';
import '../../widgets/admin_header.dart';
import '../patients/patients_page.dart';
import 'announcements_section.dart';
import 'patient_schedule_modal.dart';
import 'reschedule_requests_section.dart';

final supabase = Supabase.instance.client;

late Future<Map<String, dynamic>?> _adminInfo;

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

RealtimeChannel? _patientsChannel;
RealtimeChannel? _weeklySchedulesChannel;
RealtimeChannel? _fundDistributionsChannel;
RealtimeChannel? _purchaseLogsChannel;
RealtimeChannel? _donationsChannel;
RealtimeChannel? _donationAllocationsChannel;

class _DashboardPageState extends ConsumerState<DashboardPage>
    with TickerProviderStateMixin {
  final DashboardService _service = DashboardService();

  late Future<int> _totalPatients;
  late Future<int> _pendingPatientsCount;
  late Future<List<Map<String, dynamic>>> _monthlyData;
  late Future<List<Patient>> _noSchedPatients;

  int _selectedNavIndex = 0;

  /// The page's own scroll controller.
  ///
  /// Without it both this scroll view and the purchase-log list inside the
  /// donation card claim the PrimaryScrollController, and the page's
  /// Scrollbar then has two positions to choose from. Owning a controller
  /// keeps the page scrollbar bound to the page.
  final ScrollController _pageScroll = ScrollController();

  late AnimationController _fadeController;
  String? _connectionError;

  // Today's Schedule and Reschedule Requests read the same daily_schedules
  // rows, so a decision in one has to refresh the other.
  final GlobalKey<TodayScheduleSectionState> _todayScheduleKey =
      GlobalKey<TodayScheduleSectionState>();
  final GlobalKey<RescheduleRequestsSectionState> _rescheduleRequestsKey =
      GlobalKey<RescheduleRequestsSectionState>();

  /// Patient Announcements is self-contained; the key exists only so the
  /// dashboard's Refresh button can reload it along with everything else.
  final GlobalKey<AnnouncementsSectionState> _announcementsKey =
      GlobalKey<AnnouncementsSectionState>();

  String? clinicId;
  String centerName = 'Valenzuela Dialysis Center';
  int machineCount = 10;

  Map<String, dynamic>? latestDonation;
  num totalDonations = 0;
  List<Map<String, dynamic>> purchaseLogs = [];

  // Presentation only: the dashboard palette now comes from the shared
  // Admin theme, so it matches the Patients page and the Super Admin
  // portal. The names are unchanged, so nothing below had to move.
  static const Color primary = AppTheme.blue1;
  static const Color primaryDark = AppTheme.blue3;
  static const Color background = AppTheme.canvas;
  static const Color border = AppTheme.border;
  static const Color textDark = AppTheme.textPrimary;
  static const Color textMuted = AppTheme.textMuted;
  static const Color green = AppTheme.accentGreen;
  static const Color orange = AppTheme.accentOrange;
  static const Color purple = AppTheme.accentPurple;

  @override
  void initState() {
    super.initState();

    _initAnimations();
    _loadData();
    _verifyDatabaseConnection();
    // Donation data is keyed by clinic, so it is fetched by loadClinicData
    // once clinicId/centerName resolve -- calling it here would read against
    // the placeholder centerName and show another center's donation.
    loadClinicData();

    _patientsChannel = Supabase.instance.client
        .channel('dashboard_patients_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'patients',
          callback: (payload) {
            _loadData();
            loadClinicData();
          },
        )
        .subscribe();

    _weeklySchedulesChannel = Supabase.instance.client
        .channel('dashboard_weekly_schedules_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'weekly_schedules',
          callback: (payload) {
            _loadData();
            loadClinicData();
          },
        )
        .subscribe();

    _fundDistributionsChannel = Supabase.instance.client
        .channel('dashboard_fund_distributions_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'fund_distributions',
          callback: (payload) {
            fetchDonationData();
          },
        )
        .subscribe();

    _purchaseLogsChannel = Supabase.instance.client
        .channel('dashboard_purchase_logs_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'donation_purchase_logs',
          callback: (payload) {
            fetchDonationData();
          },
        )
        .subscribe();

    // A Superadmin approving a donation (specific/random -> donations.status,
    // equal distribution -> the parent donations row referenced by this
    // center's donation_allocations rows) should be reflected here without
    // needing a manual refresh.
    _donationsChannel = Supabase.instance.client
        .channel('dashboard_donations_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'donations',
          callback: (payload) {
            fetchDonationData();
          },
        )
        .subscribe();

    _donationAllocationsChannel = Supabase.instance.client
        .channel('dashboard_donation_allocations_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'donation_allocations',
          callback: (payload) {
            fetchDonationData();
          },
        )
        .subscribe();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageScroll.dispose();

    if (_patientsChannel != null) {
      Supabase.instance.client.removeChannel(_patientsChannel!);
    }

    if (_weeklySchedulesChannel != null) {
      Supabase.instance.client.removeChannel(_weeklySchedulesChannel!);
    }

    if (_fundDistributionsChannel != null) {
      Supabase.instance.client.removeChannel(_fundDistributionsChannel!);
    }

    if (_purchaseLogsChannel != null) {
      Supabase.instance.client.removeChannel(_purchaseLogsChannel!);
    }

    if (_donationsChannel != null) {
      Supabase.instance.client.removeChannel(_donationsChannel!);
    }

    if (_donationAllocationsChannel != null) {
      Supabase.instance.client.removeChannel(_donationAllocationsChannel!);
    }

    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _noSchedPatients = _service.getPatientsByStatus('no_sched');
      _totalPatients = _service.getTotalPatients();
      _pendingPatientsCount = _service.getPendingPatientsCount();
      _monthlyData = _service.getMonthlyPatientData();
      _adminInfo = _service.getCurrentAdminInfo();
    });
  }

  Future<void> _verifyDatabaseConnection() async {
    try {
      await _service.getTotalPatients();
      if (!mounted) return;
      setState(() => _connectionError = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionError =
            'Unable to connect to database. Please check your Supabase configuration.';
      });
    }
  }

  Future<void> loadClinicData() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('clinic_id, clinics(machine, name)')
          .eq('id', user.id)
          .single();

      if (!mounted) return;

      setState(() {
        clinicId = data['clinic_id'];
        machineCount = data['clinics']?['machine'] ?? 10;
        centerName = data['clinics']?['name'] ?? centerName;
      });

      fetchDonationData();
    } catch (e) {
      debugPrint('Error loading clinic data: $e');
    }
  }

  Future<void> fetchDonationData() async {
    try {
      final latest = await _service.getLatestDonation(
        centerName: centerName,
        clinicId: clinicId,
      );
      final manualTotal = await _service.getTotalDonations(centerName);

      // Real donor-driven allocations (specific/random/equal-share, all
      // resolved and verified through the donation flow) are additive with
      // the manual fund_distributions total above -- not a replacement --
      // so previously-distributed amounts are never dropped from the
      // center's reported total.
      num allocatedTotal = 0;
      if (clinicId != null) {
        allocatedTotal = await _service.getAllocatedDonationTotal(clinicId!);
      }

      final logs = await Supabase.instance.client
          .from('donation_purchase_logs')
          .select()
          .eq('clinic_name', centerName)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        latestDonation = latest;
        totalDonations = manualTotal + allocatedTotal;
        purchaseLogs = List<Map<String, dynamic>>.from(logs);
      });
    } catch (e) {
      debugPrint('Error fetching donation data: $e');
    }
  }

  Future<void> _addPurchaseLog({
    required String itemName,
    required num amount,
  }) async {
    try {
      await Supabase.instance.client.from('donation_purchase_logs').insert({
        'clinic_name': centerName,
        'item_name': itemName,
        'amount': amount,
        'purchase_date': DateTime.now().toIso8601String(),
      });

      await fetchDonationData();
      _showMessage('Purchase log added successfully');
    } catch (e) {
      _showMessage('The purchase log could not be saved. $e', isError: true);
    }
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

  String _safeText(String? value, {String fallback = 'N/A'}) {
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  String _getInitial(String name) {
    if (name.trim().isEmpty) return 'P';
    return name.trim()[0].toUpperCase();
  }

  String _formatMoney(num value) {
    return '₱ ${value.toStringAsFixed(2)}';
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'N/A';

    try {
      final date = DateTime.parse(value.toString()).toLocal();
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return value.toString();
    }
  }

  /// Every outcome the dashboard reports goes through the one notice
  /// system, so it lands above whatever modal is open rather than in a
  /// snack bar underneath it.
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
  /// An error notice rather than an info one, so it waits to be
  /// acknowledged and cannot be dismissed by clicking past it.
  void _showValidation(String message) {
    if (!mounted) return;
    AdminNotice.error(context, message, title: 'Check this before saving');
  }

  /// The panel's one logout, shared with the Patients page. Unchanged
  /// behaviour -- it only moved out of this file.
  void _logout() => adminLogout(context);

  void _showAddPurchaseModal() {
    final itemController = TextEditingController();
    final amountController = TextEditingController();

    showAdminDialog(
      context: context,
      builder: (dialogContext) {
        return AdminModal(
          title: 'Add Purchase Log',
          subtitle:
              'Record a clinic expense. The remaining donation balance '
              'updates automatically.',
          icon: Icons.receipt_long_rounded,
          accent: AppTheme.accentPurple,
          accentSoft: AppTheme.accentPurpleSoft,
          size: AdminModalSize.small,
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: AppTheme.secondaryButton(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: AppTheme.primaryButton(),
              onPressed: () async {
                final itemName = itemController.text.trim();

                // Checked field by field, so the message says which one
                // is wrong rather than covering both at once. The
                // balance ceiling below is unchanged -- how donations
                // are recorded and spent is not touched here.
                final validationError = AdminValidators.firstError([
                  () => AdminValidators.requiredText(
                    itemName,
                    label: 'purchase item',
                    maxLength: 150,
                  ),
                  () => AdminValidators.decimalNumber(
                    amountController.text,
                    label: 'amount spent',
                    max: 100000000,
                  ),
                ]);

                if (validationError != null) {
                  _showValidation(validationError);
                  return;
                }

                final amount = num.parse(amountController.text.trim());

                final currentSpent = purchaseLogs.fold<num>(
                  0,
                  (sum, item) => sum + ((item['amount'] as num?) ?? 0),
                );

                final currentRemainingBalance = totalDonations - currentSpent;

                if (amount > currentRemainingBalance) {
                  _showValidation(
                    'The amount spent (${_formatMoney(amount)}) is more than '
                    'the remaining donation balance of '
                    '${_formatMoney(currentRemainingBalance)}.',
                  );
                  return;
                }

                Navigator.of(dialogContext).pop();

                await _addPurchaseLog(itemName: itemName, amount: amount);
              },
              icon: const Icon(Icons.save_rounded, size: 17),
              label: const Text('Save log'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminField(
                label: 'Purchase item',
                required: true,
                child: TextField(
                  controller: itemController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTheme.fieldTextStyle,
                  decoration: AppTheme.field(
                    hintText: 'Ex. Dialyzer supplies',
                    prefixIcon: const Icon(
                      Icons.inventory_2_outlined,
                      size: 19,
                      color: AppTheme.iconMuted,
                    ),
                  ),
                ),
              ),
              const AdminFieldGap(),
              AdminField(
                label: 'Amount spent',
                required: true,
                helper: 'Remaining: ${_formatMoney(_remainingBalance())}',
                child: TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppTheme.fieldTextStyle.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: AppTheme.field(
                    hintText: '0.00',
                    prefixIcon: const SizedBox(
                      width: 46,
                      child: Center(
                        child: Text(
                          '\u20B1',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentPurple,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// What is left of this center's donations after the logged purchases.
  /// Shown in the purchase modal so the admin can see the ceiling the
  /// save is checked against. The check itself is unchanged.
  num _remainingBalance() {
    final spent = purchaseLogs.fold<num>(
      0,
      (sum, item) => sum + ((item['amount'] as num?) ?? 0),
    );
    final remaining = totalDonations - spent;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _refreshDashboard() async {
    _loadData();
    _announcementsKey.currentState?.load();
    await loadClinicData();
    await fetchDonationData();
    await _verifyDatabaseConnection();
  }

  @override
  Widget build(BuildContext context) {
    return AdminTitle(
      page: 'Admin Dashboard',
      child: Scaffold(
        backgroundColor: background,
        body: Row(
          // Stretch, so the sidebar and the content area both fill the
          // viewport height. Without it a short page floats vertically
          // centred and its scroll view never reaches the full height.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildAdminHeader(),
                  Expanded(
                    child: FadeTransition(
                      opacity: _fadeController.drive(
                        Tween<double>(begin: 0, end: 1),
                      ),
                      child: _buildMainContent(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Existing navigation, unchanged - only the sidebar's appearance moved
  /// into the shared widget.
  void _onNavSelect(int index) {
    setState(() => _selectedNavIndex = index);

    if (index != AdminNav.patients) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PatientsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ).then((_) {
      // Accepting a patient on the Patients page moves them into
      // No Schedule Patients here. The patients realtime channel
      // usually catches that, but it only fires if Realtime is
      // enabled for the table -- reloading on return makes the
      // list correct either way.
      if (!mounted) return;
      setState(() => _selectedNavIndex = AdminNav.dashboard);
      _loadData();
    });
  }

  Widget _buildSidebar() {
    return AdminSidebar(
      selectedIndex: _selectedNavIndex,
      onSelect: _onNavSelect,
      onLogout: _logout,
      centerName: clinicId == null ? null : capitalizeWords(centerName),
      machineCount: clinicId == null ? null : machineCount,
    );
  }

  /// The Admin header. The head nurse's name is shown here -- once for
  /// the whole shell -- and this is the way through to Center Profile.
  Widget _buildAdminHeader() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _adminInfo,
      builder: (context, snapshot) {
        final rawName = snapshot.data?['adminName'];

        return AdminHeader(
          adminName: rawName == null
              ? null
              : capitalizeWords(rawName.toString()),
          centerName: clinicId == null ? null : capitalizeWords(centerName),
          onOpenCenterProfile: _openCenterProfile,
        );
      },
    );
  }

  void _openCenterProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CenterProfilePage()),
    ).then((_) {
      // Machines, shifts and capacity can all have changed while the
      // profile page was open, and the dashboard reads every one of them.
      if (!mounted) return;
      loadClinicData();
      _loadData();
    });
  }

  Widget _buildMainContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final pad = AppTheme.pagePadding(MediaQuery.of(context).size.width);

        // Below this the two columns stack: on a narrow window the 7/3
        // split squeezed the donation card until its figures wrapped.
        final stacked = width < AppTheme.stackBreakpoint;

        final left = Column(
          children: [
            _buildTodaysScheduleSection(),
            const SizedBox(height: 18),
            _buildMonthlyChart(),
          ],
        );

        final right = Column(
          children: [
            // Patient Announcements sits directly above Donation Funds.
            _buildAnnouncementsSection(),
            const SizedBox(height: 18),
            _buildDonationCard(),
          ],
        );

        // No outer padding on the scroll view: the padding goes *inside*
        // it, so the scrollbar rides the true right edge of the viewport
        // instead of floating inset from it.
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
                    if (_connectionError != null) ...[
                      _buildConnectionError(),
                      const SizedBox(height: 18),
                    ],
                    _buildHeroOverview(),
                    const SizedBox(height: 18),
                    _buildKPIRow(constraints.maxWidth),
                    const SizedBox(height: 18),
                    if (stacked) ...[
                      left,
                      const SizedBox(height: 18),
                      right,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: left),
                          const SizedBox(width: 18),
                          Expanded(flex: 3, child: right),
                        ],
                      ),
                    const SizedBox(height: 18),
                    _buildRescheduleRequestsSection(),
                    const SizedBox(height: 18),
                    _buildNoSchedulePatients(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageHeader() {
    return const SizedBox.shrink();
  }

  Widget _buildHeroOverview() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _adminInfo,
      builder: (context, snapshot) {
        final rawClinicName = snapshot.data?['clinicName'] ?? centerName;
        final clinicName = capitalizeWords(rawClinicName.toString());

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
              final title = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      borderRadius: BorderRadius.circular(AppTheme.rLg),
                      border: Border.all(color: AppTheme.borderStrong),
                    ),
                    child: const Icon(
                      Icons.monitor_heart_rounded,
                      color: AppTheme.blue1,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CENTER OPERATIONS',
                          style: AppTheme.eyebrow,
                        ),
                        const SizedBox(height: 6),
                        Text(clinicName, style: AppTheme.pageTitle),
                        const SizedBox(height: 7),
                        const Text(
                          'Daily workspace for dialysis scheduling, patient '
                          'monitoring, and transparent center operations.',
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
                  onPressed: _refreshDashboard,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Refresh'),
                  style: AppTheme.secondaryButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              );

              // On a narrow window the button drops below the heading
              // rather than squeezing the center name.
              if (constraints.maxWidth < 640) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 16), refresh],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  refresh,
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildKPIRow(double width) {
    return FutureBuilder<List<Patient>>(
      future: _noSchedPatients,
      builder: (context, noSchedSnapshot) {
        final noSchedCount = noSchedSnapshot.data?.length ?? 0;
        final noSchedLoading =
            noSchedSnapshot.connectionState == ConnectionState.waiting;

        final cards = <Widget>[
          FutureBuilder<int>(
            future: _totalPatients,
            builder: (context, snapshot) {
              return _buildKPICard(
                title: 'Total Patients',
                value: snapshot.data?.toString(),
                loading: snapshot.connectionState == ConnectionState.waiting,
                icon: Icons.groups_rounded,
                color: AppTheme.blue1,
                soft: AppTheme.accentBlueSoft,
                subtitle: 'Registered records',
              );
            },
          ),
          FutureBuilder<int>(
            future: _pendingPatientsCount,
            builder: (context, snapshot) {
              return _buildKPICard(
                title: 'Pending',
                value: snapshot.data?.toString(),
                loading: snapshot.connectionState == ConnectionState.waiting,
                icon: Icons.pending_actions_rounded,
                color: AppTheme.accentPurple,
                soft: AppTheme.accentPurpleSoft,
                subtitle: 'Awaiting approval',
              );
            },
          ),
          _buildKPICard(
            title: 'Need Schedule',
            value: noSchedCount.toString(),
            loading: noSchedLoading,
            icon: Icons.event_busy_rounded,
            color: AppTheme.accentOrange,
            soft: AppTheme.accentOrangeSoft,
            subtitle: 'No weekly schedule',
          ),
        ];

        return AdminCardRow(cards: cards, width: width, spacing: 14);
      },
    );
  }

  Widget _buildKPICard({
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
                width: 44,
                height: 44,
                decoration: AppTheme.iconBox(soft, radius: AppTheme.rLg),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // While the count is in flight a placeholder stands in
                    // its place: never a zero, which would read as a real
                    // figure.
                    if (loading && value == null)
                      const AdminSkeleton(width: 46, height: 22)
                    else
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value ?? '0',
                          style: const TextStyle(
                            fontSize: 25,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.blue3,
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
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
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

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Widget child,
    Color? accentSoft,
    Widget? trailing,
  }) {
    return AdminSection(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accentColor,
      accentSoft: accentSoft ?? _softFor(accentColor),
      trailing: trailing,
      child: child,
    );
  }

  /// The tinted companion for one of the accent colours used here.
  static Color _softFor(Color accent) {
    if (accent == AppTheme.accentGreen) return AppTheme.accentGreenSoft;
    if (accent == AppTheme.accentOrange) return AppTheme.accentOrangeSoft;
    if (accent == AppTheme.accentPurple) return AppTheme.accentPurpleSoft;
    if (accent == AppTheme.accentPink) return AppTheme.accentPinkSoft;
    if (accent == AppTheme.danger) return AppTheme.dangerSoft;
    return AppTheme.accentBlueSoft;
  }

  /// Patient Announcements -- the notices this center's patients see in
  /// the CureNurture mobile app. Renders its own panel, so it keeps the
  /// "New" action next to its own heading.
  Widget _buildAnnouncementsSection() {
    if (clinicId == null) {
      return _sectionCard(
        title: 'Patient Announcements',
        subtitle: 'Loading this center\u2019s announcements.',
        icon: Icons.campaign_rounded,
        accentColor: AppTheme.accentOrange,
        child: const SizedBox(
          height: 120,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      );
    }

    return AnnouncementsSection(key: _announcementsKey, clinicId: clinicId!);
  }

  Widget _buildTodaysScheduleSection() {
    if (clinicId == null) {
      return _sectionCard(
        title: 'Today’s Dialysis Schedule',
        subtitle: 'Loading AM and PM shift scheduling.',
        icon: Icons.calendar_today_rounded,
        accentColor: green,
        child: const SizedBox(
          height: 220,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      );
    }

    return _sectionCard(
      title: 'Today’s Dialysis Schedule',
      subtitle: 'AM and PM shift overview for the selected day.',
      icon: Icons.calendar_today_rounded,
      accentColor: green,
      child: TodayScheduleSection(
        key: _todayScheduleKey,
        clinicId: clinicId!,
        machineCount: machineCount,
        onScheduleChanged: () => _rescheduleRequestsKey.currentState?.load(),
      ),
    );
  }

  /// Patient-submitted reschedule requests, read from the same
  /// `reschedule_requests` rows the mobile app writes. Sits directly under
  /// the donation section, in the same fixed-height scrollable pattern the
  /// other dashboard lists use.
  Widget _buildRescheduleRequestsSection() {
    if (clinicId == null) {
      return _sectionCard(
        title: 'Reschedule Requests',
        subtitle: 'Loading patient reschedule requests.',
        icon: Icons.event_repeat_rounded,
        accentColor: orange,
        child: const SizedBox(
          height: 140,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      );
    }

    return _sectionCard(
      title: 'Reschedule Requests',
      subtitle:
          'Session change requests sent by patients from the mobile app. '
          'Accepting one changes that session only — never the recurring '
          'weekly schedule.',
      icon: Icons.event_repeat_rounded,
      accentColor: orange,
      child: RescheduleRequestsSection(
        key: _rescheduleRequestsKey,
        clinicId: clinicId!,
        onRequestApplied: () =>
            _todayScheduleKey.currentState?.loadSelectedDaySchedule(),
      ),
    );
  }

  Widget _buildDonationCard() {
    final latestAmount = latestDonation?['amount'] ?? 0;
    final latestDate = latestDonation?['received_at'];
    final remarks = latestDonation?['remarks']?.toString();

    final totalSpent = purchaseLogs.fold<num>(
      0,
      (sum, item) => sum + ((item['amount'] as num?) ?? 0),
    );

    final rawRemainingBalance = totalDonations - totalSpent;
    final remainingBalance = rawRemainingBalance < 0 ? 0 : rawRemainingBalance;

    // No fixed height: the purchase log inside already caps its own
    // scroll area, so letting the panel size itself keeps it readable in
    // a narrow window instead of leaving a tall gap in a wide one.
    return _sectionCard(
      title: 'Donation Funds',
      subtitle:
          'Track received support, clinic purchases, and remaining balance.',
      icon: Icons.account_balance_wallet_rounded,
      accentColor: purple,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentPurpleSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDFD4EE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Remaining Balance',
                  style: TextStyle(
                    fontSize: 12,
                    color: textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatMoney(remainingBalance),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _miniFundMetric(
                        'Received',
                        _formatMoney(totalDonations),
                        green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniFundMetric(
                        'Spent',
                        _formatMoney(totalSpent),
                        orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          _infoTile('Latest Donation', _formatMoney(latestAmount)),
          _infoTile('Date Received', _formatDate(latestDate)),

          const SizedBox(height: 10),
          const Text(
            'Remarks',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppTheme.surfaceTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Text(
              remarks == null || remarks.trim().isEmpty
                  ? 'No remarks available.'
                  : remarks,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Purchase Logs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _showAddPurchaseModal,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          SizedBox(
            height: 252,
            child: purchaseLogs.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceTint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: const Center(
                      child: Text(
                        'No purchase logs yet.',
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : Scrollbar(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      physics: purchaseLogs.length > 4
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: purchaseLogs.length,
                      itemBuilder: (context, index) {
                        final item = purchaseLogs[index];

                        return _purchaseLogTile(
                          item['item_name']?.toString() ?? 'Unnamed purchase',
                          _formatDate(item['purchase_date']),
                          (item['amount'] as num?) ?? 0,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniFundMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _purchaseLogTile(String item, String date, num amount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: orange,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '- ${_formatMoney(amount)}',
            style: const TextStyle(
              color: orange,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              color: textDark,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: const Color(0xFFF0CFCF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppTheme.danger, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _connectionError!,
              style: const TextStyle(
                color: Color(0xFF8E3330),
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _refreshDashboard,
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSchedulePatients() {
    return _sectionCard(
      title: 'Patients Needing Schedule',
      subtitle: 'Assign weekly dialysis days to keep patient flow organized.',
      icon: Icons.event_busy_rounded,
      accentColor: orange,
      child: FutureBuilder<List<Patient>>(
        future: _noSchedPatients,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(color: primary)),
            );
          }

          if (snapshot.hasError) {
            return _buildErrorBox('Error loading patients: ${snapshot.error}');
          }

          final patients = snapshot.data ?? [];

          if (patients.isEmpty) {
            return _buildEmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'All patients have schedules',
              subtitle: 'Patients without schedules will appear here.',
            );
          }

          return _buildTableWrapper(
            child: DataTable(
              headingRowHeight: 50,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 62,
              columnSpacing: 48,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(AppTheme.surfaceTint),
              dataRowColor: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.hovered)) {
                  return AppTheme.accentSoft;
                }
                return null;
              }),
              border: TableBorder(
                horizontalInside: BorderSide(color: AppTheme.border, width: 1),
              ),
              columns: const [
                DataColumn(label: Text('Patient')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Phone')),
                DataColumn(label: Text('Guardian')),
                DataColumn(label: Text('Guardian Contact')),
                DataColumn(label: Text('Action')),
              ],
              rows: patients.map((patient) {
                return DataRow(
                  onSelectChanged: (_) => showPatientScheduleModal(
                    context,
                    patient: patient,
                    onScheduled: () {
                      _showMessage('Schedule updated successfully');
                      _loadData();
                    },
                  ),
                  cells: [
                    DataCell(_buildNameCell(patient)),
                    DataCell(Text(patient.email)),
                    DataCell(Text(_safeText(patient.phone))),
                    DataCell(Text(_safeText(patient.emergencyContactName))),
                    DataCell(Text(_safeText(patient.emergencyContactNumber))),
                    const DataCell(
                      Row(
                        children: [
                          Text(
                            'Schedule',
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 5),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                            color: primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTableWrapper({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNameCell(Patient patient) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppTheme.accentSoft,
          child: Text(
            _getInitial(patient.name),
            style: const TextStyle(
              color: primary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          patient.name,
          style: const TextStyle(color: primary, fontWeight: FontWeight.w900),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppTheme.iconMuted),
          const SizedBox(height: 9),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: textDark,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF0CFCF)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.danger,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: const Color(0xFF8E3330),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The No Schedule patient assignment flow (patient info + day/shift
  // selection + live capacity validation + suggested-schedule
  // integration) now lives in showPatientScheduleModal
  // (features/dashboard/patient_schedule_modal.dart), since assigning a
  // recurring schedule now means picking a default SHIFT per day too,
  // backed by CenterScheduleService rather than the old days-only flow.

  Widget _buildMonthlyChart() {
    return _sectionCard(
      title: 'Monthly Patient Growth',
      subtitle: 'Patient growth trend based on recent monthly records.',
      icon: Icons.trending_up_rounded,
      accentColor: primary,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _monthlyData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator(color: primary)),
            );
          }

          if (snapshot.hasError) {
            return _buildErrorBox('Error loading chart: ${snapshot.error}');
          }

          final rawData = snapshot.data ?? [];

          if (rawData.isEmpty) {
            return SizedBox(
              height: 320,
              child: _buildEmptyState(
                icon: Icons.bar_chart_rounded,
                title: 'No chart data available',
                subtitle: 'Monthly patient growth will appear here.',
              ),
            );
          }

          final data = rawData.length > 6
              ? rawData.sublist(rawData.length - 6)
              : rawData;

          final spots = List.generate(
            data.length,
            (index) => FlSpot(
              index.toDouble(),
              (data[index]['count'] as num).toDouble(),
            ),
          );

          final maxYValue = data
              .map((e) => (e['count'] as num).toDouble())
              .fold<double>(0, (prev, e) => e > prev ? e : prev);

          final double maxY = maxYValue <= 0 ? 5.0 : maxYValue + 4;

          return SizedBox(
            height: 320,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 14, 4),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (data.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 5,
                    getDrawingHorizontalLine: (value) =>
                        const FlLine(color: border, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        reservedSize: 34,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < data.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: Text(
                                data[index]['month'].toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: textMuted,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
                        reservedSize: 38,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: border),
                  ),
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) => primary,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            '${spot.y.toInt()} patients',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: primary.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
