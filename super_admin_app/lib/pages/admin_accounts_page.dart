import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/profile_service.dart';
import '../config/supabase_config.dart';
import '../theme/app_theme.dart';

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
      decoration: AppTheme.card(radius: AppTheme.rLg),
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
                        backgroundColor: AppTheme.blue1,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rMd),
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
                        backgroundColor: AppTheme.blue1,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rMd),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _deleteAdmin(admin),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Deactivate'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rMd),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: AppTheme.iconBox(AppTheme.accentOrangeSoft),
            child: const Icon(
              Icons.history_rounded,
              color: AppTheme.accentOrange,
              size: 19,
            ),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.white, AppTheme.headerTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
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
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.accentBlueSoft,
                            borderRadius: BorderRadius.circular(AppTheme.rLg),
                            border: Border.all(color: AppTheme.borderStrong),
                          ),
                          child: const Icon(
                            Icons.manage_accounts_rounded,
                            color: AppTheme.blue1,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account Management',
                                style: TextStyle(
                                  color: AppTheme.blue3,
                                  fontSize: 22,
                                  height: 1.25,
                                  letterSpacing: -0.3,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Manage clinic head nurse accounts, update account details, and review head nurse activity history.',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13.5,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isCompact) const SizedBox(height: 18) else const SizedBox(width: 24),
              SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: _openCreateAdmin,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add Account'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.blue1,
                    foregroundColor: AppTheme.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
        const SizedBox(height: AppTheme.gapLg),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.card(),
          child: Column(
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Accounts'),
                    selected: !_showLogs,
                    selectedColor: AppTheme.accentBlueSoft,
                    backgroundColor: AppTheme.surface,
                    checkmarkColor: AppTheme.blue1,
                    side: const BorderSide(color: AppTheme.border),
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(
                      color: !_showLogs ? AppTheme.blue1 : AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
                    selectedColor: AppTheme.accentBlueSoft,
                    backgroundColor: AppTheme.surface,
                    checkmarkColor: AppTheme.blue1,
                    side: const BorderSide(color: AppTheme.border),
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(
                      color: _showLogs ? AppTheme.blue1 : AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                      tooltip: 'Refresh',
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.accentBlueSoft,
                        foregroundColor: AppTheme.blue1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rMd),
                        ),
                      ),
                    ),
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
          style: AppTheme.fieldTextStyle,
          decoration: AppTheme.field(
            hintText: 'Search accounts...',
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 19,
              color: AppTheme.iconMuted,
            ),
            suffixIcon: _searchText.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchText = '');
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.iconMuted,
                    ),
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
                icon: const Icon(Icons.clear_all_rounded, size: 17),
                label: const Text('Clear Filters'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.blue1,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
      width: 190,
      child: DropdownButtonFormField<T>(
        key: ValueKey('$keyPrefix-$value'),
        initialValue: value,
        isExpanded: true,
        style: AppTheme.fieldTextStyle,
        icon: const Icon(
          Icons.expand_more_rounded,
          size: 18,
          color: AppTheme.iconMuted,
        ),
        dropdownColor: AppTheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(AppTheme.menuRadius),
        decoration: AppTheme.field(
          dense: true,
          prefixIcon: Icon(icon, size: 17, color: AppTheme.blue1),
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
    final pagePadding = AppTheme.pagePadding(
      MediaQuery.of(context).size.width,
    );

    return Container(
      color: _bg,
      child: AppMenuTheme(
        child: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          // Padded inside the scroll view so the scrollbar rides the
          // viewport edge instead of floating inset from it.
          padding: EdgeInsets.all(pagePadding),
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

  final ProfileService _service = ProfileService();

  bool _isSaving = false;
  String? _errorMessage;

  // No password state here on purpose. Editing a head nurse's password was
  // removed (R4): the only client-side API available, auth.updateUser(), acts
  // on the CURRENTLY AUTHENTICATED user and takes no target id, so it changed
  // the Super Admin's own password instead of the nurse's while reporting
  // success. Setting another user's password needs a privileged server-side
  // call, which a client holding only the anon key cannot make. The Create
  // modal keeps its password fields -- those set the new account's own
  // password at sign-up time and are unaffected.

  List<Map<String, dynamic>> _clinics = [];
  Set<String> _clinicsWithAdmin = {};
  String? selectedClinicId;

  static const Color _primary = Color(0xFF0F719F);

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

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _service.updateAdmin(
        adminId: widget.admin['id'],
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
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
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(color: const Color(0x4D1F2D3D)),
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
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.rXl),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: AppTheme.iconBox(
                              AppTheme.accentBlueSoft,
                            ),
                            child: const Icon(
                              Icons.manage_accounts_outlined,
                              color: AppTheme.blue1,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Head Nurse Account',
                                  style: TextStyle(
                                    color: AppTheme.blue3,
                                    fontSize: 17,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Update account details.',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.close_rounded, size: 19),
                            color: AppTheme.iconMuted,
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppTheme.border,
                      ),
                      const SizedBox(height: 16),
                      // Which account is being edited - kept on its own row so
                      // the header reads the same as the Create modal's.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceTint,
                          borderRadius: BorderRadius.circular(AppTheme.rMd),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.edit_note_rounded,
                              size: 18,
                              color: AppTheme.blue1,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Editing: $editingLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerSoft,
                            borderRadius: BorderRadius.circular(AppTheme.rMd),
                            border: Border.all(
                              color: AppTheme.danger.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: AppTheme.danger,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: AppTheme.danger,
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      DropdownButtonFormField<String?>(
                        // Long clinic names ellipsize instead of overflowing the field.
                        isExpanded: true,
                        dropdownColor: AppTheme.surface,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(AppTheme.menuRadius),
                        icon: const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: AppTheme.iconMuted,
                        ),
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
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.textSecondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 15,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                              backgroundColor: AppTheme.blue1,
                              foregroundColor: AppTheme.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rMd,
                                ),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
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
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(color: const Color(0x4D1F2D3D)),
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
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.rXl),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.shadowMd,
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
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerSoft,
                            borderRadius: BorderRadius.circular(AppTheme.rMd),
                            border: Border.all(
                              color: AppTheme.danger.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: AppTheme.danger,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: AppTheme.danger,
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
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
                          // Long clinic names ellipsize instead of overflowing the field.
                          isExpanded: true,
                          dropdownColor: AppTheme.surface,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(AppTheme.menuRadius),
                          icon: const Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: AppTheme.iconMuted,
                          ),
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
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.textSecondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 15,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                              backgroundColor: AppTheme.blue1,
                              foregroundColor: AppTheme.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rMd,
                                ),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
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

    // MITIGATION (R3): auth.signUp() is Supabase's SELF-REGISTRATION call --
    // whenever the project returns a session for the new account, the SDK
    // stores it as the current session, so the Super Admin is silently
    // replaced by the head nurse being created. Everything after that point
    // (the profiles insert, the audit entry) would then run as the wrong
    // user. So the Super Admin's own session is captured here, restored
    // immediately after signUp(), and proven to be back before anything is
    // written.
    //
    // This does NOT fix the underlying provisioning problem: creating another
    // user without assuming their identity needs a privileged server-side
    // call, which a client holding only the anon key cannot make. It narrows
    // a reliable failure to a brief window -- see the failure path in
    // _abandonToRelogin.
    //
    // Tokens captured here are only handed back to the SDK; they are never
    // logged, printed, or stored.
    final client = SupabaseConfig.client;
    final superAdminSession = client.auth.currentSession;
    final superAdminId = superAdminSession?.user.id;
    final superAdminRefreshToken = superAdminSession?.refreshToken;
    final superAdminAccessToken = superAdminSession?.accessToken;

    if (superAdminId == null || superAdminRefreshToken == null) {
      setState(() {
        _errorMessage =
            'Your session could not be verified. Please log in again before '
            'creating an account.';
      });
      return;
    }

    // Resolved before any await so the modal's BuildContext is never used
    // across an async gap -- both survive this route being removed, which the
    // failure path below does.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final authResponse = await client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = authResponse.user;

      if (user == null) {
        throw Exception('User creation failed');
      }

      // Put the Super Admin's session back before anything is written. Only
      // needed when signUp() actually returned a session (with email
      // confirmation enabled it does not, and the session was never
      // replaced), but a failure here is deliberately swallowed: the identity
      // check below is the real gate, and it fails safe either way.
      if (authResponse.session != null) {
        try {
          await client.auth.setSession(
            superAdminRefreshToken,
            accessToken: superAdminAccessToken,
          );
        } catch (_) {
          // Fall through to the identity check.
        }
      }

      // The gate. Nothing is written until the current user is provably the
      // Super Admin who started this. Checked even when signUp() returned no
      // session, so an unexpected identity can never slip past.
      if (client.auth.currentUser?.id != superAdminId) {
        await _abandonToRelogin(messenger, navigator);
        return;
      }

      await client.from('profiles').insert({
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
      navigator.pop(true);
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

  /// Failure path for the R3 session-restore mitigation above: the current
  /// user is not the Super Admin who opened this modal, so the app is holding
  /// a session it cannot vouch for -- possibly the newly created head nurse's.
  ///
  /// Nothing is written and no success is reported. The unknown session is
  /// cleared and the Super Admin is sent back to Login, which is safer than
  /// continuing in an unverified identity. signOut() failing must not block
  /// the redirect, so it is swallowed; it clears the local session before it
  /// attempts the server call anyway.
  ///
  /// The message says what actually happened: signUp() may well have created
  /// the auth user before the session was lost, so this does not claim the
  /// account was not created -- it says setup stopped and asks the Super Admin
  /// to check before retrying (a retry with the same email would be rejected
  /// as already taken).
  Future<void> _abandonToRelogin(
    ScaffoldMessengerState messenger,
    NavigatorState navigator,
  ) async {
    try {
      await SupabaseConfig.client.auth.signOut();
    } catch (_) {
      // Ignored on purpose -- the redirect below matters more.
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Your Super Admin session could not be restored, so setting up the '
          'new account was stopped. Please log in again and check the account '
          'list before retrying.',
        ),
        duration: Duration(seconds: 6),
      ),
    );

    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return AppTheme.field(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: AppTheme.blue1),
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
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(color: const Color(0x4D1F2D3D)),
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
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.rXl),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: AppTheme.iconBox(
                              AppTheme.accentBlueSoft,
                            ),
                            child: const Icon(
                              Icons.person_add_alt_1_rounded,
                              color: AppTheme.blue1,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create Head Nurse Account',
                                  style: TextStyle(
                                    color: AppTheme.blue3,
                                    fontSize: 17,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Assign clinic\'s head nurse and create login access.',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.close_rounded, size: 19),
                            color: AppTheme.iconMuted,
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppTheme.border,
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceTint,
                          borderRadius: BorderRadius.circular(AppTheme.rMd),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: AppTheme.blue1,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Only clinics without an existing head nurse account can be selected.',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerSoft,
                            borderRadius: BorderRadius.circular(AppTheme.rMd),
                            border: Border.all(
                              color: AppTheme.danger.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: AppTheme.danger,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: AppTheme.danger,
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      DropdownButtonFormField<String>(
                        // Long clinic names ellipsize instead of overflowing the field.
                        isExpanded: true,
                        dropdownColor: AppTheme.surface,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(AppTheme.menuRadius),
                        icon: const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: AppTheme.iconMuted,
                        ),
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
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.textSecondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 15,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                              backgroundColor: AppTheme.blue1,
                              foregroundColor: AppTheme.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rMd,
                                ),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
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
