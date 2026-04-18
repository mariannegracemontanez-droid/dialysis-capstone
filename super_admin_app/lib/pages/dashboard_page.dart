import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'admin_accounts_page.dart';
import 'patients_page.dart';
import 'placeholder_page.dart';

enum DashboardSection { dashboard, appointment, patients, adminAccounts, donations }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardSection _selectedSection = DashboardSection.dashboard;

  Widget _buildContent(UserModel? user) {
    switch (_selectedSection) {
      case DashboardSection.appointment:
        return const PlaceholderPage(
          title: 'Appointment',
          description: 'Review appointment requests and schedules on this page. Content will be connected to Supabase soon.',
        );
      case DashboardSection.patients:
        return const PatientsPage();
      case DashboardSection.adminAccounts:
        return const AdminAccountsPage();
      case DashboardSection.donations:
        return const PlaceholderPage(
          title: 'Donations',
          description: 'Donation summaries and incoming gifts will be visible here once connected.',
        );
      case DashboardSection.dashboard:
        return _buildDashboardHome(user);
    }
  }

  Widget _buildDashboardHome(UserModel? user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F3A55),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Welcome, Super Admin!',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4E6B7E),
                  ),
                ),
              ],
            ),
            _ProfileCard(user: user),
          ],
        ),
        const SizedBox(height: 26),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
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
            children: const [
              Text(
                'Mobile-connected dashboard',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'This page is ready to display the same users and data from the mobile app once the Supabase integration is connected. No production content is shown here yet.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF637381),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          height: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFCBD5E1),
              width: 1.4,
            ),
            color: Colors.white,
          ),
          child: const Center(
            child: Text(
              'Super Admin dashboard content will appear here as mobile user data is connected.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF7A8697),
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ModalRoute.of(context)?.settings.arguments as UserModel?;

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 280,
            color: const Color(0xFF174E71),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.local_hospital,
                          color: Color(0xFF174E71),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'CureNurture\nSuper Admin Panel',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _SidebarItem(
                  label: 'Dashboard',
                  icon: Icons.dashboard,
                  selected: _selectedSection == DashboardSection.dashboard,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.dashboard;
                    });
                  },
                ),
                _SidebarItem(
                  label: 'Appointment',
                  icon: Icons.calendar_month,
                  selected: _selectedSection == DashboardSection.appointment,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.appointment;
                    });
                  },
                ),
                _SidebarItem(
                  label: 'Patients',
                  icon: Icons.person,
                  selected: _selectedSection == DashboardSection.patients,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.patients;
                    });
                  },
                ),
                _SidebarItem(
                  label: 'Admin Accounts',
                  icon: Icons.admin_panel_settings,
                  selected: _selectedSection == DashboardSection.adminAccounts,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.adminAccounts;
                    });
                  },
                ),
                _SidebarItem(
                  label: 'Donations',
                  icon: Icons.volunteer_activism,
                  selected: _selectedSection == DashboardSection.donations,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.donations;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFFF5F7FA),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _buildContent(user),
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
  final VoidCallback? onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF0E7DA9) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(icon, color: selected ? Colors.white : Colors.white70),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final UserModel? user;

  const _ProfileCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF0F5B7A),
            child: Text(
              user?.fullName.isNotEmpty == true ? user!.fullName[0] : 'S',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.fullName ?? 'Super Admin',
                style: const TextStyle(
                  color: Color(0xFF0F3A55),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user?.role ?? 'superadmin',
                style: const TextStyle(
                  color: Color(0xFF637381),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
