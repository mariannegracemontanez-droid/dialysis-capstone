import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import 'admin_create_page.dart';
import 'admin_edit_page.dart';

class AdminAccountsPage extends StatefulWidget {
  const AdminAccountsPage({super.key});

  @override
  State<AdminAccountsPage> createState() => _AdminAccountsPageState();
}

class _AdminAccountsPageState extends State<AdminAccountsPage> {
  final ProfileService _service = ProfileService();
  late Future<List<Map<String, dynamic>>> _adminsFuture;
  late Future<List<Map<String, dynamic>>> _logsFuture;
  bool _showLogs = false;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
    _loadLogs();
  }

  void _loadAdmins() {
    _adminsFuture = _service.getAdminProfiles();
  }

  void _loadLogs() {
    _logsFuture = _service.getAdminLogs();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadAdmins();
      _loadLogs();
    });
  }

  Future<void> _openCreateAdmin() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AdminCreatePage()));

    if (created == true) {
      await _refresh();
    }
  }

  Future<void> _openEditAdmin(Map<String, dynamic> admin) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminEditPage(admin: admin)),
    );

    if (updated == true) {
      await _refresh();
    }
  }

  Future<void> _deleteAdmin(Map<String, dynamic> admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete admin account'),
        content: Text(
          'Delete ${admin['full_name'] ?? admin['email']} permanently?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA5353),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deleteAdmin(adminId: admin['id'] as String);
      if (!mounted) return;
      await _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin account deleted successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete admin: $error')));
    }
  }

  Widget _adminCard(Map<String, dynamic> admin) {
    final fullName = admin['full_name'] as String? ?? 'Unknown';
    final email = admin['email'] as String? ?? 'No email';
    final phone = admin['phone'] as String? ?? 'No phone';
    final id = admin['id'] as String? ?? 'Unknown ID';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    Text(
                      email,
                      style: const TextStyle(color: Color(0xFF5E6B74)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: $id',
                      style: const TextStyle(
                        color: Color(0xFF7F8B9B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => _openEditAdmin(admin),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F5B7A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Edit'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () => _deleteAdmin(admin),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEA5353),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.phone, size: 16, color: Color(0xFF7F8B9B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phone,
                  style: const TextStyle(color: Color(0xFF7F8B9B)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogsCard(Map<String, dynamic> log) {
    final actorName = log['actor_name'] as String? ?? 'Unknown actor';
    final targetName = log['target_name'] as String? ?? 'Unknown target';
    final action = log['action'] as String? ?? 'unknown';
    final timestamp = log['created_at']?.toString() ?? 'Unknown time';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                actorName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                action.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F5B7A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Target: $targetName',
            style: const TextStyle(color: Color(0xFF5E6B74)),
          ),
          const SizedBox(height: 8),
          Text(
            timestamp,
            style: const TextStyle(color: Color(0xFF7F8B9B), fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _showLogs ? _logsFuture : _adminsFuture,
      builder: (context, snapshot) {
        Widget body;
        if (snapshot.connectionState != ConnectionState.done) {
          body = const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          body = Center(
            child: Text(
              'Error loading data: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        } else {
          final items = snapshot.data ?? [];
          body = Column(
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Accounts'),
                    selected: !_showLogs,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _showLogs = false;
                          _loadAdmins();
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    label: const Text('Audit Trail'),
                    selected: _showLogs,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _showLogs = true;
                          _loadLogs();
                        });
                      }
                    },
                  ),
                  const Spacer(),
                  if (!_showLogs)
                    FilledButton(
                      onPressed: _openCreateAdmin,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5B7A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Text('Add Account'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (items.isEmpty)
                Center(
                  child: Text(
                    _showLogs
                        ? 'No audit logs found yet.'
                        : 'No admin accounts have been created yet.',
                    style: const TextStyle(color: Color(0xFF637381)),
                  ),
                )
              else if (_showLogs)
                Column(children: items.map(_buildLogsCard).toList())
              else
                Column(children: items.map(_adminCard).toList()),
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
                'Manage admin accounts and review the audit trail for create, update, and delete actions.',
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
