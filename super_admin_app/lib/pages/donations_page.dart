import 'package:flutter/material.dart';
import '../models/center_donation_history_entry.dart';
import '../models/donation_record.dart';
import 'package:super_admin_app/services/donation_service.dart';
import '../theme/app_theme.dart';

/// Preset date windows for the Center Donation History filter. Applied
/// client-side against the existing donation date -- no new fields or queries.
enum _HistoryDateRange {
  allTime('All Time', null),
  last7Days('Last 7 Days', 7),
  last30Days('Last 30 Days', 30),
  last90Days('Last 90 Days', 90),
  thisYear('This Year', null);

  const _HistoryDateRange(this.label, this.days);

  final String label;
  final int? days;
}

/// One display row in the Overall Donation History table. Not a persisted
/// model -- just a normalized shape so the table/search/filter code can treat
/// "All Centers" rows (from DonationRecord, one per raw donation) and
/// "one center selected" rows (from CenterDonationHistoryEntry, one per
/// center-share) identically.
class _OverallHistoryRow {
  final String donationId;
  final double amount;
  final String allocationType;
  final String status;
  final DateTime date;
  final String centerLabel;
  final String? donorName;
  final String? donorEmail;

  _OverallHistoryRow({
    required this.donationId,
    required this.amount,
    required this.allocationType,
    required this.status,
    required this.date,
    required this.centerLabel,
    this.donorName,
    this.donorEmail,
  });

  String get allocationLabel {
    switch (allocationType) {
      case 'specific_center':
        return 'Specific Center';
      case 'random_center':
        return 'Random';
      case 'equal_distribution':
        return 'Equal Share';
      default:
        return 'Not recorded';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'verified':
        return 'Received';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }
}

class DonationsPage extends StatefulWidget {
  const DonationsPage({super.key});

  @override
  State<DonationsPage> createState() => _DonationsPageState();
}

class _DonationsPageState extends State<DonationsPage> {
  final DonationService _service = DonationService();

  bool _isLoading = true;
  List<DonationRecord> _donations = [];
  List<Map<String, dynamic>> _centers = [];

  double _totalVerifiedDonations = 0;

  /// How many of the loaded donations are verified, shown under the Total
  /// Donations figure. Owned by this State rather than being a top-level
  /// variable (R21): as a global it was shared by every DonationsPage and
  /// outlived each one, so re-entering the page briefly showed the previous
  /// visit's count until the fresh load completed. Same value, same
  /// calculation -- only where it lives has changed.
  int _verifiedCount = 0;

  // Center Donation History section.
  String? _historyCenterId;
  List<CenterDonationHistoryEntry> _historyEntries = [];
  bool _isLoadingHistory = false;

  // Center Donation History filters -- applied client-side to the already
  // loaded _historyEntries, so they only affect which rows the table shows.
  final TextEditingController _historySearchController = TextEditingController();
  String _historySearch = '';
  _HistoryDateRange _historyRange = _HistoryDateRange.allTime;

  // Overall Donation History section (read-only, all centers). Fully
  // independent of the Center Donation History state above -- it reuses the
  // same _HistoryDateRange presets but keeps its own selection/search/range
  // so neither section affects the other. "All Centers" (null) reads
  // straight from _donations (already loaded); picking one center switches
  // to _overallCenterEntries, fetched via the same fetchCenterDonationHistory
  // the Center Donation History section already uses.
  String? _overallCenterId;
  List<CenterDonationHistoryEntry> _overallCenterEntries = [];
  bool _isLoadingOverall = false;
  final TextEditingController _overallSearchController = TextEditingController();
  String _overallSearch = '';
  _HistoryDateRange _overallRange = _HistoryDateRange.allTime;

  static const Color _primary = Color(0xFF0F719F);
  static const Color _dark = Color(0xFF0F3A55);
  static const Color _muted = Color(0xFF647583);
  static const Color _bg = Color(0xFFF3F7FA);
  static const Color _success = Color(0xFF2E7D32);
  static const Color _danger = Color(0xFFDE4D4D);
  static const Color _warning = Color(0xFFFB8B3C);

  // Center Donation History panel: fixed-but-responsive heights so the
  // section reads as a bounded dashboard card (sidebar + history both
  // scroll internally) instead of growing with the record count.
  static const double _historyPanelHeightWide = 500;
  static const double _historyPanelHeightCompact = 440;
  static const double _tabletBreakpoint = 900;
  static const double _mobileBreakpoint = 640;

  Map<String, dynamic>? get _selectedHistoryCenter {
    for (final center in _centers) {
      if (center['id'].toString() == _historyCenterId) return center;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedOverallCenter {
    for (final center in _centers) {
      if (center['id'].toString() == _overallCenterId) return center;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadDonations();
  }

  @override
  void dispose() {
    _historySearchController.dispose();
    _overallSearchController.dispose();
    super.dispose();
  }

  String _formatCompactCurrency(double amount) {
    if (amount >= 1000000) {
      return '₱${(amount / 1000000).toStringAsFixed(amount % 1000000 == 0 ? 0 : 1)}M';
    }

    if (amount >= 1000) {
      return '₱${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}K';
    }

    return '₱${amount.toStringAsFixed(0)}';
  }

  Future<void> _loadDonations() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final donations = await _service.fetchDonations();
      final centers = await _service.fetchCenters();
      final totalDonations = await _service.fetchTotalDonations();

      if (!mounted) return;

      setState(() {
        _donations = donations;
        _centers = centers;

        _totalVerifiedDonations = totalDonations;

        _verifiedCount = donations.where((d) => d.status == 'verified').length;

        // Keep the current selection if that center still exists in this
        // fresh list, otherwise fall back to the first center.
        final stillExists = centers.any((c) => c['id'].toString() == _historyCenterId);
        if (_historyCenterId == null || !stillExists) {
          _historyCenterId = centers.isNotEmpty ? centers.first['id'].toString() : null;
        }

        // Same reconciliation for the Overall Donation History selector,
        // which previously had none. Now that closed centers are filtered
        // out of this list, a selection made before a center was closed can
        // point at an id the dropdown no longer offers -- and its items must
        // contain the selected value exactly once.
        //
        // Reset goes to null, not to centers.first: null is this dropdown's
        // own "All Centers" option (unlike the Center Donation History
        // selector above, which has no such option and must always hold a
        // center). So null is always a valid item here, it is this section's
        // normal default, and it avoids silently switching the Super Admin
        // onto an unrelated center's records. A null selection is therefore
        // left exactly as it is.
        final overallCenterId = _overallCenterId;
        if (overallCenterId != null &&
            !centers.any((c) => c['id'].toString() == overallCenterId)) {
          _overallCenterId = null;
        }
      });

      if (_historyCenterId != null) {
        await _loadCenterHistory(_historyCenterId!);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load donations: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCenterHistory(String clinicId) async {
    if (mounted) {
      setState(() => _isLoadingHistory = true);
    }

    try {
      final entries = await _service.fetchCenterDonationHistory(clinicId);
      if (!mounted) return;
      setState(() => _historyEntries = entries);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load center history: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  /// Loads a single center's donations for the Overall Donation History
  /// section when it is narrowed from "All Centers" to one center. Reuses
  /// the exact same service call as _loadCenterHistory above -- this method
  /// only exists so the two sections keep fully independent state.
  Future<void> _loadOverallHistory(String clinicId) async {
    if (mounted) {
      setState(() => _isLoadingOverall = true);
    }

    try {
      final entries = await _service.fetchCenterDonationHistory(clinicId);
      if (!mounted) return;
      setState(() => _overallCenterEntries = entries);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load overall donation history: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingOverall = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final verifiedRecords = _verifiedCount;

    final pagePadding = AppTheme.pagePadding(
      MediaQuery.of(context).size.width,
    );

    return Container(
      color: _bg,
      child: AppMenuTheme(
        child: RefreshIndicator(
        onRefresh: _loadDonations,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          // Padded inside the scroll view so the scrollbar rides the
          // viewport edge instead of floating inset from it.
          padding: EdgeInsets.all(pagePadding),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1150;
              final statWidth = isWide
                  ? (constraints.maxWidth - 32) / 3
                  : constraints.maxWidth >= 760
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: AppTheme.gapLg),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: statWidth,
                        child: _InfoCard(
                          icon: Icons.volunteer_activism_outlined,
                          label: 'Total Donations',
                          value: _formatCompactCurrency(
                            _totalVerifiedDonations,
                          ),
                          // No "awaiting review" figure: donations are
                          // recorded as verified at submission time, so
                          // there is no pending queue and no review action
                          // in this UI. The old count was the negation of
                          // 'verified', so it also swept in rejected and
                          // legacy/null-status rows and labelled them as
                          // work awaiting the Super Admin.
                          subtitle: '$verifiedRecords verified donation(s)',
                          color: AppTheme.accentPink,
                          softColor: AppTheme.accentPinkSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  _SectionCard(
                    title: 'Center Donation History',
                    subtitle:
                        'Review one center\'s full donation record -- specific, random, and equal-share allocations.',
                    icon: Icons.local_hospital_outlined,
                    accent: AppTheme.accentTeal,
                    accentSoft: AppTheme.accentTealSoft,
                    child: _buildCenterHistory(),
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  _SectionCard(
                    title: 'Overall Donation History',
                    subtitle:
                        'Read-only oversight of donation records across every center -- search, filter by center and date, no approval actions.',
                    icon: Icons.fact_check_outlined,
                    accent: AppTheme.accentGreen,
                    accentSoft: AppTheme.accentGreenSoft,
                    child: _buildOverallHistory(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
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
          final isCompact = constraints.maxWidth < 700;

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
                            color: AppTheme.accentPinkSoft,
                            borderRadius: BorderRadius.circular(AppTheme.rLg),
                            border: Border.all(color: AppTheme.borderStrong),
                          ),
                          child: const Icon(
                            Icons.volunteer_activism_rounded,
                            color: AppTheme.accentPink,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Distribute Donation Funds',
                                style: TextStyle(
                                  fontSize: 22,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: AppTheme.blue3,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Allocate verified donations to centers and keep every distribution transparent.',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.45,
                                  color: AppTheme.textSecondary,
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
            ],
          );
        },
      ),
    );
  }

  Color _historyStatusColor(String status) {
    if (status == 'verified') return _success;
    if (status == 'rejected') return _danger;
    return _warning;
  }

  /// The loaded history rows narrowed by the search box and the date-range
  /// dropdown. Order is left untouched, so the service's newest-first sort is
  /// preserved. Search is a case-insensitive substring match across donor
  /// name, donor email, donation ID, and the selected center's name.
  List<CenterDonationHistoryEntry> _filteredHistoryEntries() {
    final query = _historySearch.trim().toLowerCase();
    final centerName =
        _selectedHistoryCenter?['name']?.toString().toLowerCase() ?? '';

    DateTime? cutoff;
    if (_historyRange == _HistoryDateRange.thisYear) {
      cutoff = DateTime(DateTime.now().year);
    } else if (_historyRange.days != null) {
      cutoff = DateTime.now().subtract(Duration(days: _historyRange.days!));
    }

    return _historyEntries.where((entry) {
      if (cutoff != null && entry.date.isBefore(cutoff)) return false;
      if (query.isEmpty) return true;

      final haystack = [
        entry.donorName ?? '',
        entry.donorEmail ?? '',
        entry.donationId,
        centerName,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  // ---- Overall Donation History (Step 3, read-only, all centers) --------

  /// "All Centers" label for an equal-distribution donation, since one such
  /// donation is not tied to a single center.
  String _overallCenterLabel(DonationRecord donation) {
    if (donation.allocationType == 'equal_distribution') {
      return 'All Centers (Equal Share)';
    }
    return donation.clinicName ?? 'Not recorded';
  }

  /// "All Centers" rows: one row per raw donation, at its full donated
  /// amount. An equal-distribution donation appears exactly once here --
  /// never split -- so totals never double-count.
  List<_OverallHistoryRow> _rowsFromAllDonations() {
    return _donations
        .map(
          (d) => _OverallHistoryRow(
            donationId: d.id,
            amount: d.amount,
            allocationType: d.allocationType ?? '',
            status: d.status,
            date: d.createdAt,
            centerLabel: _overallCenterLabel(d),
            donorName: d.donorName,
            donorEmail: d.email,
          ),
        )
        .toList();
  }

  /// "One center selected" rows: reuses fetchCenterDonationHistory's already
  /// correct per-center amounts, so an equal-distribution donation shows
  /// only that center's actual share, not the full donation amount.
  List<_OverallHistoryRow> _rowsFromOverallCenterEntries(String centerName) {
    return _overallCenterEntries
        .map(
          (e) => _OverallHistoryRow(
            donationId: e.donationId,
            amount: e.amount,
            allocationType: e.allocationType,
            status: e.status,
            date: e.date,
            centerLabel: centerName,
            donorName: e.donorName,
            donorEmail: e.donorEmail,
          ),
        )
        .toList();
  }

  /// Combines the All-Centers/one-center source rows with the search box and
  /// date-range dropdown. Order is left untouched -- both sources are already
  /// newest-first, so that ordering is preserved end to end.
  List<_OverallHistoryRow> _filteredOverallRows() {
    final rows = _overallCenterId == null
        ? _rowsFromAllDonations()
        : _rowsFromOverallCenterEntries(
            _selectedOverallCenter?['name']?.toString() ?? 'Selected Center',
          );

    final query = _overallSearch.trim().toLowerCase();

    DateTime? cutoff;
    if (_overallRange == _HistoryDateRange.thisYear) {
      cutoff = DateTime(DateTime.now().year);
    } else if (_overallRange.days != null) {
      cutoff = DateTime.now().subtract(Duration(days: _overallRange.days!));
    }

    return rows.where((row) {
      if (cutoff != null && row.date.isBefore(cutoff)) return false;
      if (query.isEmpty) return true;

      final haystack = [
        row.donorName ?? '',
        row.donorEmail ?? '',
        row.donationId,
        row.centerLabel,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  void _clearOverallFilters() {
    _overallSearchController.clear();
    setState(() {
      _overallSearch = '';
      _overallRange = _HistoryDateRange.allTime;
    });
  }

  // Sidebar (desktop/tablet) + history panel layout. Data fetching is
  // unchanged from before -- _centers, _historyCenterId, _historyEntries,
  // and _loadCenterHistory all still work exactly as they did with the
  // dropdown-only version; only the selector's presentation changes based
  // on available width, and the mobile breakpoint still reuses that same
  // dropdown rather than inventing a new selector.
  Widget _buildCenterHistory() {
    if (_centers.isEmpty) {
      return const _EmptyState(
        icon: Icons.local_hospital_outlined,
        title: 'No centers yet',
        message: 'Add a dialysis center to see its donation history.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        final isTablet = !isMobile && constraints.maxWidth < _tabletBreakpoint;
        final panelHeight =
            isMobile ? _historyPanelHeightCompact : _historyPanelHeightWide;
        final sidebarWidth = isTablet ? 168.0 : 224.0;

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCenterDropdown(),
              const SizedBox(height: 16),
              SizedBox(height: panelHeight, child: _buildHistoryPanel()),
            ],
          );
        }

        return SizedBox(
          height: panelHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: sidebarWidth, child: _buildCenterSidebar()),
              const SizedBox(width: 22),
              const VerticalDivider(width: 1, color: Color(0xFFE7EFF5)),
              const SizedBox(width: 22),
              Expanded(child: _buildHistoryPanel()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCenterDropdown() {
    // Keyed on the clinic id (a String, compared by content) rather than
    // the clinic Map itself. Map equality in Dart is by reference, and
    // DropdownButtonFormField only reads its `initialValue` once to seed
    // internal state -- it does not resync on every rebuild -- so passing
    // a fresh Map instance from each _loadDonations() reload left the
    // field holding a stale reference that no longer matched any item in
    // `items`, crashing the page. An id string survives that because
    // '6ec...' == '6ec...' regardless of which fetch produced it.
    return DropdownButtonFormField<String>(
      dropdownColor: AppTheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(AppTheme.menuRadius),
      icon: const Icon(
        Icons.expand_more_rounded,
        size: 18,
        color: AppTheme.iconMuted,
      ),
      key: ValueKey(_historyCenterId),
      initialValue: _historyCenterId,
      items: _centers.map((center) {
        return DropdownMenuItem<String>(
          value: center['id'].toString(),
          child: Text(
            center['name']?.toString() ?? 'Unnamed Center',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      decoration: _inputDecoration('Center', Icons.local_hospital_outlined),
      onChanged: (value) async {
        if (value == null) return;
        setState(() => _historyCenterId = value);
        await _loadCenterHistory(value);
      },
    );
  }

  Widget _buildCenterSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 6, bottom: 10),
          child: Text(
            'CENTERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _muted,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            thickness: 4,
            radius: const Radius.circular(8),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _centers.length,
              itemBuilder: (context, index) {
                final center = _centers[index];
                final id = center['id'].toString();
                final isSelected = id == _historyCenterId;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: isSelected
                        ? null
                        : () async {
                            setState(() => _historyCenterId = id);
                            await _loadCenterHistory(id);
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _primary.withAlpha(18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border(
                          left: BorderSide(
                            color: isSelected ? _primary : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        center['name']?.toString() ?? 'Unnamed Center',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? _dark : _muted,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryPanel() {
    final centerName = _selectedHistoryCenter?['name']?.toString() ??
        'Select a center';
    // TOTAL RECEIVED stays a lifetime figure for the center -- it is
    // intentionally computed from the full list, not the filtered view.
    final totalReceived = _historyEntries
        .where((e) => e.status == 'verified')
        .fold<double>(0, (sum, e) => sum + e.amount);

    final visibleEntries = _filteredHistoryEntries();
    final hasFilters =
        _historySearch.trim().isNotEmpty || _historyRange != _HistoryDateRange.allTime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    centerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Donation History',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isLoadingHistory && _historyEntries.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _success.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'TOTAL RECEIVED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: _success,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      '₱${totalReceived.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _success,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFE7EFF5)),
        const SizedBox(height: 6),
        if (!_isLoadingHistory && _historyEntries.isNotEmpty) ...[
          _buildHistoryFilters(),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: _isLoadingHistory
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              : _historyEntries.isEmpty
                  ? const Center(
                      child: _EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No donation history yet',
                        message:
                            'This center has not received any recorded donations.',
                      ),
                    )
                  : visibleEntries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _EmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'No donations match your filters',
                                message:
                                    'Try a different search term or date range.',
                              ),
                              if (hasFilters)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: TextButton.icon(
                                    onPressed: _clearHistoryFilters,
                                    icon: const Icon(Icons.clear_all_rounded),
                                    label: const Text('Clear filters'),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : _buildHistoryTable(visibleEntries),
        ),
      ],
    );
  }

  void _clearHistoryFilters() {
    _historySearchController.clear();
    setState(() {
      _historySearch = '';
      _historyRange = _HistoryDateRange.allTime;
    });
  }

  Widget _buildHistoryFilters() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _historySearchController,
            onChanged: (value) => setState(() => _historySearch = value),
            decoration: _inputDecoration(
              'Search donor, email, or donation ID',
              Icons.search_rounded,
            ).copyWith(
              suffixIcon: _historySearch.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _historySearchController.clear();
                        setState(() => _historySearch = '');
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<_HistoryDateRange>(
            dropdownColor: AppTheme.surface,
            elevation: 2,
            borderRadius: BorderRadius.circular(AppTheme.menuRadius),
            icon: const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: AppTheme.iconMuted,
            ),
            initialValue: _historyRange,
            isExpanded: true,
            decoration:
                _inputDecoration('Date Range', Icons.date_range_rounded),
            items: _HistoryDateRange.values
                .map(
                  (range) => DropdownMenuItem<_HistoryDateRange>(
                    value: range,
                    child: Text(
                      range.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _historyRange = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTable(List<CenterDonationHistoryEntry> entries) {
    const columnWidths = {
      0: FlexColumnWidth(1.2),
      1: FlexColumnWidth(1.3),
      2: FlexColumnWidth(1.7),
      3: FlexColumnWidth(1.1),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header stays fixed above the scrollable body below it, so the
        // column labels never scroll out of view while browsing records.
        Table(
          columnWidths: columnWidths,
          children: const [
            TableRow(
              decoration: BoxDecoration(color: Color(0xFFF4F9FC)),
              children: [
                _AuditHeaderCell('Date'),
                _AuditHeaderCell('Amount'),
                _AuditHeaderCell('Allocation'),
                _AuditHeaderCell('Status'),
              ],
            ),
          ],
        ),
        Expanded(
          child: Scrollbar(
            thickness: 4,
            radius: const Radius.circular(8),
            child: SingleChildScrollView(
              child: Table(
                columnWidths: columnWidths,
                border: const TableBorder(
                  horizontalInside: BorderSide(color: Color(0xFFEDF2F6), width: 1),
                ),
                children: entries.map((entry) {
                  final statusColor = _historyStatusColor(entry.status);

                  return TableRow(
                    children: [
                      _AuditBodyCell(
                        '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}-${entry.date.day.toString().padLeft(2, '0')}',
                      ),
                      _AuditBodyCell(
                        '₱${entry.amount.toStringAsFixed(2)}',
                        isBold: true,
                        color: _primary,
                      ),
                      _AuditBodyCell(entry.allocationLabel),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(24),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              entry.statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Overall Donation History (Step 3, read-only, all centers) --------

  Widget _buildOverallHistory() {
    final isLoading = _overallCenterId == null ? _isLoading : _isLoadingOverall;
    final hasSourceData = _overallCenterId == null
        ? _donations.isNotEmpty
        : _overallCenterEntries.isNotEmpty;
    final rows = _filteredOverallRows();
    final hasFilters = _overallSearch.trim().isNotEmpty ||
        _overallRange != _HistoryDateRange.allTime;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        final panelHeight =
            isMobile ? _historyPanelHeightCompact : _historyPanelHeightWide;

        return SizedBox(
          height: panelHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOverallFilters(isMobile: isMobile),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE7EFF5)),
              const SizedBox(height: 10),
              Expanded(
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                    : !hasSourceData
                        ? const Center(
                            child: _EmptyState(
                              icon: Icons.fact_check_outlined,
                              title: 'No donations recorded yet',
                              message:
                                  'Donation records will appear here once donors contribute.',
                            ),
                          )
                        : rows.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const _EmptyState(
                                      icon: Icons.search_off_rounded,
                                      title: 'No donations match your filters',
                                      message:
                                          'Try a different search term, center, or date range.',
                                    ),
                                    if (hasFilters)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: TextButton.icon(
                                          onPressed: _clearOverallFilters,
                                          icon: const Icon(Icons.clear_all_rounded),
                                          label: const Text('Clear filters'),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : _buildOverallTable(rows),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverallFilters({required bool isMobile}) {
    final centerDropdown = SizedBox(
      width: isMobile ? double.infinity : 200,
      child: DropdownButtonFormField<String?>(
        dropdownColor: AppTheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(AppTheme.menuRadius),
        icon: const Icon(
          Icons.expand_more_rounded,
          size: 18,
          color: AppTheme.iconMuted,
        ),
        // Mirrors the Center Donation History selector's existing key:
        // DropdownButtonFormField reads `initialValue` once per widget
        // identity, so without this the field would keep its old internal
        // selection after the reconciliation above cleared a closed
        // center's id -- leaving a value its items no longer contain.
        key: ValueKey(_overallCenterId),
        initialValue: _overallCenterId,
        isExpanded: true,
        decoration: _inputDecoration('Center', Icons.local_hospital_outlined),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All Centers'),
          ),
          ..._centers.map(
            (center) => DropdownMenuItem<String?>(
              value: center['id'].toString(),
              child: Text(
                center['name']?.toString() ?? 'Unnamed Center',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() => _overallCenterId = value);
          if (value != null) _loadOverallHistory(value);
        },
      ),
    );

    final searchField = TextField(
      controller: _overallSearchController,
      onChanged: (value) => setState(() => _overallSearch = value),
      decoration: _inputDecoration(
        'Search donor, email, or donation ID',
        Icons.search_rounded,
      ).copyWith(
        suffixIcon: _overallSearch.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Clear search',
                onPressed: () {
                  _overallSearchController.clear();
                  setState(() => _overallSearch = '');
                },
              ),
      ),
    );

    final rangeDropdown = SizedBox(
      width: isMobile ? double.infinity : 170,
      child: DropdownButtonFormField<_HistoryDateRange>(
        dropdownColor: AppTheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(AppTheme.menuRadius),
        icon: const Icon(
          Icons.expand_more_rounded,
          size: 18,
          color: AppTheme.iconMuted,
        ),
        initialValue: _overallRange,
        isExpanded: true,
        decoration: _inputDecoration('Date Range', Icons.date_range_rounded),
        items: _HistoryDateRange.values
            .map(
              (range) => DropdownMenuItem<_HistoryDateRange>(
                value: range,
                child: Text(range.label, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => _overallRange = value);
        },
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          centerDropdown,
          const SizedBox(height: 10),
          searchField,
          const SizedBox(height: 10),
          rangeDropdown,
        ],
      );
    }

    return Row(
      children: [
        centerDropdown,
        const SizedBox(width: 12),
        Expanded(child: searchField),
        const SizedBox(width: 12),
        rangeDropdown,
      ],
    );
  }

  Widget _buildOverallTable(List<_OverallHistoryRow> rows) {
    const columnWidths = {
      0: FlexColumnWidth(1.1),
      1: FlexColumnWidth(1.8),
      2: FlexColumnWidth(1.5),
      3: FlexColumnWidth(1.0),
      4: FlexColumnWidth(1.2),
      5: FlexColumnWidth(1.0),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header stays fixed above the scrollable body below it, matching
        // the Center Donation History table.
        Table(
          columnWidths: columnWidths,
          children: const [
            TableRow(
              decoration: BoxDecoration(color: Color(0xFFF4F9FC)),
              children: [
                _AuditHeaderCell('Date'),
                _AuditHeaderCell('Donor'),
                _AuditHeaderCell('Center'),
                _AuditHeaderCell('Amount'),
                _AuditHeaderCell('Allocation'),
                _AuditHeaderCell('Status'),
              ],
            ),
          ],
        ),
        Expanded(
          child: Scrollbar(
            thickness: 4,
            radius: const Radius.circular(8),
            child: SingleChildScrollView(
              child: Table(
                columnWidths: columnWidths,
                border: const TableBorder(
                  horizontalInside: BorderSide(color: Color(0xFFEDF2F6), width: 1),
                ),
                children: rows.map((row) {
                  final statusColor = _historyStatusColor(row.status);
                  final donorName = (row.donorName != null && row.donorName!.isNotEmpty)
                      ? row.donorName!
                      : 'Anonymous';

                  return TableRow(
                    children: [
                      _AuditBodyCell(
                        '${row.date.year}-${row.date.month.toString().padLeft(2, '0')}-${row.date.day.toString().padLeft(2, '0')}',
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              donorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF36424C),
                                fontSize: 13,
                              ),
                            ),
                            if (row.donorEmail != null && row.donorEmail!.isNotEmpty)
                              Text(
                                row.donorEmail!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF8A98A5),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _AuditBodyCell(row.centerLabel, maxLines: 2),
                      _AuditBodyCell(
                        '₱${row.amount.toStringAsFixed(2)}',
                        isBold: true,
                        color: _primary,
                      ),
                      _AuditBodyCell(row.allocationLabel),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(24),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              row.statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return AppTheme.field(
      labelText: label,
      dense: true,
      prefixIcon: Icon(icon, size: 18, color: AppTheme.blue1),
    );
  }
}

class _AuditHeaderCell extends StatelessWidget {
  final String text;

  const _AuditHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F3A55),
          fontSize: 13,
        ),
      ),
    );
  }
}

class _AuditBodyCell extends StatelessWidget {
  final String text;
  final bool isBold;
  final Color? color;
  final int maxLines;

  const _AuditBodyCell(
    this.text, {
    this.isBold = false,
    this.color,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? const Color(0xFF36424C),
          fontSize: 13,
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color accentSoft;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.accent = AppTheme.blue1,
    this.accentSoft = AppTheme.accentBlueSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: AppTheme.iconBox(accentSoft),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: AppTheme.blue3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final Color softColor;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    this.softColor = AppTheme.accentBlueSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: AppTheme.iconBox(softColor),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: AppTheme.blue3,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5EEF4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
        ],
      ),
    );
  }
}

