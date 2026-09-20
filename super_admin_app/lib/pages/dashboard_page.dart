import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../models/center_model.dart';
import '../models/donation_summary.dart';
import '../models/notification_item.dart';
import '../models/user_model.dart';
import '../services/dashboard_service.dart';
import '../theme/app_theme.dart';
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

  Map<String, int> _stats = {
    'patients': 0,
    'appointments': 0,
    'centers': 0,
    'donations': 0,
  };

  String _formatPeso(int amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );

    return formatter.format(amount);
  }

  List<CenterModel> _centers = [];
  List<DonationSummary> _donationTotals = [];

  Timer? _clockTimer;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Presentation tokens, sourced from the shared palette.
  static const Color primaryColor = AppTheme.blue1;
  static const Color bgColor = AppTheme.canvas;
  static const Color mutedText = AppTheme.textMuted;

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

    SupabaseConfig.client.from('donations').stream(primaryKey: ['id']).listen((
      data,
    ) {
      if (!mounted) return;

      int totalDonations = 0;

      for (final item in data) {
        final status = item['status']?.toString().toLowerCase().trim() ?? '';

        if (status != 'verified') continue;

        final amount =
            double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;

        totalDonations += amount.toInt();
      }

      setState(() {
        _stats['donations'] = totalDonations;
      });
    });

    SupabaseConfig.client.from('clinics').stream(primaryKey: ['id']).listen((
      data,
    ) {
      if (!mounted) return;

      setState(() {
        _centers = data.map((e) => CenterModel.fromJson(e)).toList();
      });
    });

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final stats = await _dashboardService.fetchOverviewStats();
      final centers = await _dashboardService.fetchCenters();
      final verifiedDonationTotal = await _fetchVerifiedDonationTotal();

      stats['donations'] = verifiedDonationTotal;

      if (!mounted) return;

      setState(() {
        _stats = stats;
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _logout() {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<int> _fetchVerifiedDonationTotal() async {
    final response = await SupabaseConfig.client
        .from('donations')
        .select('amount')
        .eq('status', 'verified');

    int totalDonations = 0;

    for (final item in response) {
      final amount = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
      totalDonations += amount.toInt();
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

    final activeCenters = _centers
        .where((center) => _isOpenNow(center.operatingHours))
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
          final totalCapacity = machine * shifts;
          final usedSlots = (totalCapacity - slots).clamp(0, totalCapacity);
          final occupancy = totalCapacity > 0
              ? (usedSlots / totalCapacity) * 100
              : 0.0;

          final isOpen = _isOpenNow(center.operatingHours);
          final dbStatus = center.status.toLowerCase();

          final statusColor = !isOpen
              ? const Color(0xFF6B7280)
              : _statusColor(dbStatus);

          String statusLabel;

          if (totalCapacity == 0) {
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

                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (occupancy / 100).clamp(0.0, 1.0),
                        color: statusColor,
                        backgroundColor: statusColor.withValues(alpha: 0.12),
                        minHeight: 6,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: _statusChip(statusLabel, statusColor),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${occupancy.toStringAsFixed(0)}% Occupied',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
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
    final slots = center.availableSlots;
    final totalCapacity = machine * shifts;
    final usedSlots = (totalCapacity - slots).clamp(0, totalCapacity);
    final occupancy = totalCapacity > 0
        ? (usedSlots / totalCapacity) * 100
        : 0.0;

    final isOpen = _isOpenNow(center.operatingHours);
    final dbStatus = center.status.toLowerCase();
    final statusColor = !isOpen
        ? const Color(0xFF6B7280)
        : _statusColor(dbStatus);

    String statusLabel;
    if (totalCapacity == 0) {
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

                        const SizedBox(height: 24),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceTint,
                            borderRadius: BorderRadius.circular(AppTheme.rLg),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${occupancy.toStringAsFixed(0)}% Occupied',
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Slots left: $slots',
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: (occupancy / 100).clamp(0.0, 1.0),
                                  color: statusColor,
                                  backgroundColor: statusColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          ),
                        ),

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
                            _modalInfoTile(
                              Icons.people_alt_rounded,
                              'Total Patients',
                              center.totalPatients.toString(),
                            ),
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

  Widget _smallInfo(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFD),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: mutedText, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: mutedText,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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

  bool _isOpenNow(String? hours) {
    if (hours == null || !hours.contains('-')) return false;

    try {
      final parts = hours.split('-');
      final open = _parseSimpleTime(parts[0]);
      final close = _parseSimpleTime(parts[1]);

      final now = TimeOfDay.now();

      final nowMin = now.hour * 60 + now.minute;
      final openMin = open.hour * 60 + open.minute;
      final closeMin = close.hour * 60 + close.minute;

      return nowMin >= openMin && nowMin <= closeMin;
    } catch (e) {
      return false;
    }
  }

  TimeOfDay _parseSimpleTime(String timeStr) {
    final cleaned = timeStr.trim().toUpperCase();

    final regex = RegExp(r'(\d{1,2}):?(\d{2})?\s*(AM|PM)');
    final match = regex.firstMatch(cleaned);

    if (match == null) throw Exception("Invalid time format");

    int hour = int.parse(match.group(1)!);
    int minute = int.parse(match.group(2) ?? '0');
    String period = match.group(3)!;

    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _openCloseText(String? hours) {
    if (hours == null || !hours.contains('-')) return 'No hours set';

    try {
      final parts = hours.split('-');

      final now = TimeOfDay.now();
      final open = _parseSimpleTime(parts[0]);
      final close = _parseSimpleTime(parts[1]);

      final nowMin = now.hour * 60 + now.minute;
      final openMin = open.hour * 60 + open.minute;
      final closeMin = close.hour * 60 + close.minute;

      if (nowMin >= openMin && nowMin <= closeMin) {
        return 'Closes at ${parts[1].trim()}';
      } else {
        return 'Opens at ${parts[0].trim()}';
      }
    } catch (_) {
      return hours;
    }
  }

  String _formatTimeAgo(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);

    if (difference.inSeconds < 60) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hr ago';
    return '${difference.inDays} day(s) ago';
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

  Future<void> _showAddCenterDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final machinesController = TextEditingController();
    final slotsController = TextEditingController();
    final hoursController = TextEditingController(text: '7:00 AM - 5:00 PM');
    final contactController = TextEditingController();
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final messenger = ScaffoldMessenger.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Center'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextField(
                        controller: nameController,
                        label: 'Center Name',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: addressController,
                        label: 'Address',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: machinesController,
                        label: 'Number of Machines',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: slotsController,
                        label: 'Available Slots',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: hoursController,
                        label: 'Operating Hours',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: contactController,
                        label: 'Contact Number',
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            await _dashboardService.createCenter(
                              name: nameController.text.trim(),
                              address: addressController.text.trim(),
                              city: 'Unknown',
                              requirements: 'N/A',
                              latitude: 0.0,
                              longitude: 0.0,
                              slotAvailable:
                                  int.tryParse(slotsController.text.trim()) ??
                                  0,
                              machines:
                                  int.tryParse(
                                    machinesController.text.trim(),
                                  ) ??
                                  0,
                              shifts: 2,
                              operatingHours: hoursController.text.trim(),
                              contactNumber: contactController.text.trim(),
                            );

                            Navigator.pop(context);

                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Center added successfully.'),
                              ),
                            );
                          } catch (error) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Unable to add center: ${error.toString()}',
                                ),
                              ),
                            );
                          } finally {
                            setDialogState(() {
                              isSaving = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showExportDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Export Reports'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: const Text(
            'Choose the data type you want to export and select PDF or CSV format.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reports export started.')),
                );
              },
              child: const Text('Export CSV'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: (value) =>
          (value == null || value.isEmpty) ? 'This field is required' : null,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
    );
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
