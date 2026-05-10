import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/patient_service.dart';
import '../../models/patient.dart';
import '../dashboard/dashboard_page.dart';

late Future<Map<String, dynamic>?> _adminInfo;

class PatientsPage extends ConsumerStatefulWidget {
  const PatientsPage({super.key});

  @override
  ConsumerState<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends ConsumerState<PatientsPage> {
  final PatientService _service = PatientService();
  int _selectedNavIndex = 1;

  late Future<List<Patient>> _pendingPatients;
  late Future<List<Patient>> _allPatients;
  late Future<List<Patient>> _declinedPatients;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _pendingPatients = _service.getPatientsByStatus('pending');
    _allPatients = _service.getPatientsByStatus('active');
    _declinedPatients = _service.getPatientsByStatus('declined');
    _adminInfo = _service.getCurrentAdminInfo();
  }

  void _refreshData() {
    setState(() {
      _loadData();
    });
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
          (word) => word.isEmpty
              ? ''
              : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  Widget _buildNoScheduleState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: const Text(
        'No schedule set',
        style: TextStyle(
          color: Color(0xFF718096),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
              borderRadius: BorderRadius.circular(24),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
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
              child: CircularProgressIndicator(
                color: Color(0xFF2A5F7E),
              ),
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
              borderRadius: BorderRadius.circular(14),
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

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: docs.map((doc) {
            final fileName = _safeText(doc['name'] ?? doc['file_name']);
            final imageUrl = _safeText(doc['url'] ?? doc['file_url']);

            return ElevatedButton.icon(
              onPressed: imageUrl == 'N/A'
                  ? null
                  : () => _showMedicalDocPreview(fileName, imageUrl),
              icon: const Icon(Icons.description_rounded, size: 17),
              label: Text(fileName),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEAF3F7),
                foregroundColor: const Color(0xFF2A5F7E),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: const BorderSide(color: Color(0xFFD7E8F0)),
                ),
              ),
            );
          }).toList(),
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
            child: CircularProgressIndicator(
              color: Color(0xFF2A5F7E),
            ),
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
    day = (item['day'] ?? item['day_of_week'] ?? item['scheduled_day'] ?? 'N/A')
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

            final hasTime = startTime != null &&
                endTime != null &&
                startTime.toString().trim().isNotEmpty &&
                endTime.toString().trim().isNotEmpty &&
                startTime.toString().toLowerCase() != 'null' &&
                endTime.toString().toLowerCase() != 'null';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3F7),
                borderRadius: BorderRadius.circular(30),
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
      backgroundColor: const Color(0xFFF3F7FA),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 26),
                  _buildPendingPatientsSection(),
                  const SizedBox(height: 26),
                  _buildAllPatientsSection(),
                  const SizedBox(height: 26),
                  _buildDeclinedPatientsSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patients Management',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF26364A),
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Review patient requests, active records, and declined applications.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF718096),
                ),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _refreshData,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2A5F7E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
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
                    final adminName = snapshot.data?['adminName'] ?? 'Admin';

                    return Text(
                      adminName.toString(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
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

            if (index == 0) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => DashboardPage()),
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

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        '© 2025 CureNurture',
        style: TextStyle(
          color: Colors.white.withOpacity(0.55),
          fontSize: 11,
        ),
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
      child: Padding(
        padding: const EdgeInsets.all(26),
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
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF26364A),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF718096),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      '$count total',
                      style: TextStyle(
                        fontSize: 12,
                        color: accentColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF2A5F7E),
        ),
      ),
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
              fontWeight: FontWeight.w800,
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

  Widget _buildErrorState(Object? error) {
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

              return _buildTableWrapper(
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

              return _buildTableWrapper(
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
                  dataRowColor: WidgetStateProperty.resolveWith<Color?>(
                    (states) {
                      if (states.contains(WidgetState.hovered)) {
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

              return _buildTableWrapper(
                minWidth: 740,
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
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTableWrapper({
    required Widget child,
    required int minWidth,
  }) {
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(30),
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
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 760,
            constraints: const BoxConstraints(maxHeight: 760),
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
                    _buildPatientModalHeader(patient),
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPatientInfoSection(patient),
                          const SizedBox(height: 28),
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
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  color: Color(0xFF26364A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildMedicalDocsList(patient),
                          const SizedBox(height: 30),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFED7AA),
                              ),
                            ),
                            child: const Text(
                              'Please carefully review the patient details and medical requirements before accepting or declining this request.',
                              style: TextStyle(
                                color: Color(0xFF9A3412),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () => _confirmPendingDecision(
                                  patient: patient,
                                  isAccept: false,
                                ),
                                icon: const Icon(Icons.close_rounded, size: 17),
                                label: const Text('Decline'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () => _confirmPendingDecision(
                                  patient: patient,
                                  isAccept: true,
                                ),
                                icon: const Icon(Icons.check_rounded, size: 17),
                                label: const Text('Accept'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
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
  }

  void _showPatientDetailsModal(Patient patient) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 760,
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
                    _buildPatientModalHeader(patient),
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPatientInfoSection(patient),
                          const SizedBox(height: 28),
                          const Row(
                            children: [
                              Icon(
                                Icons.calendar_month_rounded,
                                color: Color(0xFF2A5F7E),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Weekly Schedule',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  color: Color(0xFF26364A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildWeeklyScheduleList(patient),
                          const SizedBox(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showEditPatientModal(patient);
                                },
                                icon: const Icon(Icons.edit_rounded, size: 17),
                                label: const Text('Edit'),
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPatientModalHeader(Patient patient) {
    return Container(
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
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            color: Colors.white,
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
          'Patient Information',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 17,
            color: Color(0xFF26364A),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _buildDetailCard(Icons.email_rounded, 'Email', _safeText(patient.email)),
            _buildDetailCard(Icons.phone_rounded, 'Phone', _safeText(patient.phone)),
            _buildDetailCard(
              Icons.location_on_rounded,
              'Address',
              _safeText(patient.homeAddress),
            ),
            _buildDetailCard(
              Icons.cake_rounded,
              'Date of Birth',
              patient.birthDate?.toString().split(' ')[0] ?? 'N/A',
            ),
            _buildDetailCard(
              Icons.bloodtype_rounded,
              'Blood Type',
              _safeText(patient.bloodType),
            ),
            _buildDetailCard(
              Icons.family_restroom_rounded,
              'Guardian',
              _safeText(patient.emergencyContactName),
            ),
            _buildDetailCard(
              Icons.contact_phone_rounded,
              'Guardian Contact',
              _safeText(patient.emergencyContactNumber),
            ),
          ],
        ),
      ],
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
                    _buildLockedField('Blood Type', _safeText(patient.bloodType)),
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
                            try {
                              await _service.updatePatientInfo(
                                patientId: patient.id,
                                email: emailController.text.trim(),
                                phone: phoneController.text.trim(),
                                homeAddress: addressController.text.trim(),
                                emergencyContactName:
                                    guardianNameController.text.trim(),
                                emergencyContactNumber:
                                    guardianContactController.text.trim(),
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

  Widget _buildLockedField(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
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
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE4EAF0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE4EAF0)),
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
    );
  }

  Widget _buildDetailCard(IconData icon, String label, String value) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2A5F7E), size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF718096),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2D3748),
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

  Future<void> _acceptPatient(Patient patient) async {
    try {
      await _service.acceptPatient(patient.id);
      _refreshData();
      _showMessage('Patient accepted, awaiting schedule');
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }
  }

  Future<void> _declinePatient(Patient patient) async {
    try {
      await _service.declinePatient(patient.id);
      _refreshData();
      _showMessage('Patient declined');
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }
  }

  Future<void> _confirmPendingDecision({
    required Patient patient,
    required bool isAccept,
  }) async {
    final actionText = isAccept ? 'accept' : 'decline';
    final title = isAccept ? 'Accept Patient?' : 'Decline Patient?';

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (confirmContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(title),
          content: Text(
            'Please make sure you have carefully reviewed ${patient.name}’s patient details and medical requirements before you $actionText this request.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('Review Again'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(confirmContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isAccept ? Colors.green.shade600 : Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              child: Text(isAccept ? 'Accept' : 'Decline'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      if (isAccept) {
        await _service.acceptPatient(patient.id);
        _showMessage('Patient accepted, awaiting schedule');
      } else {
        await _service.declinePatient(patient.id);
        _showMessage('Patient declined');
      }

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();
      _refreshData();
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }
  }
}