import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/appointment.dart';
import 'package:intl/intl.dart';
import '../dashboard/dashboard_page.dart';
import '../patients/patients_page.dart';

class AppointmentsPage extends ConsumerStatefulWidget {
  const AppointmentsPage({super.key});

  @override
  ConsumerState<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends ConsumerState<AppointmentsPage> {
  String _search = '';
  int _selectedNavIndex = 1;
  late List<Appointment> _appointments;

  @override
  void initState() {
    super.initState();
    _initializeMockData();
  }

  void _initializeMockData() {
    _appointments = [
      Appointment(
        id: '1',
        patientId: 'P001',
        patientName: 'John Doe',
        date: DateTime.now().add(const Duration(days: 1)),
        time: '10:00 AM',
        status: 'Scheduled',
        description: null,
      ),
      Appointment(
        id: '2',
        patientId: 'P002',
        patientName: 'Jane Smith',
        date: DateTime.now().add(const Duration(days: 2)),
        time: '2:00 PM',
        status: 'Urgent',
        description: null,
      ),
      Appointment(
        id: '3',
        patientId: 'P003',
        patientName: 'Bob Johnson',
        date: DateTime.now().add(const Duration(days: 3)),
        time: '11:00 AM',
        status: 'Confirmed',
        description: null,
      ),
      Appointment(
        id: '4',
        patientId: 'P004',
        patientName: 'Alice Brown',
        date: DateTime.now().add(const Duration(days: 4)),
        time: '3:00 PM',
        status: 'Declined',
        description: null,
      ),
      Appointment(
        id: '5',
        patientId: 'P005',
        patientName: 'Charlie Wilson',
        date: DateTime.now().add(const Duration(days: 5)),
        time: '9:00 AM',
        status: 'Cancelled',
        description: 'Patient requested cancellation',
      ),
    ];
  }

  Widget _statusCard(String title, int value) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(value.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _prescriptionButton(String appointmentId) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      onPressed: () async {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Prescription'),
            content: const Text('Patients content coming soon'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        );
      },
      child: const Text('View Prescription', style: TextStyle(color: Colors.white)),
    );
  }

  Widget _appointmentActions(Appointment appointment) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: () {
            final index = _appointments.indexWhere((a) => a.id == appointment.id);
            if (index != -1) {
              setState(() {
                _appointments[index] = Appointment(
                  id: appointment.id,
                  patientId: appointment.patientId,
                  patientName: appointment.patientName,
                  date: appointment.date,
                  time: appointment.time,
                  status: 'Confirmed',
                  description: appointment.description,
                );
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Appointment confirmed')),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            final index = _appointments.indexWhere((a) => a.id == appointment.id);
            if (index != -1) {
              setState(() {
                _appointments[index] = Appointment(
                  id: appointment.id,
                  patientId: appointment.patientId,
                  patientName: appointment.patientName,
                  date: appointment.date,
                  time: appointment.time,
                  status: 'Declined',
                  description: appointment.description,
                );
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Appointment declined')),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Decline', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _appointmentTile(Appointment appointment, {bool showActions = false}) {
    // Custom layout for incoming appointments
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black12),
              ),
              child: const Icon(Icons.person, size: 32, color: Colors.black),
            ),
            const SizedBox(width: 16),
            // Patient info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        appointment.patientName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        'Date: ${DateFormat('MMM dd, h:mm a').format(appointment.date)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('#${appointment.patientId}', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                  if (appointment.status == 'Urgent')
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('URGENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _prescriptionButton(appointment.id),
                if (showActions) ...[
                  const SizedBox(height: 8),
                  _appointmentActions(appointment),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Appointment> appointments, {bool showActions = false, bool removeIcon = false}) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...appointments.map((a) => _sectionTile(a, showActions: showActions, removeIcon: removeIcon)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTile(Appointment appointment, {bool showActions = false, bool removeIcon = false}) {
    if (removeIcon) {
      // Remove icon for confirmed/declined
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Row(
            children: [
              // Patient info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          appointment.patientName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          'Date: ${DateFormat('MMM dd, h:mm a').format(appointment.date)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('#${appointment.patientId}', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Actions
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _prescriptionButton(appointment.id),
                  if (showActions) ...[
                    const SizedBox(height: 8),
                    _appointmentActions(appointment),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }
    // Default: use _appointmentTile
    return _appointmentTile(appointment, showActions: showActions);
  }

  Widget _cancelledSection(List<Appointment> appointments) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cancelled', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...appointments.map((a) => Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(a.patientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const Spacer(),
                        Text(DateFormat('MMM dd, h:mm a').format(a.date), style: const TextStyle(fontSize: 14, color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('#${a.patientId}', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                    if (a.description != null) ...[
                      const SizedBox(height: 8),
                      Text('Reason:', style: TextStyle(color: Colors.black38, fontSize: 14)),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(a.description!, style: const TextStyle(color: Colors.black87, fontSize: 14)),
                      ),
                    ],
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentsContent() {
    final filtered = _appointments.where((a) {
      final matchesSearch = _search.isEmpty || a.patientName.toLowerCase().contains(_search.toLowerCase());
      return matchesSearch;
    }).toList();
    
    final totalToday = _appointments.where((a) => DateTime.now().difference(a.date).inDays == 0).length;
    final urgent = _appointments.where((a) => a.status == 'Urgent').length;
    final notUrgent = _appointments.where((a) => a.status == 'Not Urgent').length;
    final cancelled = _appointments.where((a) => a.status == 'Cancelled').length;
    
    final incoming = filtered.where((a) => a.status == 'Scheduled').toList();
    final confirmed = filtered.where((a) => a.status == 'Confirmed').toList();
    final declined = filtered.where((a) => a.status == 'Declined').toList();
    final cancelledList = filtered.where((a) => a.status == 'Cancelled').toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _statusCard('Total Today', totalToday)),
              const SizedBox(width: 20),
              Expanded(child: _statusCard('Urgent', urgent)),
              const SizedBox(width: 20),
              Expanded(child: _statusCard('Not Urgent', notUrgent)),
              const SizedBox(width: 20),
              Expanded(child: _statusCard('Cancelled', cancelled)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (val) {
                setState(() {
                  _search = val;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          _section('Incoming Appointments', incoming, showActions: true),
          Row(
            children: [
              Expanded(child: _section('Confirmed', confirmed, removeIcon: true)),
              const SizedBox(width: 20),
              Expanded(child: _section('Declined', declined, removeIcon: true)),
            ],
          ),
          _cancelledSection(cancelledList),
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
                    padding: const EdgeInsets.all(16.0),
                    child: _buildAppointmentsContent(),
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
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
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
              color: isSelected
                  ? const Color(0xFF1A4A63)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
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
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}