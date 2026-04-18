import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import 'admin_create_page.dart';

class AdminAccountsPage extends StatefulWidget {
  const AdminAccountsPage({super.key});

  @override
  State<AdminAccountsPage> createState() => _AdminAccountsPageState();
}

class _AdminAccountsPageState extends State<AdminAccountsPage> {
  final ProfileService _service = ProfileService();
  late Future<List<Map<String, dynamic>>> _adminsFuture;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  void _loadAdmins() {
    _adminsFuture = _service.getProfilesByRoles(['admin', 'superadmin']);
  }

  Future<void> _openCreateAdmin() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const AdminCreatePage(),
      ),
    );

    if (created == true) {
      setState(() {
        _loadAdmins();
      });
    }
  }

  Widget _adminCard(Map<String, dynamic> admin) {
    final fullName = admin['full_name'] as String? ?? 'Unknown';
    final email = admin['email'] as String? ?? 'No email';
    final role = admin['role'] as String? ?? 'admin';
    final phone = admin['phone_number'] as String? ?? 'No phone';

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF0F5B7A),
            child: Text(
              fullName.isNotEmpty ? fullName[0].toUpperCase() : 'A',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
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
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(color: Color(0xFF5E6B74))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: role == 'superadmin' ? const Color(0xFFF3E5FF) : const Color(0xFFDCF5F7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        role.toUpperCase(),
                        style: TextStyle(
                          color: role == 'superadmin' ? const Color(0xFF6D3AB8) : const Color(0xFF0F5B7A),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(phone, style: const TextStyle(color: Color(0xFF7F8B9B))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F5B7A),
              disabledBackgroundColor: const Color(0xFF0F5B7A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Edit'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA5353),
              disabledBackgroundColor: const Color(0xFFEA5353),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _adminsFuture,
      builder: (context, snapshot) {
        Widget body;
        if (snapshot.connectionState != ConnectionState.done) {
          body = const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          body = Center(
            child: Text(
              'Error loading admins: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        } else {
          final admins = snapshot.data ?? [];
          body = Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD6DFED)),
                      ),
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Search accounts...',
                          style: TextStyle(color: Color(0xFF9AA5B4)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  FilledButton(
                    onPressed: _openCreateAdmin,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5B7A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Text('Add Account'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (admins.isEmpty)
                const Center(
                  child: Text(
                    'No admin accounts have been created yet.',
                    style: TextStyle(color: Color(0xFF637381)),
                  ),
                )
              else
                Column(
                  children: admins.map(_adminCard).toList(),
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
                'Admin Account Management',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F3A55),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage admin users and add new accounts for the CureNurture team.',
                style: TextStyle(fontSize: 14, color: Color(0xFF637381)),
              ),
              const SizedBox(height: 24),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
