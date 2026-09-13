import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/profile_service.dart';
import '../config/supabase_config.dart';

/// Limits a phone-style field to at most [maxDigits] digits while still
/// letting the existing supported formatting characters (spaces, +, -,
/// parentheses) through -- counts by digits, not raw string length, so a
/// nicely formatted number isn't penalized for its own formatting
/// characters. Never touches text it isn't given interactively: setting a
/// controller's initial `text` (e.g. when opening Edit) does not go through
/// input formatters at all, so an existing stored value is never truncated
/// by this -- it only blocks typing/pasting a value whose digit count would
/// exceed the limit. Equivalent to (and kept in sync with the intent of)
/// _MaxDigitsTextInputFormatter in center_page.dart's Contact Number field;
/// duplicated here rather than imported since that class is private to
/// center_page.dart.
class _MaxDigitsTextInputFormatter extends TextInputFormatter {
  final int maxDigits;

  const _MaxDigitsTextInputFormatter(this.maxDigits);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitCount = newValue.text.replaceAll(RegExp(r'[^0-9]'), '').length;

    if (digitCount > maxDigits) {
      return oldValue;
    }

    return newValue;
  }
}

/// User-controlled sort options for the account list. Sorting only reorders
/// the already-loaded/filtered list -- it never changes the database query.
enum _AccountSortOption {
  newest('Newest'),
  oldest('Oldest'),
  nameAsc('Name A-Z'),
  nameDesc('Name Z-A');

  const _AccountSortOption(this.label);

  final String label;
}

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

  // Account list search/filter/sort -- all client-side, applied on top of
  // the already-loaded account data. Does not affect the Audit Trail tab.
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  String? _statusFilter; // null = All, otherwise 'active' or 'inactive'
  _AccountSortOption _sortOption = _AccountSortOption.newest;

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      barrierLabel: 'Create Head Nurse Account',
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Head nurse account created successfully.'),
        ),
      );
    }
  }

  Future<void> _openEditAdmin(Map<String, dynamic> admin) async {
    if (admin['status'] == 'inactive') return;

    final updated = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit Head Nurse Account',
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Head nurse account updated successfully.'),
        ),
      );
    }
  }

  Future<void> _openReactivateAdmin(Map<String, dynamic> admin) async {
    final reactivated = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Reactivate Head Nurse Account',
      barrierColor: Colors.black.withAlpha(70),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _BlurredAdminReactivateModal(admin: admin);
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

    if (reactivated == true) {
      await _refresh();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Head nurse account reactivated successfully.'),
        ),
      );
    }
  }

  Future<void> _deleteAdmin(Map<String, dynamic> admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Deactivate head nurse account'),
        content: Text(
          'Deactivate ${admin['full_name'] ?? admin['email']}? '
          'The account will become inactive and lose its active clinic access. '
          'It can be reactivated later by assigning a clinic again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('Deactivate'),
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
        const SnackBar(
          content: Text('Head nurse account deleted successfully.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete admin: $error')));
    }
  }

  /// Display-only translation of the stored role value -- never interprets
  /// or changes what the role actually grants. Unknown/unexpected values are
  /// shown readably rather than crashing or being treated as a known role.
  String _roleLabel(String? role) {
    final normalized = role?.trim() ?? '';

    if (normalized.isEmpty) return 'Role not assigned';

    switch (normalized.toLowerCase()) {
      case 'admin':
        return 'Head Nurse';
      case 'superadmin':
        return 'Super Admin';
      default:
        final words = normalized.replaceAll('_', ' ').split(' ');
        final readable = words
            .where((word) => word.isNotEmpty)
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join(' ');
        // Keeps an unexpected role string from ever growing large enough to
        // look out of place in a compact pill.
        return readable.length > 24 ? '${readable.substring(0, 24)}…' : readable;
    }
  }

  Widget _adminCard(Map<String, dynamic> admin) {
    final fullName = admin['full_name'] as String? ?? 'Unknown';
    final email = admin['email'] as String? ?? 'No email';
    final phone = admin['phone'] as String? ?? 'No phone';
    final status = admin['status'] ?? 'active';
    final roleLabel = _roleLabel(admin['role'] as String?);
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
                        _StatusPill(label: roleLabel, color: _primary),
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

          // Inactive accounts can only be reactivated -- they can no longer
          // be edited or deactivated again from here.
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
            children: isInactive
                ? [
                    FilledButton.icon(
                      onPressed: () => _openReactivateAdmin(admin),
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Reactivate'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _primary,
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
                  ]
                : [
                    FilledButton.icon(
                      onPressed: () => _openEditAdmin(admin),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _primary,
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
                    FilledButton.icon(
                      onPressed: () => _deleteAdmin(admin),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Deactivate'),
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
                        'Head Nurse Access Control',
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
                      'Manage clinic head nurse accounts, update account details, and review head nurse activity history.',
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

  Widget _buildContent({
    required List<Map<String, dynamic>> rawItems,
    required List<Map<String, dynamic>> visibleItems,
  }) {
    // Distinguishes "no accounts exist at all" from "accounts exist, but the
    // current search/filters matched none of them" -- only relevant to the
    // Accounts tab, since the Audit Trail tab has no filters applied to it.
    final isFilteredEmpty =
        !_showLogs && rawItems.isNotEmpty && visibleItems.isEmpty;

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
              if (!_showLogs) ...[
                const SizedBox(height: 18),
                _buildAccountFilters(),
              ],
              const SizedBox(height: 22),
              if (visibleItems.isEmpty)
                _EmptyState(
                  icon: isFilteredEmpty
                      ? Icons.search_off_rounded
                      : (_showLogs
                            ? Icons.manage_search_rounded
                            : Icons.admin_panel_settings_outlined),
                  title: isFilteredEmpty
                      ? 'No accounts match your search or filters.'
                      : (_showLogs
                            ? 'No audit logs found'
                            : 'No head nurse accounts'),
                  message: isFilteredEmpty
                      ? 'Try a different search term or adjust your filters.'
                      : (_showLogs
                            ? 'Head nurse activity history will appear here.'
                            : 'Create head nurse account to assign access to a clinic.'),
                  actionLabel: isFilteredEmpty ? 'Clear Filters' : null,
                  onAction: isFilteredEmpty ? _clearAccountFilters : null,
                )
              else if (_showLogs)
                Column(children: visibleItems.map(_buildLogsCard).toList())
              else
                Column(children: visibleItems.map(_adminCard).toList()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchText = value),
          decoration: InputDecoration(
            hintText: 'Search accounts...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchText.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchText = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: const Color(0xFFF6FBFF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildCompactAccountDropdown<String?>(
              keyPrefix: 'account-status',
              icon: Icons.tune_rounded,
              value: _statusFilter,
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('All')),
                DropdownMenuItem<String?>(
                  value: 'active',
                  child: Text('Active'),
                ),
                DropdownMenuItem<String?>(
                  value: 'inactive',
                  child: Text('Inactive'),
                ),
              ],
              onChanged: (value) => setState(() => _statusFilter = value),
            ),
            _buildCompactAccountDropdown<_AccountSortOption>(
              keyPrefix: 'account-sort',
              icon: Icons.sort_rounded,
              value: _sortOption,
              items: _AccountSortOption.values
                  .map(
                    (option) => DropdownMenuItem<_AccountSortOption>(
                      value: option,
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _sortOption = value);
              },
            ),
            if (_hasActiveAccountFilters)
              TextButton.icon(
                onPressed: _clearAccountFilters,
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear Filters'),
              ),
          ],
        ),
      ],
    );
  }

  // Compact dropdown matching the search field's style (filled, rounded,
  // borderless). Keyed on the current value so an external reset (e.g. Clear
  // Filters) reliably resyncs the dropdown -- DropdownButtonFormField only
  // reads `initialValue` once per widget identity, same reason the Centers
  // page's filter dropdowns are keyed.
  Widget _buildCompactAccountDropdown<T>({
    required String keyPrefix,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<T>(
        key: ValueKey('$keyPrefix-$value'),
        initialValue: value,
        isExpanded: true,
        icon: const Icon(Icons.expand_more_rounded, size: 18),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(icon, size: 18, color: _primary),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: const Color(0xFFF6FBFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  DateTime _parseCreatedAt(Map<String, dynamic> item) {
    final rawDate = item['created_at'] ?? item['createdAt'];

    if (rawDate == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.tryParse(rawDate.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<Map<String, dynamic>> _sortAccountsByRecentCreated(
    List<Map<String, dynamic>> items,
  ) {
    final sortedItems = List<Map<String, dynamic>>.from(items);

    sortedItems.sort((a, b) {
      final dateA = _parseCreatedAt(a);
      final dateB = _parseCreatedAt(b);

      return dateB.compareTo(dateA);
    });

    return sortedItems;
  }

  String _accountSortName(Map<String, dynamic> admin) {
    final name = admin['full_name'] as String?;
    return (name ?? '').trim().toLowerCase();
  }

  /// Search -> Status filter -> Sort, applied in that order on top of the
  /// already-loaded account list for the current tab. Nothing here touches
  /// the database query or the underlying list passed in -- a new filtered
  /// list is returned each time.
  List<Map<String, dynamic>> _applyAccountFilters(
    List<Map<String, dynamic>> items,
  ) {
    Iterable<Map<String, dynamic>> result = items;

    final query = _searchText.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((admin) {
        final name = (admin['full_name'] as String? ?? '').toLowerCase();
        final email = (admin['email'] as String? ?? '').toLowerCase();
        final phone = (admin['phone'] as String? ?? '').toLowerCase();
        final clinicName =
            (admin['clinics']?['name'] as String? ?? '').toLowerCase();

        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query) ||
            clinicName.contains(query);
      });
    }

    final statusFilter = _statusFilter;
    if (statusFilter != null) {
      result = result.where((admin) {
        // Same "missing status defaults to active" convention _adminCard
        // already uses below, so filtering and display never disagree.
        final status = (admin['status'] as String?) ?? 'active';
        return status.toLowerCase() == statusFilter;
      });
    }

    final filtered = result.toList();

    switch (_sortOption) {
      case _AccountSortOption.newest:
        return _sortAccountsByRecentCreated(filtered);
      case _AccountSortOption.oldest:
        filtered.sort(
          (a, b) => _parseCreatedAt(a).compareTo(_parseCreatedAt(b)),
        );
      case _AccountSortOption.nameAsc:
        filtered.sort(
          (a, b) => _accountSortName(a).compareTo(_accountSortName(b)),
        );
      case _AccountSortOption.nameDesc:
        filtered.sort(
          (a, b) => _accountSortName(b).compareTo(_accountSortName(a)),
        );
    }

    return filtered;
  }

  bool get _hasActiveAccountFilters =>
      _searchText.trim().isNotEmpty ||
      _statusFilter != null ||
      _sortOption != _AccountSortOption.newest;

  void _clearAccountFilters() {
    _searchController.clear();
    setState(() {
      _searchText = '';
      _statusFilter = null;
      _sortOption = _AccountSortOption.newest;
    });
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
              final visibleItems = _showLogs
                  ? items
                  : _applyAccountFilters(items);

              return _buildContent(
                rawItems: items,
                visibleItems: visibleItems,
              );
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
    final data = await SupabaseConfig.client
        .from('clinics')
        .select()
        .or('status.is.null,status.neq.closed')
        .order('name', ascending: true);

    if (!mounted) return;

    setState(() {
      _clinics = List<Map<String, dynamic>>.from(data);
    });
  }

  Future<void> _loadAdmins() async {
    final data = await SupabaseConfig.client
        .from('profiles')
        .select('clinic_id')
        .eq('role', 'admin')
        .eq('status', 'active')
        .eq('is_active', true)
        .not('clinic_id', 'is', null);

    if (!mounted) return;

    setState(() {
      _clinicsWithAdmin = data
          .map((e) => e['clinic_id']?.toString())
          .whereType<String>()
          .toSet();
    });
  }

  Future<void> _saveChanges() async {
    // Explicit re-entrancy guard: the onPressed: _isSaving ? null : ...
    // gate on the button only takes effect once the modal rebuilds, so two
    // very fast taps/submits could otherwise both reach this handler before
    // that rebuild happens. This stops a second submission cold even then.
    if (_isSaving) return;

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

    try {
      await _service.updateAdmin(
        adminId: widget.admin['id'],
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _changePassword && password.isNotEmpty ? password : null,
        clinicId: selectedClinicId,
      );

      // Only record the audit entry once the update has actually succeeded --
      // previously this was written before updateAdmin() was even attempted,
      // so a failed update could still leave behind a successful-looking
      // "edit_admin" log entry. Same action/target content as before.
      await ProfileService().logAction(
        action: 'edit_admin',
        targetId: widget.admin['id'],
        targetName: _nameController.text.trim(),
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

    // Makes it unmistakable which existing account is being edited, not just
    // that this is "edit mode" -- same pattern used for the Center edit
    // dialog in Feature 4.
    final fullName = (widget.admin['full_name'] as String?)?.trim();
    final editingLabel = (fullName != null && fullName.isNotEmpty)
        ? fullName
        : email.toString();

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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Edit Head Nurse Account',
                                  style: TextStyle(
                                    color: _dark,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Update account details and password settings.',
                                  style: TextStyle(color: _muted, fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.edit_note_rounded,
                                        size: 15,
                                        color: _primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Editing: $editingLabel',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: _dark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                        inputFormatters: [_MaxDigitsTextInputFormatter(11)],
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
                            'Enable this only if the head nurse needs a new password.',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                          value: _changePassword,
                          activeThumbColor: _primary,
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
                              _isSaving ? 'Updating...' : 'Update Account',
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

class _BlurredAdminReactivateModal extends StatefulWidget {
  final Map<String, dynamic> admin;

  const _BlurredAdminReactivateModal({required this.admin});

  @override
  State<_BlurredAdminReactivateModal> createState() =>
      _BlurredAdminReactivateModalState();
}

class _BlurredAdminReactivateModalState
    extends State<_BlurredAdminReactivateModal> {
  final _formKey = GlobalKey<FormState>();
  final ProfileService _service = ProfileService();

  bool _isSubmitting = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _clinics = [];
  Set<String> _clinicsWithAdmin = {};
  String? _selectedClinicId;

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

  // Same clinic query already used by the Create/Edit modals -- excludes
  // closed centers, matching the existing pattern.
  Future<void> _loadClinics() async {
    final data = await SupabaseConfig.client
        .from('clinics')
        .select()
        .or('status.is.null,status.neq.closed')
        .order('name', ascending: true);

    if (!mounted) return;

    setState(() {
      _clinics = List<Map<String, dynamic>>.from(data);
    });
  }

  // Same "which clinics already have an active admin" query already used by
  // the Create/Edit modals. status='active' + is_active=true here means an
  // inactive admin's old clinic_id (already cleared to null by deleteAdmin
  // anyway) never counts against availability.
  Future<void> _loadAdmins() async {
    final data = await SupabaseConfig.client
        .from('profiles')
        .select('clinic_id')
        .eq('role', 'admin')
        .eq('status', 'active')
        .eq('is_active', true)
        .not('clinic_id', 'is', null);

    if (!mounted) return;

    setState(() {
      _clinicsWithAdmin = data
          .map((e) => e['clinic_id']?.toString())
          .whereType<String>()
          .toSet();
    });
  }

  bool get _hasAvailableClinics =>
      _clinics.any((clinic) => !_clinicsWithAdmin.contains(clinic['id']));

  Future<void> _reactivate() async {
    // Explicit re-entrancy guard: the onPressed: _isSubmitting ? null : ...
    // gate on the button only takes effect once the modal rebuilds, so two
    // very fast taps/submits could otherwise both reach this handler before
    // that rebuild happens. This stops a second submission cold even then.
    if (_isSubmitting) return;

    if (!_formKey.currentState!.validate()) return;

    if (_selectedClinicId == null) {
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
      await _service.reactivateAdmin(
        adminId: widget.admin['id'] as String,
        clinicId: _selectedClinicId!,
      );

      // Only record the audit entry once the update has actually succeeded,
      // same principle applied to Edit in Subtask 3.
      await ProfileService().logAction(
        action: 'reactivate_admin',
        targetId: widget.admin['id'],
        targetName:
            widget.admin['full_name'] ?? widget.admin['email'] ?? 'Unknown',
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
    final fullName = (widget.admin['full_name'] as String?)?.trim();
    final email = widget.admin['email'] as String? ?? '-';
    final displayLabel = (fullName != null && fullName.isNotEmpty)
        ? fullName
        : email;
    final hasAvailableClinics = _hasAvailableClinics;

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
                width: 560,
                constraints: const BoxConstraints(maxWidth: 560),
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
                              Icons.restart_alt_rounded,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Reactivate Head Nurse Account',
                                  style: TextStyle(
                                    color: _dark,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  displayLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
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
                                'This account is currently inactive. Select a '
                                'clinic to restore active access. The previous '
                                'clinic assignment was not retained, so this '
                                'is a new assignment.',
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Clinic Assignment',
                          style: const TextStyle(
                            color: _dark,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!hasAvailableClinics)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'No clinics are currently available for assignment.',
                            style: TextStyle(
                              color: Color(0xFF8A651C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          decoration: _inputDecoration(
                            label: 'Choose a clinic',
                            icon: Icons.local_hospital_outlined,
                          ),
                          initialValue: _selectedClinicId,
                          hint: const Text('Choose a clinic'),
                          items: _clinics.map((clinic) {
                            final clinicId = clinic['id'].toString();
                            final hasAdmin = _clinicsWithAdmin.contains(
                              clinicId,
                            );

                            return DropdownMenuItem<String>(
                              value: clinicId,
                              enabled: !hasAdmin,
                              child: Text(
                                '${clinic['name'] ?? 'Unnamed clinic'}'
                                '${hasAdmin ? ' (Has Head Nurse Account)' : ''}',
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedClinicId = value);
                          },
                          validator: (value) =>
                              value == null ? 'Please select a clinic.' : null,
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
                            onPressed: (_isSubmitting || !hasAvailableClinics)
                                ? null
                                : _reactivate,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.restart_alt_rounded),
                            label: Text(
                              _isSubmitting ? 'Reactivating...' : 'Reactivate',
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
    final data = await SupabaseConfig.client
        .from('clinics')
        .select()
        .or('status.is.null,status.neq.closed')
        .order('name', ascending: true);

    if (!mounted) return;

    setState(() {
      _clinics = List<Map<String, dynamic>>.from(data);
    });
  }

  Future<void> _loadAdmins() async {
    final data = await SupabaseConfig.client
        .from('profiles')
        .select('clinic_id')
        .eq('role', 'admin')
        .eq('status', 'active')
        .eq('is_active', true)
        .not('clinic_id', 'is', null);

    if (!mounted) return;

    setState(() {
      _clinicsWithAdmin = data
          .map((e) => e['clinic_id']?.toString())
          .whereType<String>()
          .toSet();
    });
  }

  Future<void> _createAccount() async {
    // Explicit re-entrancy guard: the onPressed: _isSubmitting ? null : ...
    // gate on the button only takes effect once the modal rebuilds, so two
    // very fast taps/submits could otherwise both reach this handler before
    // that rebuild happens. This stops a second submission cold even then.
    if (_isSubmitting) return;

    if (!_formKey.currentState!.validate()) return;

    // Password match is already enforced by the Confirm Password field's own
    // validator (_validateConfirmPassword) above, which the Form.validate()
    // call just checked -- re-checking it here would be redundant.

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

  /// Reasonable, non-restrictive email format check: local-part@domain.tld,
  /// no whitespace. Rejects obviously invalid input (missing "@", missing a
  /// domain, missing a TLD) without imposing a stricter format than normal
  /// email addresses actually use.
  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) return 'Enter email address';

    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  /// Allows the characters normally found in a phone number (digits, spaces,
  /// +, -, parentheses) and validates by digit count rather than one exact
  /// formatting style -- same approach used for center Contact Number
  /// validation elsewhere in this app.
  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';

    if (phone.isEmpty) return 'Enter phone number';

    final allowedCharacters = RegExp(r'^[0-9+\-() ]+$');
    if (!allowedCharacters.hasMatch(phone)) {
      return 'Enter a valid phone number';
    }

    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length < 7) {
      return 'Enter a valid phone number';
    }

    return null;
  }

  /// Validates the same (trimmed) value that is actually sent to
  /// Supabase Auth at submission time, so a password that passes here can
  /// never fail length-wise once trimmed for signUp.
  String? _validatePassword(String? value) {
    final password = value?.trim() ?? '';

    if (password.isEmpty) return 'Enter password';

    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }

    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final confirm = value?.trim() ?? '';

    if (confirm.isEmpty) return 'Confirm your password';

    if (confirm != _passwordController.text.trim()) {
      return 'Passwords do not match';
    }

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
                                  'Create Head Nurse Account',
                                  style: TextStyle(
                                    color: _dark,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Assign clinic\'s head nurse and create login access.',
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
                                'Only clinics without an existing head nurse account can be selected.',
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
                            value: clinicId,
                            enabled: !hasAdmin,
                            child: Text(
                              '${clinic['name'] ?? 'Unnamed clinic'}'
                              '${hasAdmin ? ' (Has Head Nurse Account)' : ''}',
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
                          hint: 'Enter head nurse full name',
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
                          hint: 'Enter head nurse email',
                        ),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_MaxDigitsTextInputFormatter(11)],
                        decoration: _inputDecoration(
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                          hint: 'Enter phone number',
                        ),
                        validator: _validatePhone,
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
                              helperText: 'At least 8 characters',
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
                        validator: _validatePassword,
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
                        validator: _validateConfirmPassword,
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
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
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
            textAlign: TextAlign.center,
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
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.clear_all_rounded),
              label: Text(actionLabel!),
            ),
          ],
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
