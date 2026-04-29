import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/clinic.dart';
import '../../models/patient.dart';
import '../../services/supabase_service.dart';
import '../dashboard/dashboard_page.dart';
import '../patients/patients_page.dart';
import 'clinic_detail_page.dart';

class AppointmentsPage extends ConsumerStatefulWidget {
  const AppointmentsPage({super.key});

  @override
  ConsumerState<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends ConsumerState<AppointmentsPage> {
  final SupabaseService _service = SupabaseService();
  late Future<List<Clinic>> _clinicsFuture;
  late Future<List<Patient>> _patientRosterFuture;
  late Future<List<Map<String, dynamic>>> _availableSlotsFuture;
  String _search = '';
  int _selectedNavIndex = 1;
  String? _selectedSlot;

  @override
  void initState() {
    super.initState();
    _clinicsFuture = _service.getClinics();
    _patientRosterFuture = _service.getAllPatients();
    _availableSlotsFuture = _service.getAvailableTimeSlots();
  }

  List<Clinic> _filterClinics(List<Clinic> clinics, List<Patient> patients, String query) {
    if (query.isEmpty) {
      return clinics;
    }

    final lowerQuery = query.toLowerCase();
    final matchingClinicIds = patients
        .where((patient) => patient.name.toLowerCase().contains(lowerQuery))
        .map((patient) => patient.id)
        .where((id) => id.isNotEmpty)
        .cast<String>()
        .toSet();

    return clinics.where((clinic) {
      final clinicName = clinic.name.toLowerCase();
      final clinicLocation = clinic.location.toLowerCase();
      return clinicName.contains(lowerQuery) ||
          clinicLocation.contains(lowerQuery) ||
          matchingClinicIds.contains(clinic.id);
    }).toList();
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
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
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Search by patient name, clinic name, or location',
          prefixIcon: Icon(Icons.search, color: Color(0xFF4A5568)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        onChanged: (value) => setState(() => _search = value),
      ),
    );
  }

  Widget _buildClinicTable(List<Clinic> clinics) {
    if (clinics.isEmpty) {
      return Container(
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
        child: const Text('No clinics found in clinics_centers. Add a clinic to get started.'),
      );
    }

    return Container(
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
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: const [
                Text(
                  'Clinics List',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: const [
                Expanded(child: Text('Clinic and Center Name', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 120, child: Text('Machines', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 140, child: Text('Scheduled Today', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          const Divider(height: 1),
          ...clinics.map((clinic) => _buildClinicRow(clinic)).toList(),
        ],
      ),
    );
  }

  Widget _buildClinicRow(Clinic clinic) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ClinicDetailPage(clinicId: clinic.id)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text('Clinic: ${clinic.name}', style: const TextStyle(color: Color(0xFF2D3748), fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text('Location: ${clinic.location}', style: const TextStyle(color: Color(0xFF4A5568))),
            ),
            SizedBox(width: 120, child: Text('ID: ${clinic.id}', style: const TextStyle(color: Color(0xFF2D3748)))),
            SizedBox(width: 140, child: Text('View Details', style: const TextStyle(color: Color(0xFF718096)))),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableSlotsSection(List<Map<String, dynamic>> slots) {
    // Group slots by date
    final slotsByDate = <String, List<Map<String, dynamic>>>{};
    for (final slot in slots) {
      final date = slot['displayDate'] as String;
      slotsByDate.putIfAbsent(date, () => []).add(slot);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Dialysis Time Slots',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 400,
            child: ListView(
              children: slotsByDate.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2A5F7E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.value.map((slot) {
                          final isSelected = _selectedSlot == '${slot['date']}_${slot['time']}';
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedSlot = '${slot['date']}_${slot['time']}';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF2A5F7E) : const Color(0xFFF5F7FA),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF2A5F7E) : Colors.grey.shade300,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                slot['time'] as String,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : const Color(0xFF4A5568),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (_selectedSlot != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F9F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Selected: $_selectedSlot',
                style: const TextStyle(color: Color(0xFF22863A), fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPatientRosterSection(List<Patient> patients) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patient Roster',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          if (patients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No registered patients found. Add a patient on the dashboard to populate this roster.',
                style: TextStyle(color: Color(0xFF4A5568), fontSize: 14),
              ),
            )
          else
            Column(
              children: patients.map((patient) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Patient: ${patient.name} (Email: ${patient.email})', style: const TextStyle(color: Color(0xFF2D3748), fontSize: 14)),
                );
              }).toList(),
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
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: FutureBuilder<List<Clinic>>(
                      future: _clinicsFuture,
                      builder: (context, clinicSnapshot) {
                        return FutureBuilder<List<Patient>>(
                          future: _patientRosterFuture,
                          builder: (context, patientSnapshot) {
                            return FutureBuilder<List<Map<String, dynamic>>>(
                              future: _availableSlotsFuture,
                              builder: (context, slotsSnapshot) {
                                final clinics = clinicSnapshot.data ?? [];
                                final patients = patientSnapshot.data ?? [];
                                final slots = slotsSnapshot.data ?? [];
                                final filteredClinics = _filterClinics(clinics, patients, _search);

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSearchBar(),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildClinicTable(filteredClinics),
                                            const SizedBox(height: 24),
                                            _buildAvailableSlotsSection(slots),
                                            const SizedBox(height: 24),
                                            _buildPatientRosterSection(patients),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
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
    final isSelected = _selectedNavIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                'Manage all appointment clinics',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
