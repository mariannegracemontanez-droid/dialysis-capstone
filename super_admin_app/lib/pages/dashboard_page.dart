import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../models/center_model.dart';
import '../models/donation_summary.dart';
import '../models/notification_item.dart';
import '../models/user_model.dart';
import '../services/dashboard_service.dart';
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

  static const Color primaryColor = Color(0xFF174E71);
  static const Color accentColor = Color(0xFF1F719F);
  static const Color bgColor = Color(0xFFF4F7FA);
  static const Color textDark = Color(0xFF102A43);
  static const Color mutedText = Color(0xFF6B7280);

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
        children: [
          _buildSidebar(),
          Expanded(
            child: Stack(
              children: [
                Container(
                  color: bgColor,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: _buildContent(user),
                    ),
                  ),
                ),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withOpacity(0.72),
                      child: const Center(
                        child: CircularProgressIndicator(color: accentColor),
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
    return Container(
      width: 285,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B1D2A), Color(0xFF103C55), Color(0xFF174E71)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 38),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    'assets/images/CureNurture_CircleLogo.png',
                    width: 42,
                    height: 42,
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CureNurture',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Super Admin Portal',
                        style: TextStyle(
                          color: Color(0xB3FFFFFF),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 34),

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
            label: 'Distribute Donation',
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.health_and_safety_rounded,
                    color: Colors.white.withOpacity(0.90),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Manage centers, patients, and dialysis support efficiently.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF174E71),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            '© 2026 CureNurture',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.42),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 22),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(user),

          const SizedBox(height: 24),

          _buildSummaryGrid(
            totalMachines: totalMachines,
            totalSlots: totalSlots,
            activeCenters: activeCenters,
          ),

          const SizedBox(height: 24),

          _buildOperationsBanner(),

          const SizedBox(height: 24),

          // FULL WIDTH CENTER SECTION
          _buildCenterGrid(width),
        ],
      ),
    );
  }

  Widget _buildHeader(UserModel? user) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174E71), Color(0xFF1F719F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A174E71),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: const Icon(
              Icons.monitor_heart_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dialysis Center Operations Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Track center availability, machine capacity, patient flow, and donation support in one place.',
                  style: TextStyle(
                    color: Color(0xDFFFFFFF),
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 35,
                  child: ElevatedButton.icon(
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryColor,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  height: 60,
                  child: _headerInfoChip(
                    Icons.access_time_rounded,
                    'Today',
                    _formattedToday(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerInfoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const spacing = 18.0;

        final useOneRow = width >= 1000;

        if (useOneRow) {
          final donationWidth = width * 0.35;
          final normalCardWidth = (width - donationWidth - (spacing * 3)) / 3;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: normalCardWidth,
                height: 160,
                child: _DashboardMetric(
                  label: 'Active Centers',
                  value: '$activeCenters / ${_centers.length}',
                  icon: Icons.local_hospital_rounded,
                  color: const Color(0xFF059669),
                  note: 'Centers open based on operating hours',
                ),
              ),
              const SizedBox(width: spacing),
              SizedBox(
                width: normalCardWidth,
                height: 160,
                child: _DashboardMetric(
                  label: 'Available Slots',
                  value: '$totalSlots',
                  icon: Icons.airline_seat_flat_rounded,
                  color: const Color(0xFFEA580C),
                  note: 'Remaining dialysis session capacity',
                ),
              ),
              const SizedBox(width: spacing),
              SizedBox(
                width: normalCardWidth,
                height: 160,
                child: _DashboardMetric(
                  label: 'Dialysis Machines',
                  value: '$totalMachines',
                  icon: Icons.precision_manufacturing_rounded,
                  color: const Color(0xFF0891B2),
                  note: 'Total machines across centers',
                ),
              ),
              const SizedBox(width: spacing),
              SizedBox(
                width: donationWidth,
                height: 160,
                child: _DashboardMetric(
                  label: 'Donation Fund',
                  value: _formatPeso(_stats['donations'] ?? 0),
                  icon: Icons.volunteer_activism_rounded,
                  color: const Color(0xFFDB2777),
                  note: 'Verified donations only',
                  isWide: true,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _mobileKpiRow(
              left: _DashboardMetric(
                label: 'Active Centers',
                value: '$activeCenters / ${_centers.length}',
                icon: Icons.local_hospital_rounded,
                color: const Color(0xFF059669),
                note: 'Centers open based on operating hours',
              ),
              right: _DashboardMetric(
                label: 'Available Slots',
                value: '$totalSlots',
                icon: Icons.airline_seat_flat_rounded,
                color: const Color(0xFFEA580C),
                note: 'Remaining dialysis session capacity',
              ),
            ),
            const SizedBox(height: spacing),
            _mobileKpiRow(
              left: _DashboardMetric(
                label: 'Dialysis Machines',
                value: '$totalMachines',
                icon: Icons.precision_manufacturing_rounded,
                color: const Color(0xFF0891B2),
                note: 'Total machines across centers',
              ),
              right: _DashboardMetric(
                label: 'Donation Fund',
                value: _formatPeso(_stats['donations'] ?? 0),
                icon: Icons.volunteer_activism_rounded,
                color: const Color(0xFFDB2777),
                note: 'Verified donations only',
                isWide: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mobileKpiRow({required Widget left, required Widget right}) {
    return Row(
      children: [
        Expanded(child: SizedBox(height: 155, child: left)),
        const SizedBox(width: 18),
        Expanded(child: SizedBox(height: 155, child: right)),
      ],
    );
  }

  Widget _buildOperationsBanner() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7EEF4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _bannerStep(
            Icons.assignment_turned_in_rounded,
            'Verify Capacity',
            'Review machine count, slots, and shift schedules.',
          ),
          _bannerDivider(),
          _bannerStep(
            Icons.groups_2_rounded,
            'Coordinate Patients',
            'Keep center availability visible for smoother referrals.',
          ),
          _bannerDivider(),
          _bannerStep(
            Icons.volunteer_activism_rounded,
            'Support Treatment',
            'Monitor donation assistance and dialysis-related needs.',
          ),
        ],
      ),
    );
  }

  Widget _bannerStep(IconData icon, String title, String description) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerDivider() {
    return Container(
      width: 1,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      color: const Color(0xFFE5EAF0),
    );
  }

  Widget _buildCenterGrid(double width) {
    final crossAxisCount = width > 1600
        ? 3
        : width > 1100
        ? 2
        : 1;
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
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.55,
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _showCenterDetailsModal(center),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE5EAF0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x07000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            Icons.local_hospital_rounded,
                            color: statusColor,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            center.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        _statusChip(statusLabel, statusColor),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.open_in_new_rounded,
                          color: mutedText,
                          size: 18,
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: (occupancy / 100).clamp(0.0, 1.0),
                        color: statusColor,
                        backgroundColor: statusColor.withOpacity(0.12),
                        minHeight: 9,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Text(
                          '${occupancy.toStringAsFixed(0)}% Occupied',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Slots left: $slots',
                          style: const TextStyle(
                            color: mutedText,
                            fontSize: 12.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 15,
                          color: mutedText,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            center.operatingHours,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: mutedText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 7),

                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 15,
                          color: mutedText,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            center.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    Row(
                      children: [
                        _miniStat('Machines', center.machines.toString()),
                        const SizedBox(width: 10),
                        _miniStat('Slots', center.availableSlots.toString()),
                        const SizedBox(width: 10),
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
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFE7EEF4)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 28,
                        offset: Offset(0, 18),
                      ),
                    ],
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
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                Icons.local_hospital_rounded,
                                color: statusColor,
                                size: 30,
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
                                      color: textDark,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    center.address,
                                    style: const TextStyle(
                                      color: mutedText,
                                      fontSize: 13.5,
                                      height: 1.35,
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
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FBFD),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFE7EEF4)),
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
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Slots left: $slots',
                                    style: const TextStyle(
                                      color: mutedText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: LinearProgressIndicator(
                                  value: (occupancy / 100).clamp(0.0, 1.0),
                                  color: statusColor,
                                  backgroundColor: statusColor.withOpacity(
                                    0.12,
                                  ),
                                  minHeight: 11,
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
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 20),
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
                    color: mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.isEmpty ? '--' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 13.5,
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

  Widget _modalDetailBlock({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accentColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value.isEmpty ? '--' : value,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 12.8,
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

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE7EEF4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 12.8,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 20),
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
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7EEF4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: mutedText),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6FAFD),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7EEF4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                color: mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textDark,
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

class _DashboardMetric extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;
  final bool isWide;

  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.color,
    this.isWide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isWide ? 20 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7EEF4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: isWide ? _wideLayout() : _normalLayout(),
    );
  }

  Widget _normalLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _iconBox(size: 44, iconSize: 22),
            const Spacer(),
            Icon(
              Icons.trending_up_rounded,
              size: 18,
              color: color.withOpacity(0.65),
            ),
          ],
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF102A43),
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF102A43),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          note,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _wideLayout() {
    return Row(
      children: [
        _iconBox(size: 48, iconSize: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF102A43),
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF102A43),
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _iconBox({double size = 48, double iconSize = 24}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Icon(icon, color: color, size: iconSize),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withOpacity(0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.white.withOpacity(0.22) : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          hoverColor: Colors.white.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? Colors.white
                      : Colors.white.withOpacity(0.68),
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white.withOpacity(0.68),
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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
