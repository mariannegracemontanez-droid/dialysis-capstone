import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../models/center_model.dart';
import '../models/donation_summary.dart';
import '../models/user_model.dart';
import '../services/dashboard_service.dart';
import '../theme/app_theme.dart';
import '../utils/operating_hours.dart';
import 'admin_accounts_page.dart';
import 'center_page.dart';
import 'donations_page.dart';
import '../config/supabase_config.dart';
import 'package:intl/intl.dart';

enum DashboardSection { dashboard, centers, distribution, accountManagement }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  final DashboardService _dashboardService = DashboardService();

  DashboardSection _selectedSection = DashboardSection.dashboard;

  bool _isLoading = false;

  /// Re-entrancy guard for _loadDashboard (R15). Separate from [_isLoading],
  /// which exists to drive the loading indicator: this one is only about
  /// whether a load is already in flight, and it is set synchronously before
  /// the first await so a second Refresh tap in the same frame is stopped.
  bool _isDashboardLoading = false;

  // final since R6: the map is no longer swapped out wholesale (that was the
  // fetchOverviewStats() result being assigned over it) -- its 'donations'
  // entry is written in place by _loadDashboard and the realtime stream.
  // num, not int, so the donation total keeps its centavos end to end (R8).
  // The remaining keys are unchanged and still initialise to 0.
  final Map<String, num> _stats = {
    'patients': 0,
    'appointments': 0,
    'centers': 0,
    'donations': 0,
  };

  // decimalDigits: 2 so the corrected total is actually shown -- at 0 the
  // formatter rounds 351.50 back to a whole peso, which would have hidden the
  // fix behind the display.
  String _formatPeso(num amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return formatter.format(amount);
  }

  List<CenterModel> _centers = [];
  List<DonationSummary> _donationTotals = [];

  Timer? _clockTimer;

  // Retained so both realtime subscriptions can be cancelled in dispose()
  // (R11). Previously the two stream().listen() calls below were fire-and-
  // forget: their `mounted` guards stopped a disposed-widget setState, but
  // the subscriptions themselves stayed open for the life of the process, so
  // every new DashboardPage (each login, for instance) added another pair
  // that kept receiving the full donations and clinics tables forever.
  StreamSubscription<List<Map<String, dynamic>>>? _donationsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _clinicsSubscription;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Presentation tokens, sourced from the shared palette.
  static const Color primaryColor = AppTheme.blue1;
  static const Color bgColor = AppTheme.canvas;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _fadeController.forward();

    _loadDashboard();

    _donationsSubscription = SupabaseConfig.client
        .from('donations')
        .stream(primaryKey: ['id'])
        .listen((data) {
      if (!mounted) return;

      // Accumulated as a double: each amount used to be truncated with
      // .toInt() BEFORE being added, so every donation silently lost its
      // centavos and the error grew with the number of donations (R8).
      // The verified-only filter below is unchanged.
      double totalDonations = 0;

      for (final item in data) {
        final status = item['status']?.toString().toLowerCase().trim() ?? '';

        if (status != 'verified') continue;

        final amount =
            double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;

        totalDonations += amount;
      }

      setState(() {
        _stats['donations'] = totalDonations;
      });
    }, onError: _onRealtimeError);

    _clinicsSubscription = SupabaseConfig.client
        .from('clinics')
        .stream(primaryKey: ['id'])
        .listen((data) {
      if (!mounted) return;

      setState(() {
        // Soft-closed centres are filtered out here so this stream applies
        // the same lifecycle rule as DashboardService.fetchCenters() (which
        // queries `status.is.null,status.neq.closed`). Without this the
        // stream overwrote _centers with EVERY clinic, so a closed centre
        // reappeared in the dashboard's operational figures and grid --
        // and which of the two definitions won depended on whether the
        // stream or the initial load resolved last. Filtered after mapping
        // rather than in the query so the realtime subscription itself is
        // unchanged.
        _centers = data
            .map((e) => CenterModel.fromJson(e))
            .where((center) => !center.isClosed)
            .toList();
      });
    }, onError: _onRealtimeError);

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Both realtime streams previously had no error handler, so a dropped
  /// socket or a rejected read (for example after sign-out, when the channel
  /// is no longer authenticated) surfaced as an unhandled async error rather
  /// than being contained here.
  ///
  /// Nothing is shown to the operator on purpose: these streams only refresh
  /// figures that are already on screen, and the initial load in
  /// _loadDashboard still reports real failures through its own SnackBar.
  /// Raising a toast here would mean repeated noise for a background refresh
  /// the operator did not ask for. The last good values simply stay until the
  /// stream recovers or the page is reloaded.
  void _onRealtimeError(Object error, StackTrace stackTrace) {
    debugPrint('Dashboard realtime update failed: $error');
  }

  @override
  void dispose() {
    // Cancelled so the subscriptions do not outlive this page (R11).
    _donationsSubscription?.cancel();
    _clinicsSubscription?.cancel();
    _clockTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    // Refresh is a plain onPressed with no disabled state, so it could be
    // tapped repeatedly while an earlier load was still awaiting Supabase.
    // That issued overlapping queries and let an older response land after a
    // newer one, overwriting fresh data with stale. Set before the first
    // await, so the second tap returns here rather than starting a load.
    if (_isDashboardLoading) return;
    _isDashboardLoading = true;

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final centers = await _dashboardService.fetchCenters();
      final verifiedDonationTotal = await _fetchVerifiedDonationTotal();

      if (!mounted) return;

      setState(() {
        // Written straight into the existing _stats (initialised above), which
        // is what the Donation Fund card reads. This previously arrived via a
        // map from fetchOverviewStats(), but that map's donation value was
        // overwritten here anyway and its other three values were never read
        // -- so the call and its four full-table scans were removed (R6).
        _stats['donations'] = verifiedDonationTotal;
        _centers = centers;
        _donationTotals = [];
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Dashboard error: $error')));
      }
    } finally {
      // Released unconditionally -- deliberately NOT inside the mounted check
      // below, so the guard can never be left stuck on and block every later
      // refresh. Runs on the success and error paths alike.
      _isDashboardLoading = false;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Ends the Supabase session itself, not just the route stack. Navigating
  /// away alone left the access/refresh tokens live, so the session stayed
  /// valid -- and kept auto-refreshing -- after the operator had logged out.
  ///
  /// signOut() clears the local session before it attempts the server call,
  /// so by the time a network failure can be raised this client is already
  /// signed out locally; only the server-side token revocation is in doubt.
  /// That is why the failure path still navigates: it must never trap the
  /// operator in a session they asked to end. The message says what actually
  /// happened rather than exposing the raw exception.
  Future<void> _logout() async {
    try {
      await SupabaseConfig.client.auth.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Signed out on this device, but the server could not be '
              'reached to fully end the session.',
            ),
          ),
        );
      }
    }

    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  /// Total of VERIFIED donations. The query and its verified-only filter are
  /// unchanged; only the arithmetic is. Each amount used to be truncated with
  /// .toInt() before being added, so 100.50 + 200.75 + 50.25 summed to 350
  /// instead of 351.50 -- the loss compounded per donation (R8). Amounts are
  /// parsed from the numeric column's string form and accumulated as doubles.
  Future<double> _fetchVerifiedDonationTotal() async {
    final response = await SupabaseConfig.client
        .from('donations')
        .select('amount')
        .eq('status', 'verified');

    double totalDonations = 0;

    for (final item in response) {
      final amount = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
      totalDonations += amount;
    }

    return totalDonations;
  }

  @override
  Widget build(BuildContext context) {
    final user = ModalRoute.of(context)?.settings.arguments as UserModel?;

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        // Stretch, so the sidebar and the content area both fill the viewport
        // height. Without it a section shorter than the window floats
        // vertically centred and its scroll view never reaches full height.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebar(),
          Expanded(
            child: Stack(
              children: [
                // No padding here on purpose: each section pads *inside* its
                // own scroll view, so the scrollbar rides the true right edge
                // of the viewport instead of floating inset from it.
                Container(
                  color: bgColor,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildContent(user),
                  ),
                ),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xCCFEFFFE),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.blue1,
                          strokeWidth: 3,
                        ),
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

  Widget _buildSidebar() {
    final sidebarWidth = AppTheme.sidebarWidth(
      MediaQuery.of(context).size.width,
    );

    return Container(
      width: sidebarWidth,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 26),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Image.asset(
                    'assets/images/CureNurture_CircleLogo.png',
                    width: 34,
                    height: 34,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CureNurture',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.blue3,
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Super Admin Portal',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          const Divider(height: 1, thickness: 1, color: AppTheme.border),

          const SizedBox(height: 14),

          _SidebarItem(
            label: 'Dashboard',
            icon: Icons.dashboard_rounded,
            selected: _selectedSection == DashboardSection.dashboard,
            onTap: () {
              setState(() {
                _selectedSection = DashboardSection.dashboard;
              });
            },
          ),
          _SidebarItem(
            label: 'Centers',
            icon: Icons.location_city_rounded,
            selected: _selectedSection == DashboardSection.centers,
            onTap: () {
              setState(() {
                _selectedSection = DashboardSection.centers;
              });
            },
          ),
          _SidebarItem(
            label: 'Donation',
            icon: Icons.volunteer_activism_rounded,
            selected: _selectedSection == DashboardSection.distribution,
            onTap: () {
              setState(() {
                _selectedSection = DashboardSection.distribution;
              });
            },
          ),
          _SidebarItem(
            label: 'Account Management',
            icon: Icons.manage_accounts_rounded,
            selected: _selectedSection == DashboardSection.accountManagement,
            onTap: () {
              setState(() {
                _selectedSection = DashboardSection.accountManagement;
              });
            },
          ),

          const Spacer(),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppTheme.surfaceTint,
                borderRadius: BorderRadius.circular(AppTheme.rLg),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.health_and_safety_rounded,
                    color: AppTheme.blue1,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Manage centers, patients, and dialysis support efficiently.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded, size: 17),
                label: const Text('Log out'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppTheme.surface,
                  foregroundColor: AppTheme.blue3,
                  side: const BorderSide(color: AppTheme.borderStrong),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            '© 2026 CureNurture',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildContent(UserModel? user) {
    switch (_selectedSection) {
      case DashboardSection.centers:
        return ClinicsPage(onUpdated: () {});
      case DashboardSection.distribution:
        return const DonationsPage();
      case DashboardSection.accountManagement:
        return const AccountManagementPage();
      case DashboardSection.dashboard:
        return _buildDashboardHome(user);
    }
  }

  Widget _buildDashboardHome(UserModel? user) {
    final width = MediaQuery.of(context).size.width;

    final totalMachines = _centers.fold<int>(
      0,
      (sum, center) => sum + center.machines,
    );

    final totalSlots = _centers.fold<int>(
      0,
      (sum, center) => sum + center.availableSlots,
    );

    // A soft-closed centre is never an active operational centre, whatever
    // its operating hours say. The stream and fetchCenters() both already
    // exclude closed centres from _centers; this keeps the invariant true
    // at the point of use rather than relying only on how _centers was
    // populated.
    final activeCenters = _centers
        .where(
          (center) =>
              !center.isClosed && isWithinOperatingHours(center.operatingHours),
        )
        .length;

    return SingleChildScrollView(
      padding: EdgeInsets.all(AppTheme.pagePadding(width)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(user),

              const SizedBox(height: AppTheme.gapLg),

              _buildSummaryGrid(
                totalMachines: totalMachines,
                totalSlots: totalSlots,
                activeCenters: activeCenters,
              ),

              const SizedBox(height: AppTheme.gapLg),

              _buildOperationsBanner(),

              const SizedBox(height: AppTheme.gapLg),

              // FULL WIDTH CENTER SECTION
              _buildCenterGrid(width),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(UserModel? user) {
    const title = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderIcon(),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dialysis Center Operations Dashboard',
                style: TextStyle(
                  color: AppTheme.blue3,
                  fontSize: 22,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Track center availability, machine capacity, patient flow, and donation support in one place.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _headerInfoChip(
          Icons.access_time_rounded,
          'Today',
          _formattedToday(),
        ),
        SizedBox(
          height: 40,
          child: ElevatedButton.icon(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: AppTheme.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
              ),
            ),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.white, AppTheme.headerTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 18), actions],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(child: title),
              const SizedBox(width: 24),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _headerInfoChip(IconData icon, String label, String value) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: primaryColor, size: 17),
          const SizedBox(width: 9),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  color: AppTheme.blue3,
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryGrid({
    required int totalMachines,
    required int totalSlots,
    required int activeCenters,
  }) {
    final metrics = <Widget>[
      _DashboardMetric(
        label: 'Active Centers',
        value: '$activeCenters / ${_centers.length}',
        icon: Icons.local_hospital_rounded,
        note: 'Centers open based on operating hours',
      ),
      _DashboardMetric(
        label: 'Available Slots',
        value: '$totalSlots',
        icon: Icons.airline_seat_flat_rounded,
        note: 'Remaining dialysis session capacity',
      ),
      _DashboardMetric(
        label: 'Dialysis Machines',
        value: '$totalMachines',
        icon: Icons.precision_manufacturing_rounded,
        note: 'Total machines across centers',
      ),
      _DashboardMetric(
        label: 'Donation Fund',
        value: _formatPeso(_stats['donations'] ?? 0),
        icon: Icons.volunteer_activism_rounded,
        note: 'Verified donations only',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppTheme.gapMd;
        const cardHeight = 166.0;

        // One row of four for every desktop width; two-up below that.
        final columns = constraints.maxWidth >= 900 ? 4 : 2;

        final rows = <Widget>[];

        for (var start = 0; start < metrics.length; start += columns) {
          final end = (start + columns).clamp(0, metrics.length);
          final slice = metrics.sublist(start, end);

          if (rows.isNotEmpty) {
            rows.add(const SizedBox(height: spacing));
          }

          rows.add(
            Row(
              children: [
                for (var i = 0; i < slice.length; i++) ...[
                  if (i > 0) const SizedBox(width: spacing),
                  Expanded(
                    child: SizedBox(height: cardHeight, child: slice[i]),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(children: rows);
      },
    );
  }

  Widget _buildOperationsBanner() {
    final steps = <Widget>[
      _bannerStep(
        Icons.assignment_turned_in_rounded,
        'Verify Capacity',
        'Review machine count, slots, and shift schedules.',
      ),
      _bannerStep(
        Icons.groups_2_rounded,
        'Coordinate Patients',
        'Keep center availability visible for smoother referrals.',
      ),
      _bannerStep(
        Icons.volunteer_activism_rounded,
        'Support Treatment',
        'Monitor donation assistance and dialysis-related needs.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) _bannerDivider(horizontal: true),
                  steps[i],
                ],
              ],
            );
          }

          return Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) _bannerDivider(),
                Expanded(child: steps[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _bannerStep(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.accentSoft,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
          ),
          child: Icon(icon, color: AppTheme.blue1, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.blue3,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bannerDivider({bool horizontal = false}) {
    if (horizontal) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(height: 1, thickness: 1, color: AppTheme.border),
      );
    }

    return Container(
      width: 1,
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: AppTheme.border,
    );
  }

  Widget _buildCenterGrid(double width) {
    // Three columns on every desktop width; narrower viewports step down.
    final crossAxisCount = AppTheme.centerColumns(width);

    if (_centers.isEmpty) {
      return _emptyStateCard(
        icon: Icons.location_city_outlined,
        title: 'No centers available',
        subtitle: 'Add centers to start monitoring dialysis capacity.',
      );
    }

    return _sectionCard(
      title: 'Valenzuela Dialysis Centers',
      subtitle:
          'Status, capacity, address, hours, machines, available slots, and shifts in one view.',
      icon: Icons.location_city_rounded,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _centers.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppTheme.gapMd,
          mainAxisSpacing: AppTheme.gapMd,
          mainAxisExtent: 234,
        ),
        itemBuilder: (context, index) {
          final center = _centers[index];

          final machine = center.machines;
          final shifts = center.shifts;
          final slots = center.availableSlots;
          // totalCapacity is kept only for the "No Data" status branch below.
          // The occupancy percentage that used to be derived here was removed
          // (R9): it was (totalCapacity - slots_available) / totalCapacity,
          // and the center form stores slots_available AS machines x 2 -- the
          // same figure as totalCapacity -- so it evaluated to 0% for every
          // center saved through the current UI, and clamped to 0% for older
          // rows. It also contradicted the approved live-capacity estimate on
          // the Centers page, which measures real reserved patients.
          final totalCapacity = machine * shifts;

          final isOpen = isWithinOperatingHours(center.operatingHours);
          final dbStatus = center.status.toLowerCase();

          final statusColor = !isOpen
              ? const Color(0xFF6B7280)
              : _statusColor(dbStatus);

          String statusLabel;

          if (center.isClosed) {
            // Lifecycle beats availability and beats operating hours: a
            // soft-closed centre is never labelled Open. Checked before the
            // switch below, which only knows the OPERATIONAL vocabulary and
            // would otherwise fall through its `default` and label 'closed'
            // as 'Open'.
            statusLabel = 'Closed';
          } else if (totalCapacity == 0) {
            statusLabel = 'No Data';
          } else if (!isOpen) {
            statusLabel = 'Closed';
          } else {
            switch (dbStatus) {
              case 'maintenance':
                statusLabel = 'Maintenance';
                break;
              case 'full':
                statusLabel = 'Full';
                break;
              case 'busy':
                statusLabel = 'Busy';
                break;
              case 'open':
              default:
                statusLabel = 'Open';
            }
          }

          return Material(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.rLg),
              onTap: () => _showCenterDetailsModal(center),
              hoverColor: AppTheme.accentSoft,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.rLg),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.shadowSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppTheme.rMd),
                          ),
                          child: Icon(
                            Icons.local_hospital_rounded,
                            color: statusColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            center.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.blue3,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.open_in_new_rounded,
                          color: AppTheme.iconMuted,
                          size: 15,
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // The occupancy progress bar and the "N% Occupied" label
                    // that stood here were removed (R9) -- both rendered the
                    // always-0% figure described above. Nothing replaces them:
                    // the dashboard holds no per-center reserved-patient data,
                    // and inventing one here would duplicate the approved
                    // live-capacity estimate rather than reuse it.
                    Row(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: _statusChip(statusLabel, statusColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Slots left: $slots',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: AppTheme.iconMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            center.operatingHours,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: AppTheme.iconMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            center.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    Row(
                      children: [
                        _miniStat('Machines', center.machines.toString()),
                        const SizedBox(width: 8),
                        _miniStat('Slots', center.availableSlots.toString()),
                        const SizedBox(width: 8),
                        _miniStat('Shifts', center.shifts.toString()),
                      ],
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

  Future<void> _showCenterDetailsModal(CenterModel center) async {
    final machine = center.machines;
    final shifts = center.shifts;
    // Same removal as the center grid (R9): the occupancy percentage derived
    // from slots_available was structurally 0% and conflicted with the
    // approved live-capacity estimate. totalCapacity stays for the "No Data"
    // status branch below.
    final totalCapacity = machine * shifts;

    final isOpen = isWithinOperatingHours(center.operatingHours);
    final dbStatus = center.status.toLowerCase();
    final statusColor = !isOpen
        ? const Color(0xFF6B7280)
        : _statusColor(dbStatus);

    String statusLabel;
    if (center.isClosed) {
      // Same lifecycle-beats-availability rule as the centre grid above.
      statusLabel = 'Closed';
    } else if (totalCapacity == 0) {
      statusLabel = 'No Data';
    } else if (!isOpen) {
      statusLabel = 'Closed';
    } else {
      switch (dbStatus) {
        case 'maintenance':
          statusLabel = 'Maintenance';
          break;
        case 'full':
          statusLabel = 'Full';
          break;
        case 'busy':
          statusLabel = 'Busy';
          break;
        case 'open':
        default:
          statusLabel = 'Open';
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 28,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rXl),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rXl),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.shadowMd,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rLg,
                                ),
                              ),
                              child: Icon(
                                Icons.local_hospital_rounded,
                                color: statusColor,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    center.name,
                                    style: const TextStyle(
                                      color: AppTheme.blue3,
                                      fontSize: 21,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    center.address,
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            _statusChip(statusLabel, statusColor),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),

                        // The occupancy panel that stood here was removed
                        // (R9): it showed the always-0% figure plus a
                        // "Slots left" reading of the same stored
                        // slots_available value. The modal already lists
                        // Available Slots on its own tile below, so nothing
                        // unique was lost and nothing replaces it.

                        const SizedBox(height: 18),

                        GridView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 2.2,
                              ),
                          children: [
                            _modalInfoTile(
                              Icons.precision_manufacturing_rounded,
                              'Machines',
                              center.machines.toString(),
                            ),
                            _modalInfoTile(
                              Icons.airline_seat_flat_rounded,
                              'Available Slots',
                              center.availableSlots.toString(),
                            ),
                            _modalInfoTile(
                              Icons.schedule_rounded,
                              'Shifts',
                              center.shifts.toString(),
                            ),
                            // No "Total Patients" tile: it read
                            // clinics.total_patients, a column nothing in any
                            // app or migration has ever written, so it showed
                            // 0 for every center regardless of reality. It is
                            // removed rather than recalculated because this
                            // app defines no per-center patient total -- the
                            // only per-center patient query is the capacity
                            // RESERVED count, which is a different figure and
                            // is deliberately left alone.
                            _modalInfoTile(
                              Icons.access_time_rounded,
                              'Operating Hours',
                              center.operatingHours,
                            ),
                            _modalInfoTile(
                              Icons.call_rounded,
                              'Contact Number',
                              center.contactNumber,
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        _modalDetailBlock(
                          icon: Icons.checklist_rounded,
                          title: 'Requirements',
                          value: center.requirements.isEmpty
                              ? 'No requirements listed.'
                              : center.requirements,
                        ),

                        const SizedBox(height: 12),

                        _modalDetailBlock(
                          icon: Icons.location_on_rounded,
                          title: 'Center Address',
                          value: center.address,
                        ),

                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _modalInfoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.blue1, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.isEmpty ? '--' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.blue3,
                    fontSize: 13,
                    height: 1.25,
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

  Widget _modalDetailBlock({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.blue1, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.blue3,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value.isEmpty ? '--' : value,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
                child: Icon(icon, color: AppTheme.blue1, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.blue3,
                        fontSize: 16.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _emptyStateCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppTheme.iconMuted),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.blue3,
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceTint,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.2,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: AppTheme.blue3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'open':
        return const Color(0xFF1F9D55);
      case 'busy':
        return const Color(0xFFED8F12);
      case 'full':
        return const Color(0xFFB91C1C);
      case 'maintenance':
      // Soft-closed: the same muted grey the !isOpen path already uses, so
      // a closed centre is never tinted like an active operational one.
      case CenterModel.closedStatus:
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF2563EB);
    }
  }

  String _formattedToday() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

}

/// Header emblem for the dashboard banner.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.borderStrong),
      ),
      child: const Icon(
        Icons.monitor_heart_rounded,
        color: AppTheme.blue1,
        size: 24,
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;

  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
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
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
                child: Icon(icon, color: AppTheme.blue1, size: 19),
              ),
              const Spacer(),
              const Icon(
                Icons.trending_up_rounded,
                size: 16,
                color: AppTheme.iconMuted,
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.blue3,
                fontSize: 24,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // Fixed two-line box so the values line up across the row whether or
          // not a note wraps.
          SizedBox(
            height: 30,
            child: Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppTheme.white : AppTheme.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? AppTheme.blue1 : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          onTap: onTap,
          hoverColor: selected ? Colors.transparent : AppTheme.accentSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? AppTheme.white : AppTheme.iconMuted,
                  size: 19,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13.5,
                      height: 1.25,
                      letterSpacing: 0.1,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
