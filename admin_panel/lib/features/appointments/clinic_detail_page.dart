import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/clinic.dart';
import '../../models/patient.dart';
import '../../services/supabase_service.dart';
import '../dashboard/dashboard_page.dart';
import '../patients/patients_page.dart';

class ClinicDetailPage extends ConsumerStatefulWidget {
  final String clinicId;

  const ClinicDetailPage({super.key, required this.clinicId});

  @override
  ConsumerState<ClinicDetailPage> createState() => _ClinicDetailPageState();
}

class _ClinicDetailPageState extends ConsumerState<ClinicDetailPage> {
  final SupabaseService _service = SupabaseService();
  Clinic? _clinic;
  List<Patient> _patients = [];
  String _selectedFilter = 'All';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClinic();
  }

  Future<void> _loadClinic() async {
    setState(() => _loading = true);
    final clinic = await _service.getClinicById(widget.clinicId);
    final patients = await _service.getPatientsByClinic(widget.clinicId);
    if (mounted) {
      setState(() {
        _clinic = clinic;
        _patients = patients;
        _loading = false;
      });
    }
  }

  List<Patient> get _filteredPatients {
    if (_selectedFilter == 'All') {
      return _patients.take(5).toList();
    }
    return _patients.where((patient) {
      final time = patient.scheduleTime?.toLowerCase() ?? '';
      if (_selectedFilter == 'AM') {
        return time.contains('am');
      }
      if (_selectedFilter == 'PM') {
        return time.contains('pm');
      }
      return true;
    }).take(5).toList();
  }

  Widget _buildFilterButton(String label) {
    final isActive = _selectedFilter == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF2A5F7E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? const Color(0xFF2A5F7E) : Colors.grey.shade300,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF4A5568),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPatientViewDialog(Patient patient) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Patient Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Name', patient.name),
              _buildDetailRow('Patient ID', patient.id),
              _buildDetailRow('Email', patient.email),
              _buildDetailRow('Phone', patient.phone ?? '-'),
              _buildDetailRow('Location', patient.userLocation ?? '-'),
          
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _showPatientEditDialog(Patient patient) async {
    final emailController = TextEditingController(text: patient.email);
    final phoneController = TextEditingController(text: patient.phone ?? '');
    final locationController = TextEditingController(text: patient.userLocation ?? '');
    final scheduleController = TextEditingController(text: patient.scheduleTime ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Patient'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                enabled: false,
                decoration: InputDecoration(labelText: 'Full Name', hintText: patient.name),
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: false
              ),
              const SizedBox(height: 12),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 12),
              TextField(controller: locationController, decoration: const InputDecoration(labelText: 'Location')),
              const SizedBox(height: 12),
              TextField(controller: scheduleController, decoration: const InputDecoration(labelText: 'Schedule Time')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (emailController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email is required.')));
                return;
              }
              await _service.updatePatient(patient.id, {
                'email': emailController.text.trim(),
                'phone': phoneController.text.trim(),
                'location': locationController.text.trim(),
                'schedule_time': scheduleController.text.trim(),
              });
              await _loadClinic();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patient updated successfully.')));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF2A5F7E)))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _clinic?.name ?? 'Clinic Details',
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _clinic?.location ?? '',
                                style: const TextStyle(fontSize: 14, color: Color(0xFF4A5568)),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  _buildInfoTile('Machines', _clinic?.machines.toString() ?? '0'),
                                  const SizedBox(width: 20),
                                  _buildInfoTile('Slots', _clinic?.availableSlots.toString() ?? '0'),
                                  const SizedBox(width: 20),
                                  _buildInfoTile('Status', _clinic?.status ?? '-'),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  _buildFilterButton('All'),
                                  const SizedBox(width: 12),
                                  _buildFilterButton('AM'),
                                  const SizedBox(width: 12),
                                  _buildFilterButton('PM'),
                                ],
                              ),
                              const SizedBox(height: 24),
                              ..._filteredPatients.map((patient) => _buildPatientCard(patient)),
                              if (_filteredPatients.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Text('No patients available for this filter.'),
                                ),
                            ],
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

  Widget _buildInfoTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard(Patient patient) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF2A5F7E),
                child: Text(patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(patient.name, style: const TextStyle(color: Color(0xFF4A5568))),
                  ],
                ),
              ),
              Row(
                children: [
                  OutlinedButton(onPressed: () => _showPatientViewDialog(patient), child: const Text('View')),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: () => _showPatientEditDialog(patient), child: const Text('Edit')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _buildPatientInfoChip('Email', patient.email),
              _buildPatientInfoChip('Phone', patient.phone ?? 'N/A'),
              _buildPatientInfoChip('Schedule', patient.scheduleTime ?? 'N/A'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatientInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: Color(0xFF4A5568), fontWeight: FontWeight.w600)),
            TextSpan(text: value, style: const TextStyle(color: Color(0xFF2D3748))),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF2A5F7E),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _buildLogo(),
          const SizedBox(height: 40),
          _buildNavItem(0, Icons.dashboard_rounded, 'Dashboard'),
          _buildNavItem(1, Icons.calendar_month_rounded, 'Appointment'),
          _buildNavItem(2, Icons.people_rounded, 'Patients'),
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
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'CureNurture',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Admin Panel',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = index == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (index == 0) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const DashboardPage()),
              );
            } else if (index == 2) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const PatientsPage()),
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1A4A63) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected ? Border.all(color: Colors.white24, width: 1) : null,
            ),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? Colors.white : Colors.white70, size: 22),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
          color: Colors.white.withOpacity(0.5),
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A5F7E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Appointments',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Manage all appointments',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
