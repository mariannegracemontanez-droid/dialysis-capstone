// ignore_for_file: deprecated_member_use, prefer_final_fields, unused_field

import 'package:admin_panel/services/dashboard_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_panel/features/dashboard/today_schedule_section.dart';
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

   Widget _buildTodaysScheduleSection() {
      if (clinicId == null) {
        return const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF2A5F7E),
          ),
        );
      }

      return _sectionCard(
        title: 'Today’s Schedule',
        subtitle: 'AM and PM shift scheduling for selected day.',
        icon: Icons.calendar_today_rounded,
        accentColor: const Color(0xFF10B981),
        child: TodayScheduleSection(
          clinicId: clinicId!,
          machineCount: machineCount,
        ),
      );
    }

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
  }

  Future<void> fetchDonationData() async {
    try {
      final latest = await _service.getLatestDonation(centerName);
      final total = await _service.getTotalDonations(centerName);

      if (!mounted) return;

      setState(() {
        latestDonation = latest;
        totalDonations = total;
      });
    } catch (e) {
      debugPrint('Error fetching donation data: $e');
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

  Future<void> _verifyDatabaseConnection() async {
    try {
      await _service.getTotalPatients();
    } catch (e) {
      setState(() {
        _connectionError =
            'Unable to connect to database. Please check your Supabase configuration.';
      });
    }
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
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
        backgroundColor:
            isError ? Colors.red.shade600 : const Color(0xFF2A5F7E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: FadeTransition(
              opacity: _fadeController.drive(
                Tween<double>(begin: 0.0, end: 1.0),
              ),
              child: _buildMainContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 230,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF2A5F7E),
            Color(0xFF1F526E),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 26),
          _buildLogo(),
          const SizedBox(height: 44),
          _buildNavItem(0, Icons.dashboard_rounded, 'Dashboard'),
          _buildNavItem(1, Icons.people_rounded, 'Patients'),
          const Spacer(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: Image.asset(
                'images/CureNurture_CircleLogo.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.local_hospital_rounded,
                  color: Color(0xFF2A5F7E),
                  size: 28,
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
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
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
                        fontSize: 11,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF174762) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: Colors.white24, width: 1)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : Colors.white70,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
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

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(20),
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
                foregroundColor: const Color(0xFF2A5F7E),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '© 2025 CureNurture',
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
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          const SizedBox(height: 24),
          if (_connectionError != null) ...[
            _buildConnectionError(),
            const SizedBox(height: 20),
          ],
          _buildKPIRow(),
          const SizedBox(height: 24),
          _buildTodaysScheduleSection(),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: _buildMonthlyChart(),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 4,
                child: _buildDonationCard(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildNoSchedulePatients(),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _adminInfo,
      builder: (context, snapshot) {
        final rawAdminName = snapshot.data?['adminName'] ?? 'Admin';
        final rawClinicName = snapshot.data?['clinicName'] ?? 'your center';
        final adminName = capitalizeWords(rawAdminName.toString());
        final clinicName = capitalizeWords(rawClinicName.toString());

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dashboard',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF26364A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Welcome, $adminName! You are managing $clinicName.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4A5568),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Here’s an overview of your current patient statistics and growth trends.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF718096),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () {
                _loadData();
                loadClinicData();
                fetchDonationData();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A5F7E),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConnectionError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _connectionError!,
              style: TextStyle(
                color: Colors.red.shade800,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPIRow() {
    return Row(
      children: [
        Expanded(
          child: FutureBuilder<int>(
            future: _totalPatients,
            builder: (context, snapshot) {
              final value = snapshot.data?.toString() ?? '0';
              return _buildKPICard(
                title: 'Total Patients',
                value: value,
                icon: Icons.people_rounded,
                color: const Color(0xFF4A90A4),
                subtitle: 'Active patient records',
              );
            },
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: FutureBuilder<int>(
            future: _pendingPatientsCount,
            builder: (context, snapshot) {
              final value = snapshot.data?.toString() ?? '0';
              return _buildKPICard(
                title: 'Pending Patients',
                value: value,
                icon: Icons.hourglass_bottom_rounded,
                color: const Color(0xFF8E44AD),
                subtitle: 'Awaiting approval',
              );
            },
          ),
        ),
      ],
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF718096),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF26364A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9AA9B8),
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
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
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
                        color: Color(0xFF26364A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF718096),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          child,
        ],
      ),
    );
  }

  Widget _buildDonationCard() {
    final latestAmount = latestDonation?['amount'] ?? 0;
    final latestDate = latestDonation?['distribution_date'];
    final status = latestDonation?['status']?.toString() ?? 'No record';
    final remarks = latestDonation?['remarks']?.toString();

    return Container(
      height: 465,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
                  color: const Color(0xFF8E44AD).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: Color(0xFF8E44AD),
                  size: 23,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Donation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF26364A),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Fund distributions received from superadmin.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF718096),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Total Received',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF718096),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatMoney(totalDonations),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Color(0xFF26364A),
            ),
          ),
          const SizedBox(height: 22),
          _donationInfoRow('Latest Amount', _formatMoney(latestAmount)),
          _donationInfoRow('Date Received', _formatDate(latestDate)),
          _donationInfoRow('Status', status),
          const SizedBox(height: 14),
          const Text(
            'Remarks',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF26364A),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE4EAF0)),
              ),
              child: Text(
                remarks == null || remarks.trim().isEmpty
                    ? 'No remarks available.'
                    : remarks,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF4A5568),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _donationInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF718096),
              fontWeight: FontWeight.w600,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2D3748),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSchedulePatients() {
    return _sectionCard(
      title: 'No Schedule Patients',
      subtitle: 'Patients who still need a weekly schedule assignment.',
      icon: Icons.event_busy_rounded,
      accentColor: const Color(0xFFF59E0B),
      child: FutureBuilder<List<Patient>>(
        future: _noSchedPatients,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF2A5F7E),
                ),
              ),
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
              headingRowHeight: 54,
              dataRowMinHeight: 60,
              dataRowMaxHeight: 66,
              columnSpacing: 54,
              showCheckboxColumn: false,
              headingRowColor: MaterialStateProperty.all(
                const Color(0xFFF4F7FA),
              ),
              dataRowColor: MaterialStateProperty.resolveWith<Color?>(
                (states) {
                  if (states.contains(MaterialState.hovered)) {
                    return const Color(0xFFEAF3F7);
                  }
                  return null;
                },
              ),
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Phone')),
                DataColumn(label: Text('Guardian')),
                DataColumn(label: Text('Guardian Contact')),
                DataColumn(label: Text('')),
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
          );
        },
      ),
    );
  }

  Widget _buildTableWrapper({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE4EAF0)),
          borderRadius: BorderRadius.circular(16),
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
          backgroundColor: const Color(0xFFEAF3F7),
          child: Text(
            _getInitial(patient.name),
            style: const TextStyle(
              color: Color(0xFF2A5F7E),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          patient.name,
          style: const TextStyle(
            color: Color(0xFF2A5F7E),
            fontWeight: FontWeight.w800,
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFF9AA9B8)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF2D3748),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF718096),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
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
                fontWeight: FontWeight.w600,
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
                width: 720,
                constraints: const BoxConstraints(maxHeight: 720),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF2A5F7E),
                                Color(0xFF1F526E),
                              ],
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
                                    color: Color(0xFF2A5F7E),
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patient.name,
                                      style: const TextStyle(
                                        fontSize: 24,
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
                                  size: 18,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Patient Details',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  color: Color(0xFF26364A),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildPatientDetailRow('Name', patient.name),
                              _buildPatientDetailRow('Email', patient.email),
                              _buildPatientDetailRow(
                                'Phone',
                                _safeText(patient.phone),
                              ),
                              _buildPatientDetailRow(
                                'Date of Birth',
                                patient.birthDate?.toString().split(' ')[0] ??
                                    'N/A',
                              ),
                              _buildPatientDetailRow(
                                'Address',
                                patient.address ?? patient.homeAddress ?? 'N/A',
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
                              const SizedBox(height: 24),
                              const Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    color: Color(0xFF2A5F7E),
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Weekly Schedule (Mon-Sat)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: Color(0xFF26364A),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _buildWeeklyScheduleSelector(
                                selectedDays,
                                (day) {
                                  setDialogState(() {
                                    if (selectedDays.contains(day)) {
                                      selectedDays.remove(day);
                                    } else {
                                      selectedDays.add(day);
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 28),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
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
                                      backgroundColor: const Color(0xFF2A5F7E),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF718096),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Color(0xFF2D3748),
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

    const dayShorts = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(days.length, (index) {
        final isSelected = selectedDays.contains(days[index]);

        return FilterChip(
          label: Text(dayShorts[index]),
          selected: isSelected,
          onSelected: (_) => onDaySelected(days[index]),
          backgroundColor: const Color(0xFFF8FAFC),
          selectedColor: const Color(0xFF2A5F7E),
          checkmarkColor: Colors.white,
          side: BorderSide(
            color: isSelected
                ? const Color(0xFF2A5F7E)
                : const Color(0xFFE4EAF0),
          ),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF2D3748),
            fontWeight: FontWeight.w800,
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
      accentColor: const Color(0xFF2A5F7E),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _monthlyData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 330,
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF2A5F7E),
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return _buildErrorBox('Error loading chart: ${snapshot.error}');
          }

          final rawData = snapshot.data ?? [];

          if (rawData.isEmpty) {
            return SizedBox(
              height: 330,
              child: _buildEmptyState(
                icon: Icons.bar_chart_rounded,
                title: 'No chart data available',
                subtitle: 'Monthly patient growth will appear here.',
              ),
            );
          }

          final data =
              rawData.length > 5 ? rawData.sublist(rawData.length - 5) : rawData;

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

          return Container(
            height: 340,
            padding: const EdgeInsets.fromLTRB(8, 12, 18, 8),
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
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFFE4EAF0),
                      strokeWidth: 1,
                    );
                  },
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
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();

                        if (index >= 0 && index < data.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              data[index]['month'].toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF718096),
                                fontWeight: FontWeight.w700,
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
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF718096),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: const Color(0xFFE4EAF0)),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => const Color(0xFF2A5F7E),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '${spot.y.toInt()} patients',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
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
                    color: const Color(0xFF2A5F7E),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF2A5F7E).withOpacity(0.10),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}