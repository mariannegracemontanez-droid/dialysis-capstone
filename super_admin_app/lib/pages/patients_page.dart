import 'package:flutter/material.dart';
import '../services/profile_service.dart';

class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key});

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  final ProfileService _service = ProfileService();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _patientsFuture;

  @override
  void initState() {
    super.initState();
    _patientsFuture = _service.getProfilesByRole('patient');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterPatients(List<Map<String, dynamic>> patients) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return patients;
    return patients.where((profile) {
      final fullName = (profile['full_name'] as String?)?.toLowerCase() ?? '';
      final email = (profile['email'] as String?)?.toLowerCase() ?? '';
      return fullName.contains(query) || email.contains(query);
    }).toList();
  }

  Widget _statCard(String title, String value, {Color background = Colors.white}) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xFF6B7685)),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF122A44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _patientCard(Map<String, dynamic> patient) {
    final fullName = patient['full_name'] as String? ?? 'Unknown';
    final email = patient['email'] as String? ?? 'No email';
    final phone = patient['phone_number'] as String? ?? 'No phone';
    return Container(
      width: 320,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD3DCE6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF0F5B7A),
                child: Text(
                  fullName.isNotEmpty ? fullName[0].toUpperCase() : 'P',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF122A44),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Patient',
                      style: const TextStyle(color: Color(0xFF637381), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCF5F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Registered',
                  style: TextStyle(color: Color(0xFF0F5B7A), fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.email, size: 16, color: Color(0xFF7F8B9B)),
              const SizedBox(width: 8),
              Expanded(child: Text(email, style: const TextStyle(color: Color(0xFF4E6B7E)))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.phone, size: 16, color: Color(0xFF7F8B9B)),
              const SizedBox(width: 8),
              Expanded(child: Text(phone, style: const TextStyle(color: Color(0xFF4E6B7E)))),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F5B7A),
                    side: const BorderSide(color: Color(0xFF0F5B7A)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('View'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F5B7A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Edit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _patientsFuture,
      builder: (context, snapshot) {
        Widget content;
        if (snapshot.connectionState != ConnectionState.done) {
          content = const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          content = Center(
            child: Text(
              'Could not load patients: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        } else {
          final patients = snapshot.data ?? [];
          final filtered = _filterPatients(patients);
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search patients',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  _statCard('Total Patients', '--'),
                  _statCard('Active Patients', '--'),
                  _statCard('Registered', patients.length.toString(), background: const Color(0xFFDCF5F7)),
                  _statCard('Inactive', '--'),
                ],
              ),
              const SizedBox(height: 24),
              if (filtered.isEmpty)
                Center(
                  child: Text(
                    patients.isEmpty
                        ? 'No registered patients found.'
                        : 'No patients match your search.',
                    style: const TextStyle(color: Color(0xFF637381)),
                  ),
                )
              else
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: filtered.map(_patientCard).toList(),
                ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Patient Management',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F3A55),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Review registered patient accounts and user details from Supabase.',
                style: TextStyle(fontSize: 14, color: Color(0xFF637381)),
              ),
              const SizedBox(height: 24),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}
