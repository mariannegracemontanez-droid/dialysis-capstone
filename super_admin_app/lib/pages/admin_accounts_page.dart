import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import '../config/supabase_config.dart';

class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({super.key});

  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  final ProfileService _service = ProfileService();

  late Future<List<Map<String, dynamic>>> _adminsFuture;
  late Future<List<Map<String, dynamic>>> _logsFuture;

  bool _showLogs = false;

  static const Color _primary = Color(0xFF0F719F);
  static const Color _dark = Color(0xFF0F3A55);
  static const Color _muted = Color(0xFF647583);
  static const Color _bg = Color(0xFFF3F7FA);
  static const Color _danger = Color(0xFFDE4D4D);
  static const Color _success = Color(0xFF2E7D32);

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
    final created = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Create Admin Account',
      barrierColor: Colors.black.withAlpha(70),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const _BlurredAdminCreateModal();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (created == true) {
      await _refresh();
    }
  }

  Future<void> _openEditAdmin(Map<String, dynamic> admin) async {
    if (admin['status'] == 'inactive') return;

    final updated = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit Admin Account',
      barrierColor: Colors.black.withAlpha(70),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _BlurredAdminEditModal(admin: admin);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (updated == true) {
      await _refresh();
    }
  }

  Future<void> _deleteAdmin(Map<String, dynamic> admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deleteAdmin(adminId: admin['id'] as String);

      await _service.logAction(
        action: 'delete_admin',
        targetId: admin['id'],
        targetName: admin['full_name'],
      );

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
    final status = admin['status'] ?? 'active';
    final clinicName = admin['clinics']?['name'];
    final isInactive = status == 'inactive';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5EEF4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 760;

          final profileBlock = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: isInactive
                    ? _danger.withAlpha(24)
                    : _primary.withAlpha(26),
                child: Text(
                  fullName.isNotEmpty ? fullName[0].toUpperCase() : 'A',
                  style: TextStyle(
                    color: isInactive ? _danger : _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _dark,
                          ),
                        ),
                        _StatusPill(
                          label: isInactive ? 'Inactive' : 'Active',
                          color: isInactive ? _danger : _success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _InfoLine(icon: Icons.email_outlined, text: email),
                    const SizedBox(height: 6),
                    _InfoLine(icon: Icons.phone_outlined, text: phone),
                    const SizedBox(height: 6),
                    _InfoLine(
                      icon: Icons.local_hospital_outlined,
                      text: isInactive
                          ? 'No active clinic access'
                          : 'Clinic: ${clinicName ?? 'No Clinic'}',
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: isInactive ? null : () => _openEditAdmin(admin),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _deleteAdmin(admin),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
                style: FilledButton.styleFrom(
                  backgroundColor: _danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [profileBlock, const SizedBox(height: 18), actions],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: profileBlock),
              const SizedBox(width: 20),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogsCard(Map<String, dynamic> log) {
    final actorName = log['actor_name'] as String? ?? 'Unknown actor';
    final targetName = log['target_name'] as String? ?? 'Unknown target';
    final action = log['action'] as String? ?? 'unknown';
    final timestamp = log['created_at']?.toString() ?? 'Unknown time';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5EEF4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primary.withAlpha(22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.history_rounded, color: _primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actorName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _dark,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Action: $action',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Target: $targetName',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 4),
                Text(
                  timestamp,
                  style: const TextStyle(
                    color: Color(0xFF8A98A5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F719F), Color(0xFF0F3A55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _primary.withAlpha(40),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 720;

          return Flex(
            direction: isCompact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: isCompact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: isCompact ? 0 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withAlpha(45)),
                      ),
                      child: const Text(
                        'Admin Access Control',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Account Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Manage clinic admin accounts, update account details, and review admin activity history.',
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCompact) const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _openCreateAdmin,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add Account'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE5EEF4)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 24,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Accounts'),
                    selected: !_showLogs,
                    selectedColor: _primary.withAlpha(28),
                    checkmarkColor: _primary,
                    labelStyle: TextStyle(
                      color: !_showLogs ? _primary : _muted,
                      fontWeight: FontWeight.w800,
                    ),
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
                    selectedColor: _primary.withAlpha(28),
                    checkmarkColor: _primary,
                    labelStyle: TextStyle(
                      color: _showLogs ? _primary : _muted,
                      fontWeight: FontWeight.w800,
                    ),
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
                  IconButton.filledTonal(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (items.isEmpty)
                _EmptyState(
                  icon: _showLogs
                      ? Icons.manage_search_rounded
                      : Icons.admin_panel_settings_outlined,
                  title: _showLogs
                      ? 'No audit logs found'
                      : 'No admin accounts',
                  message: _showLogs
                      ? 'Admin activity history will appear here.'
                      : 'Create an admin account to assign access to a clinic.',
                )
              else if (_showLogs)
                Column(children: items.map(_buildLogsCard).toList())
              else
                Column(children: items.map(_adminCard).toList()),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(28),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _showLogs ? _logsFuture : _adminsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 520,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return _ErrorState(
                  message: 'Error loading data: ${snapshot.error}',
                );
              }

              final items = snapshot.data ?? [];
              return _buildContent(items);
            },
          ),
        ),
      ),
    );
  }
}

class _BlurredAdminEditModal extends StatefulWidget {
  final Map<String, dynamic> admin;

  const _BlurredAdminEditModal({required this.admin});

  @override
  State<_BlurredAdminEditModal> createState() => _BlurredAdminEditModalState();
}

class _BlurredAdminEditModalState extends State<_BlurredAdminEditModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final ProfileService _service = ProfileService();

  bool _isSaving = false;
  String? _errorMessage;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _changePassword = false;

  List<Map<String, dynamic>> _clinics = [];
  Set<String> _clinicsWithAdmin = {};
  String? selectedClinicId;

  static const Color _primary = Color(0xFF0F719F);
  static const Color _dark = Color(0xFF0F3A55);
  static const Color _muted = Color(0xFF647583);
  static const Color _danger = Color(0xFFDE4D4D);

  @override
  void initState() {
    super.initState();

    _nameController.text = widget.admin['full_name'] ?? '';
    _phoneController.text = widget.admin['phone'] ?? '';
    selectedClinicId = widget.admin['clinic_id'];

    _loadClinics();
    _loadAdmins();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadClinics() async {
    final data = await SupabaseConfig.client.from('clinics').select();

    if (!mounted) return;

    setState(() {
      _clinics = List<Map<String, dynamic>>.from(data);
    });
  }

  Future<void> _loadAdmins() async {
    final data = await SupabaseConfig.client
        .from('profiles')
        .select('clinic_id')
        .eq('role', 'admin');

    if (!mounted) return;

    setState(() {
      _clinicsWithAdmin = data.map((e) => e['clinic_id'].toString()).toSet();
    });
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (_changePassword && password != confirm) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    await ProfileService().logAction(
      action: 'edit_admin',
      targetId: widget.admin['id'],
      targetName: _nameController.text.trim(),
    );

    try {
      await _service.updateAdmin(
        adminId: widget.admin['id'],
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _changePassword && password.isNotEmpty ? password : null,
        clinicId: selectedClinicId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _primary),
      filled: true,
      fillColor: const Color(0xFFF6FBFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFDCEAF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.admin['email'] ?? '-';
    final isInactive = widget.admin['status'] == 'inactive';
    final hasClinic = widget.admin['clinic_id'] != null;

    return Stack(
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(color: const Color(0x880F3A55)),
        ),
        Center(
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: 620,
                constraints: const BoxConstraints(maxWidth: 620),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFD),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withAlpha(180)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 35,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primary.withAlpha(22),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.manage_accounts_outlined,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Admin Account',
                                  style: TextStyle(
                                    color: _dark,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Update account details and password settings.',
                                  style: TextStyle(color: _muted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.close_rounded),
                            color: _dark,
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _danger.withAlpha(22),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _danger.withAlpha(40)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: _danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      DropdownButtonFormField<String?>(
                        decoration: _inputDecoration(
                          label: 'Assigned Clinic',
                          icon: Icons.local_hospital_outlined,
                        ),
                        initialValue: selectedClinicId,
                        hint: const Text('Select Clinic'),
                        items: _clinics.map((clinic) {
                          final hasAdmin = _clinicsWithAdmin.contains(
                            clinic['id'],
                          );
                          final isCurrent =
                              clinic['id'] == widget.admin['clinic_id'];

                          return DropdownMenuItem<String?>(
                            value: clinic['id'],
                            enabled: !hasAdmin || isCurrent,
                            child: Text(
                              clinic['name'] +
                                  (hasAdmin && !isCurrent
                                      ? ' (Has Admin)'
                                      : ''),
                            ),
                          );
                        }).toList(),
                        onChanged: (isInactive || hasClinic)
                            ? null
                            : (value) {
                                setState(() {
                                  selectedClinicId = value;
                                });
                              },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        initialValue: email,
                        readOnly: true,
                        decoration: _inputDecoration(
                          label: 'Email',
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration(
                          label: 'Full Name',
                          icon: Icons.person_outline_rounded,
                        ),
                        validator: (value) =>
                            value == null || value.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        decoration: _inputDecoration(
                          label: 'Phone',
                          icon: Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2EDF4)),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Change Password',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _dark,
                            ),
                          ),
                          subtitle: const Text(
                            'Enable this only if the admin needs a new password.',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                          value: _changePassword,
                          activeColor: _primary,
                          onChanged: (val) {
                            setState(() {
                              _changePassword = val;
                            });
                          },
                        ),
                      ),
                      if (_changePassword) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration:
                              _inputDecoration(
                                label: 'New Password',
                                icon: Icons.lock_outline_rounded,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          decoration:
                              _inputDecoration(
                                label: 'Confirm Password',
                                icon: Icons.lock_reset_rounded,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirm = !_obscureConfirm;
                                    });
                                  },
                                ),
                              ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: _isSaving ? null : _saveChanges,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              _isSaving ? 'Saving...' : 'Save Changes',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 17,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BlurredAdminCreateModal extends StatefulWidget {
  const _BlurredAdminCreateModal();

  @override
  State<_BlurredAdminCreateModal> createState() =>
      _BlurredAdminCreateModalState();
}

class _BlurredAdminCreateModalState extends State<_BlurredAdminCreateModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  List<Map<String, dynamic>> _clinics = [];
  Set<String> _clinicsWithAdmin = {};
  String? selectedClinicId;

  static const Color _primary = Color(0xFF0F719F);
  static const Color _dark = Color(0xFF0F3A55);
  static const Color _muted = Color(0xFF647583);
  static const Color _danger = Color(0xFFDE4D4D);

  @override
  void initState() {
    super.initState();
    _loadClinics();
    _loadAdmins();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadClinics() async {
    final data = await SupabaseConfig.client.from('clinics').select();

    if (!mounted) return;

    setState(() {
      _clinics = List<Map<String, dynamic>>.from(data);
    });
  }

  Future<void> _loadAdmins() async {
    final data = await SupabaseConfig.client
        .from('profiles')
        .select('clinic_id')
        .eq('role', 'admin');

    if (!mounted) return;

    setState(() {
      _clinicsWithAdmin = data.map((e) => e['clinic_id'].toString()).toSet();
    });
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
      });
      return;
    }

    if (selectedClinicId == null) {
      setState(() {
        _errorMessage = 'Please select a clinic.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final authResponse = await SupabaseConfig.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = authResponse.user;

      if (user == null) {
        throw Exception('User creation failed');
      }

      await SupabaseConfig.client.from('profiles').insert({
        'id': user.id,
        'full_name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': 'admin',
        'phone': _phoneController.text.trim(),
        'clinic_id': selectedClinicId!,
        'status': 'active',
      });

      await ProfileService().logAction(
        action: 'admin_created',
        targetId: user.id,
        targetName: _nameController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _primary),
      filled: true,
      fillColor: const Color(0xFFF6FBFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFDCEAF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _danger, width: 1.5),
      ),
    );
  }

  String? _requiredValidator(String? value, String message) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(color: const Color(0x880F3A55)),
        ),
        Center(
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: 620,
                constraints: const BoxConstraints(maxWidth: 620),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFD),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withAlpha(180)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 35,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primary.withAlpha(22),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.person_add_alt_1_rounded,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create Admin Account',
                                  style: TextStyle(
                                    color: _dark,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Assign a clinic admin and create login access.',
                                  style: TextStyle(color: _muted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.close_rounded),
                            color: _dark,
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2EDF4)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: _primary,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Only clinics without an existing admin can be selected.',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _danger.withAlpha(22),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _danger.withAlpha(40)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: _danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      DropdownButtonFormField<String>(
                        decoration: _inputDecoration(
                          label: 'Assigned Clinic',
                          icon: Icons.local_hospital_outlined,
                        ),
                        initialValue: selectedClinicId,
                        hint: const Text('Select clinic'),
                        items: _clinics.map((clinic) {
                          final clinicId = clinic['id'].toString();
                          final hasAdmin = _clinicsWithAdmin.contains(clinicId);

                          return DropdownMenuItem<String>(
                            value: hasAdmin ? null : clinicId,
                            enabled: !hasAdmin,
                            child: Text(
                              '${clinic['name'] ?? 'Unnamed clinic'}'
                              '${hasAdmin ? ' (Has Admin)' : ''}',
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedClinicId = value;
                          });
                        },
                        validator: (value) =>
                            value == null ? 'Please select a clinic' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          label: 'Full Name',
                          icon: Icons.person_outline_rounded,
                          hint: 'Enter admin full name',
                        ),
                        validator: (value) =>
                            _requiredValidator(value, 'Enter full name'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDecoration(
                          label: 'Email Address',
                          icon: Icons.email_outlined,
                          hint: 'Enter admin email',
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return 'Enter email address';
                          if (!email.contains('@')) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.phone,
                        decoration: _inputDecoration(
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                          hint: 'Enter phone number',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration:
                            _inputDecoration(
                              label: 'Password',
                              icon: Icons.lock_outline_rounded,
                              hint: 'Enter password',
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                        validator: (value) =>
                            _requiredValidator(value, 'Enter password'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        decoration:
                            _inputDecoration(
                              label: 'Confirm Password',
                              icon: Icons.lock_reset_rounded,
                              hint: 'Confirm password',
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirm = !_obscureConfirm;
                                  });
                                },
                              ),
                            ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: _isSubmitting ? null : _createAccount,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1_rounded),
                            label: Text(
                              _isSubmitting ? 'Creating...' : 'Create Account',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 17,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool muted;

  const _InfoLine({required this.icon, required this.text, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: muted ? const Color(0xFF8A98A5) : const Color(0xFF647583),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted ? const Color(0xFF8A98A5) : const Color(0xFF647583),
              fontSize: muted ? 12 : 13,
              fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5EEF4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 46, color: const Color(0xFF8DA9BA)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F3A55),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF647583), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE5EEF4)),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFDE4D4D),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
