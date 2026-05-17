// ignore_for_file: deprecated_member_use, prefer_final_fields, unused_field

import 'package:admin_panel/features/dashboard/today_schedule_section.dart';
import 'package:admin_panel/services/dashboard_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/patient.dart';
import '../auth/login_page.dart';
import '../patients/patients_page.dart';

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

class _DashboardPageState extends ConsumerState<DashboardPage>
    with TickerProviderStateMixin {
  final DashboardService _service = DashboardService();

  late Future<int> _totalPatients;
  late Future<int> _pendingPatientsCount;
  late Future<List<Map<String, dynamic>>> _monthlyData;
  late Future<List<Patient>> _noSchedPatients;

  int _selectedNavIndex = 0;
  late AnimationController _fadeController;
  String? _connectionError;

  String? clinicId;
  String centerName = 'Valenzuela Dialysis Center';
  int machineCount = 10;

  Map<String, dynamic>? latestDonation;
  num totalDonations = 0;
  List<Map<String, dynamic>> purchaseLogs = [];

  static const Color primary = Color(0xFF245C78);
  static const Color primaryDark = Color(0xFF17435C);
  static const Color background = Color(0xFFF4F8FB);
  static const Color border = Color(0xFFE1E8EF);
  static const Color textDark = Color(0xFF1F2D3D);
  static const Color textMuted = Color(0xFF6B7A8C);
  static const Color green = Color(0xFF10B981);
  static const Color orange = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF8E44AD);

  @override
  void initState() {
    super.initState();

    _initAnimations();
    _loadData();
    _verifyDatabaseConnection();
    loadClinicData();
    fetchDonationData();

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
      final latest = await _service.getLatestDonation(centerName);
      final total = await _service.getTotalDonations(centerName);

      final logs = await Supabase.instance.client
          .from('donation_purchase_logs')
          .select()
          .eq('clinic_name', centerName)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        latestDonation = latest;
        totalDonations = total;
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
      _showMessage('Failed to add purchase log: $e', isError: true);
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
      final date = DateTime.parse(value.toString());
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return value.toString();
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(18),
      ),
    );
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
      (route) => false,
    );
  }

  void _showAddPurchaseModal() {
    final itemController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 430,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
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
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: purple.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: purple,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Purchase Log',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: textDark,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Record clinic expenses and automatically update the remaining donation balance.',
                            style: TextStyle(
                              fontSize: 12,
                              color: textMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                const Text(
                  'Purchase Item',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textMuted,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: itemController,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ex. Dialyzer supplies',
                    prefixIcon: const Icon(
                      Icons.inventory_2_outlined,
                      color: textMuted,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: purple, width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'Amount Spent',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textMuted,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixIcon: Container(
                      alignment: Alignment.center,
                      width: 56,
                      child: const Text(
                        '₱',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: purple,
                        ),
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: purple, width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 26),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textMuted,
                          side: BorderSide(color: border),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          final itemName = itemController.text.trim();
                          final amount =
                              num.tryParse(amountController.text.trim()) ?? 0;

                          if (itemName.isEmpty || amount <= 0) {
                            _showMessage(
                              'Please enter a valid item and amount',
                              isError: true,
                            );
                            return;
                          }

                          final currentSpent = purchaseLogs.fold<num>(
                            0,
                            (sum, item) =>
                                sum + ((item['amount'] as num?) ?? 0),
                          );

                          final currentRemainingBalance =
                              totalDonations - currentSpent;

                          if (amount > currentRemainingBalance) {
                            _showMessage(
                              'Amount exceeds the remaining donation balance',
                              isError: true,
                            );
                            return;
                          }

                          Navigator.pop(context);

                          await _addPurchaseLog(
                            itemName: itemName,
                            amount: amount,
                          );
                        },
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text(
                          'Save Log',
                          style: TextStyle(fontWeight: FontWeight.w800),
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
  }

  Future<void> _refreshDashboard() async {
    _loadData();
    await loadClinicData();
    await fetchDonationData();
    await _verifyDatabaseConnection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: FadeTransition(
              opacity: _fadeController.drive(Tween<double>(begin: 0, end: 1)),
              child: _buildMainContent(),
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

            if (index == 1) {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const PatientsPage(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                ),
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

  Widget _buildCenterMiniCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.health_and_safety_rounded,
              color: Colors.white,
              size: 23,
            ),
            const SizedBox(height: 10),
            Text(
              capitalizeWords(centerName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$machineCount dialysis machines',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Text(
            '© 2026 CureNurture',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_connectionError != null) ...[
            _buildConnectionError(),
            const SizedBox(height: 18),
          ],
          _buildHeroOverview(),
          const SizedBox(height: 18),
          _buildKPIRow(),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    _buildTodaysScheduleSection(),
                    const SizedBox(height: 18),
                    _buildMonthlyChart(),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildDonationCard(),
                    const SizedBox(height: 18),
                    _buildOperationsPanel(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildNoSchedulePatients(),
        ],
      ),
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
              colors: [primaryDark, primary, Color(0xFF3F91A9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.16),
                blurRadius: 16,
                offset: const Offset(0, 7),
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
                      'CENTER OPERATIONS',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      clinicName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Daily workspace for dialysis scheduling, patient monitoring, and transparent center operations.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _refreshDashboard,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKPIRow() {
    return FutureBuilder<List<Patient>>(
      future: _noSchedPatients,
      builder: (context, noSchedSnapshot) {
        final noSchedCount = noSchedSnapshot.data?.length ?? 0;

        return Row(
          children: [
            Expanded(
              child: FutureBuilder<int>(
                future: _totalPatients,
                builder: (context, snapshot) {
                  return _buildKPICard(
                    title: 'Total Patients',
                    value: snapshot.data?.toString() ?? '0',
                    icon: Icons.groups_rounded,
                    color: primary,
                    subtitle: 'Registered records',
                  );
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: FutureBuilder<int>(
                future: _pendingPatientsCount,
                builder: (context, snapshot) {
                  return _buildKPICard(
                    title: 'Pending',
                    value: snapshot.data?.toString() ?? '0',
                    icon: Icons.pending_actions_rounded,
                    color: purple,
                    subtitle: 'Awaiting approval',
                  );
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildKPICard(
                title: 'Need Schedule',
                value: noSchedCount.toString(),
                icon: Icons.event_busy_rounded,
                color: orange,
                subtitle: 'No weekly schedule',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF91A0AF),
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

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
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
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
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
          child: Center(child: CircularProgressIndicator(color: primary)),
        ),
      );
    }

    return _sectionCard(
      title: 'Today’s Dialysis Schedule',
      subtitle: 'AM and PM shift overview for the selected day.',
      icon: Icons.calendar_today_rounded,
      accentColor: green,
      child: TodayScheduleSection(
        clinicId: clinicId!,
        machineCount: machineCount,
      ),
    );
  }

  Widget _buildDonationCard() {
    final latestAmount = latestDonation?['amount'] ?? 0;
    final latestDate = latestDonation?['distribution_date'];
    final remarks = latestDonation?['remarks']?.toString();

    final totalSpent = purchaseLogs.fold<num>(
      0,
      (sum, item) => sum + ((item['amount'] as num?) ?? 0),
    );

    final rawRemainingBalance = totalDonations - totalSpent;
    final remainingBalance = rawRemainingBalance < 0 ? 0 : rawRemainingBalance;

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
              color: const Color(0xFFF8F5FC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEBDDFA)),
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
              color: const Color(0xFFF8FAFC),
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
                color: Color(0xFF4A5568),
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

          if (purchaseLogs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
              ),
              child: const Text(
                'No purchase logs yet.',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...purchaseLogs.map(
              (item) => _purchaseLogTile(
                item['item_name']?.toString() ?? 'Unnamed purchase',
                _formatDate(item['purchase_date']),
                item['amount'] as num,
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
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.18)),
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: orange.withOpacity(0.12),
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
        color: const Color(0xFFF8FAFC),
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

  Widget _buildOperationsPanel() {
    return _sectionCard(
      title: 'Center Checklist',
      subtitle: 'Daily admin priorities.',
      icon: Icons.fact_check_rounded,
      accentColor: const Color(0xFF0EA5E9),
      child: FutureBuilder<List<Patient>>(
        future: _noSchedPatients,
        builder: (context, snapshot) {
          final noSchedCount = snapshot.data?.length ?? 0;

          return Column(
            children: [
              _checklistItem(
                Icons.event_available_rounded,
                'Review schedule',
                'Confirm patients per shift.',
                'Daily',
                green,
              ),
              _checklistItem(
                Icons.person_add_alt_1_rounded,
                'Approve registrations',
                'Review pending patient access.',
                'Review',
                purple,
              ),
              _checklistItem(
                Icons.assignment_late_rounded,
                'Assign schedules',
                '$noSchedCount patient(s) still need scheduling.',
                noSchedCount == 0 ? 'Clear' : 'Needed',
                orange,
              ),
              _checklistItem(
                Icons.health_and_safety_rounded,
                'Monitor capacity',
                '$machineCount machines available.',
                'Active',
                primary,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _checklistItem(
    IconData icon,
    String title,
    String subtitle,
    String status,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade600),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              _connectionError!,
              style: TextStyle(
                color: Colors.red.shade800,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
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
              headingRowColor: MaterialStateProperty.all(
                const Color(0xFFF4F7FA),
              ),
              dataRowColor: MaterialStateProperty.resolveWith<Color?>((states) {
                if (states.contains(MaterialState.hovered)) {
                  return const Color(0xFFEAF5FA);
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
                DataColumn(label: Text('Patient')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Phone')),
                DataColumn(label: Text('Guardian')),
                DataColumn(label: Text('Guardian Contact')),
                DataColumn(label: Text('Action')),
              ],
              rows: patients.map((patient) {
                return DataRow(
                  onSelectChanged: (_) => _showPatientModal(patient),
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
          backgroundColor: const Color(0xFFEAF5FA),
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFF9AA9B8)),
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
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPatientModal(Patient patient) {
    final selectedDays = <String>{};

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 760,
                constraints: const BoxConstraints(maxHeight: 740),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 26,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(26),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [primaryDark, primary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.white,
                                child: Text(
                                  _getInitial(patient.name),
                                  style: const TextStyle(
                                    color: primary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patient.name,
                                      style: const TextStyle(
                                        fontSize: 23,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      patient.email,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Patient Information',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  color: textDark,
                                ),
                              ),
                              const SizedBox(height: 15),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final details = [
                                    _buildPatientDetailRow(
                                      'Name',
                                      patient.name,
                                    ),
                                    _buildPatientDetailRow(
                                      'Email',
                                      patient.email,
                                    ),
                                    _buildPatientDetailRow(
                                      'Phone',
                                      _safeText(patient.phone),
                                    ),
                                    _buildPatientDetailRow(
                                      'Date of Birth',
                                      patient.birthDate
                                              ?.toString()
                                              .split(' ')
                                              .first ??
                                          'N/A',
                                    ),
                                    _buildPatientDetailRow(
                                      'Blood Type',
                                      _safeText(patient.bloodType),
                                    ),
                                    _buildPatientDetailRow(
                                      'Guardian',
                                      _safeText(patient.emergencyContactName),
                                    ),
                                    _buildPatientDetailRow(
                                      'Guardian Contact',
                                      _safeText(patient.emergencyContactNumber),
                                    ),
                                    _buildPatientDetailRow(
                                      'Address',
                                      patient.address ??
                                          patient.homeAddress ??
                                          'N/A',
                                    ),
                                  ];

                                  if (constraints.maxWidth < 620) {
                                    return Column(children: details);
                                  }

                                  return Wrap(
                                    spacing: 12,
                                    children: details
                                        .map(
                                          (item) => SizedBox(
                                            width:
                                                (constraints.maxWidth - 12) / 2,
                                            child: item,
                                          ),
                                        )
                                        .toList(),
                                  );
                                },
                              ),
                              const SizedBox(height: 22),
                              const Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    color: primary,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Weekly Schedule',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: textDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Select the dialysis days assigned to this patient.',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 13),
                              _buildWeeklyScheduleSelector(selectedDays, (day) {
                                setDialogState(() {
                                  if (selectedDays.contains(day)) {
                                    selectedDays.remove(day);
                                  } else {
                                    selectedDays.add(day);
                                  }
                                });
                              }),
                              const SizedBox(height: 26),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: textDark,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text('Cancel'),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      if (selectedDays.isEmpty) {
                                        _showMessage(
                                          'Please select at least one day',
                                          isError: true,
                                        );
                                        return;
                                      }

                                      try {
                                        await _service.setPatientSchedule(
                                          patientId: patient.id,
                                          selectedDays: selectedDays.toList(),
                                        );

                                        if (!mounted) return;

                                        Navigator.pop(context);
                                        _showMessage(
                                          'Schedule updated successfully',
                                        );
                                        _loadData();
                                      } catch (error) {
                                        _showMessage(
                                          'Error: $error',
                                          isError: true,
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.save_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Save Schedule'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPatientDetailRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: textMuted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyScheduleSelector(
    Set<String> selectedDays,
    Function(String) onDaySelected,
  ) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    const dayShorts = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: List.generate(days.length, (index) {
        final isSelected = selectedDays.contains(days[index]);

        return FilterChip(
          label: Text(dayShorts[index]),
          selected: isSelected,
          onSelected: (_) => onDaySelected(days[index]),
          backgroundColor: const Color(0xFFF8FAFC),
          selectedColor: primary,
          checkmarkColor: Colors.white,
          side: BorderSide(color: isSelected ? primary : border),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : textDark,
            fontWeight: FontWeight.w900,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        );
      }),
    );
  }

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
                        color: primary.withOpacity(0.10),
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
