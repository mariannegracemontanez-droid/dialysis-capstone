import 'package:flutter/material.dart';
import '../models/center_donation_history_entry.dart';
import '../models/donation_history_status.dart';
import '../models/donation_record.dart';
import 'package:super_admin_app/services/donation_service.dart';
import '../theme/app_theme.dart';
import '../utils/donation_history_export.dart';
import '../utils/file_download.dart';
import '../widgets/payment_transactions_section.dart';
import '../widgets/purchase_logs_section.dart';
import '../widgets/super_admin_notice.dart';

/// Which history section an export was started from.
enum _ExportSection { overallHistory }

/// Preset date windows for the donation history filter. Applied
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

  /// Checkout reference / outcome / environment (null for older donations).
  final String? reference;
  final String? paymentStatus;
  final String? paymentEnvironment;

  _OverallHistoryRow({
    required this.donationId,
    required this.amount,
    required this.allocationType,
    required this.status,
    required this.date,
    required this.centerLabel,
    this.donorName,
    this.donorEmail,
    this.reference,
    this.paymentStatus,
    this.paymentEnvironment,
  });

  DonationHistoryTone get tone => donationHistoryTone(
        status: status,
        paymentStatus: paymentStatus,
        paymentEnvironment: paymentEnvironment,
      );

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

  /// Same labels as the Donation Transactions section (see
  /// donation_history_status.dart).
  String get statusLabel => donationHistoryStatusLabel(
        status: status,
        paymentStatus: paymentStatus,
        paymentEnvironment: paymentEnvironment,
      );
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

  // Overall Donation History section (read-only, all centers). "All
  // Centers" (null) reads straight from _donations (already loaded); picking
  // one center switches to _overallCenterEntries, fetched via
  // fetchCenterDonationHistory.
  String? _overallCenterId;
  List<CenterDonationHistoryEntry> _overallCenterEntries = [];
  bool _isLoadingOverall = false;
  final TextEditingController _overallSearchController = TextEditingController();
  String _overallSearch = '';
  _HistoryDateRange _overallRange = _HistoryDateRange.allTime;

  // Donation history export (PDF / Excel). One export at a time across both
  // sections, so a double click cannot start a second download.
  _ExportSection? _exportingSection;

  static const Color _primary = Color(0xFF0F719F);
  static const Color _bg = Color(0xFFF3F7FA);
  static const Color _success = Color(0xFF2E7D32);
  static const Color _danger = Color(0xFFDE4D4D);
  static const Color _warning = Color(0xFFFB8B3C);

  // Center Donation History panel: fixed-but-responsive heights so the
  // section reads as a bounded dashboard card (sidebar + history both
  // scroll internally) instead of growing with the record count.
  static const double _historyPanelHeightWide = 500;
  static const double _historyPanelHeightCompact = 440;
  static const double _mobileBreakpoint = 640;

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

        // Received (verified) donations only -- the list now also holds
        // Donation-app checkouts, and a simulated payment is never received.
        _verifiedCount = donations.where((d) => d.isReceived).length;

        // Reconcile the Overall Donation History selector. Now that closed
        // centers are filtered out of this list, a selection made before a
        // center was closed can point at an id the dropdown no longer
        // offers -- and its items must contain the selected value exactly
        // once.
        //
        // Reset goes to null, not to centers.first: null is this dropdown's
        // own "All Centers" option, so it is always a valid item, it is this
        // section's normal default, and it avoids silently switching the
        // Super Admin onto an unrelated center's records. A null selection is
        // therefore left exactly as it is.
        final overallCenterId = _overallCenterId;
        if (overallCenterId != null &&
            !centers.any((c) => c['id'].toString() == overallCenterId)) {
          _overallCenterId = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      SuperAdminNotice.error(context, 'Failed to load donations: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Loads a single center's donations for the Overall Donation History
  /// section when it is narrowed from "All Centers" to one center.
  Future<void> _loadOverallHistory(String clinicId) async {
    if (mounted) {
      setState(() => _isLoadingOverall = true);
    }

    try {
      final entries = await _service.fetchCenterDonationHistory(clinicId);
      // A response for a center that is no longer selected (the Super Admin
      // switched again while it was in flight) must not overwrite the rows.
      if (!mounted || clinicId != _overallCenterId) return;
      setState(() => _overallCenterEntries = entries);
    } catch (error) {
      if (!mounted) return;
      SuperAdminNotice.error(
        context,
        'Failed to load overall donation history: $error',
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
                  const _SectionCard(
                    title: 'Donation Transactions (GCash Checkout)',
                    subtitle:
                        'Every GCash checkout with its recipient allocation breakdown. Open a transaction for its status, payment type and allocation.',
                    icon: Icons.receipt_long_outlined,
                    accent: AppTheme.accentBlue,
                    accentSoft: AppTheme.accentBlueSoft,
                    child: PaymentTransactionsSection(),
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
                  const SizedBox(height: AppTheme.gapLg),
                  const _SectionCard(
                    title: 'Center Purchase Logs',
                    subtitle:
                        'Purchases recorded by each center in the Admin Panel, updated live.',
                    icon: Icons.shopping_bag_outlined,
                    accent: AppTheme.accentOrange,
                    accentSoft: AppTheme.accentOrangeSoft,
                    child: PurchaseLogsSection(),
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

  Color _historyStatusColor(DonationHistoryTone tone) {
    switch (tone) {
      case DonationHistoryTone.received:
        return _success;
      case DonationHistoryTone.negative:
        return _danger;
      case DonationHistoryTone.simulated:
        return _primary;
      case DonationHistoryTone.pending:
        return _warning;
    }
  }

  /// Earliest date a [range] keeps, or null for All Time. Shared by both
  /// history tables and the export so they filter identically.
  static DateTime? _rangeCutoff(_HistoryDateRange range) {
    if (range == _HistoryDateRange.thisYear) {
      return DateTime(DateTime.now().year);
    }
    if (range.days != null) {
      return DateTime.now().subtract(Duration(days: range.days!));
    }
    return null;
  }

  /// Case-insensitive substring search across [fields]; an empty [query]
  /// matches everything.
  static bool _matchesSearch(String query, List<String?> fields) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fields.map((f) => f ?? '').join(' ').toLowerCase().contains(q);
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
            reference: d.reference,
            paymentStatus: d.paymentStatus,
            paymentEnvironment: d.paymentEnvironment,
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
            reference: e.reference,
            paymentStatus: e.paymentStatus,
            paymentEnvironment: e.paymentEnvironment,
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

    final cutoff = _rangeCutoff(_overallRange);

    return rows.where((row) {
      if (cutoff != null && row.date.isBefore(cutoff)) return false;
      return _matchesSearch(_overallSearch, [
        row.reference,
        row.donorName,
        row.donorEmail,
        row.donationId,
        row.centerLabel,
      ]);
    }).toList();
  }

  void _clearOverallFilters() {
    _overallSearchController.clear();
    setState(() {
      _overallSearch = '';
      _overallRange = _HistoryDateRange.allTime;
    });
  }

  // ---- Donation history export (PDF / Excel) ----------------------------
  //
  // The export matches the Admin Dashboard, not the on-screen table: it
  // contains only donations a center has actually RECEIVED -- the records
  // behind each center's "Donation Funds" total -- fetched through
  // DonationService.fetchReceivedDonations. The section's current center
  // scope, search and date range are then applied with the same filter
  // helpers the tables use.

  List<String> _exportFilterNotes(_HistoryDateRange range, String search) {
    final query = search.trim();
    return [
      if (range != _HistoryDateRange.allTime) 'Date range: ${range.label}',
      if (query.isNotEmpty) 'Search: "$query"',
    ];
  }

  void _notifyNothingToExport({
    required bool hasSourceData,
    bool forCenter = false,
  }) {
    SuperAdminNotice.info(
      context,
      !hasSourceData
          ? (forCenter
              ? 'No donation history available for this center.'
              : 'No donation history available.')
          : 'No received donations match the current search and date '
              'filters, so there is nothing to export. Clear the filters to '
              'export the full history.',
      title: 'Nothing to export',
    );
  }

  /// What the section is currently scoped to. A null clinicId means All
  /// Centers.
  ({
    String? clinicId,
    String? centerName,
    _HistoryDateRange range,
    String search,
  })? _exportScope(_ExportSection section) {
    final String? clinicId = _overallCenterId;
    final String? centerName = _selectedOverallCenter?['name']?.toString();
    final _HistoryDateRange range = _overallRange;
    final String search = _overallSearch;

    // A selected center must resolve to its name: the Admin Dashboard
    // matches manual distributions by center name, so without it the export
    // could not match the dashboard.
    if (clinicId != null && centerName == null) return null;

    return (
      clinicId: clinicId,
      centerName: clinicId == null ? null : centerName,
      range: range,
      search: search,
    );
  }

  Future<void> _exportHistory(
    _ExportSection section,
    DonationExportFormat format,
  ) async {
    // Explicit guard on top of the disabled button: the button only greys
    // out once the page rebuilds, so a fast second pick could still land.
    if (_exportingSection != null) return;

    final scope = _exportScope(section);
    if (scope == null) return;
    final forCenter = scope.clinicId != null;

    setState(() => _exportingSection = section);

    try {
      final received = await _service.fetchReceivedDonations(
        clinicId: scope.clinicId,
        centerName: scope.centerName,
      );
      if (!mounted) return;

      if (received.isEmpty) {
        _notifyNothingToExport(hasSourceData: false, forCenter: forCenter);
        return;
      }

      final cutoff = _rangeCutoff(scope.range);
      final visible = received.where((record) {
        if (cutoff != null && record.date.isBefore(cutoff)) return false;
        return _matchesSearch(scope.search, [
          record.donorLabel,
          record.isAnonymous ? null : record.donorEmail,
          record.sourceId,
          record.centerName,
        ]);
      }).toList();

      if (visible.isEmpty) {
        _notifyNothingToExport(hasSourceData: true);
        return;
      }

      final report = DonationHistoryReport(
        scopeLabel: forCenter ? scope.centerName! : 'All Centers',
        isAllCenters: !forCenter,
        filters: _exportFilterNotes(scope.range, scope.search),
        rows: visible.map(DonationExportRow.fromReceived).toList(),
      );

      // One frame so the button's spinner is painted before the (CPU-bound)
      // file generation starts.
      await Future<void>.delayed(const Duration(milliseconds: 16));

      final bytes = switch (format) {
        DonationExportFormat.pdf =>
          await DonationHistoryExporter.buildPdf(report),
        DonationExportFormat.excel => DonationHistoryExporter.buildXlsx(report),
      };

      downloadBytes(
        fileName: report.fileName(format),
        bytes: bytes,
        mimeType: format.mimeType,
      );

      if (!mounted) return;
      SuperAdminNotice.success(
        context,
        'Donation history exported successfully.',
        title: 'Download started',
      );
    } catch (error) {
      debugPrint('Donation history export failed: $error');
      if (!mounted) return;
      SuperAdminNotice.error(
        context,
        error is UnsupportedError
            ? (error.message ?? 'Downloading is not available here.')
            : 'Unable to export donation history. Please try again.',
        title: 'Export failed',
      );
    } finally {
      if (mounted) setState(() => _exportingSection = null);
    }
  }

  /// Compact "Export" menu offering PDF or Excel. Disabled while the
  /// section's data is loading or any export is being generated.
  Widget _buildExportButton(
    _ExportSection section, {
    required bool dataLoading,
  }) {
    final isBusy = _exportingSection == section;
    final enabled = _exportingSection == null && !dataLoading;

    return AppMenuTheme(
      child: PopupMenuButton<DonationExportFormat>(
        enabled: enabled,
        tooltip: 'Download this donation history',
        position: PopupMenuPosition.under,
        onSelected: (format) => _exportHistory(section, format),
        itemBuilder: (context) => [
          for (final format in DonationExportFormat.values)
            PopupMenuItem<DonationExportFormat>(
              value: format,
              child: Row(
                children: [
                  Icon(
                    format == DonationExportFormat.pdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.table_chart_outlined,
                    size: 18,
                    color: AppTheme.blue1,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    format.label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.blue3,
                    ),
                  ),
                ],
              ),
            ),
        ],
        // The menu button owns the tap; the OutlinedButton is only its look.
        child: AbsorbPointer(
          child: SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: enabled ? () {} : null,
              icon: isBusy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded, size: 17),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isBusy ? 'Exporting…' : 'Export'),
                  if (!isBusy) ...[
                    const SizedBox(width: 2),
                    const Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ],
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: AppTheme.surface,
                foregroundColor: AppTheme.blue3,
                side: const BorderSide(color: AppTheme.borderStrong),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
              ),
            ),
          ),
        ),
      ),
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

    final exportButton = _buildExportButton(
      _ExportSection.overallHistory,
      dataLoading: _overallCenterId == null ? _isLoading : _isLoadingOverall,
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
          const SizedBox(height: 10),
          exportButton,
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
        const SizedBox(width: 12),
        exportButton,
      ],
    );
  }

  Widget _buildOverallTable(List<_OverallHistoryRow> rows) {
    const columnWidths = {
      0: FlexColumnWidth(1.1),
      1: FlexColumnWidth(1.4),
      2: FlexColumnWidth(1.8),
      3: FlexColumnWidth(1.5),
      4: FlexColumnWidth(1.0),
      5: FlexColumnWidth(1.2),
      6: FlexColumnWidth(1.3),
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
                _AuditHeaderCell('Reference'),
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
                  final statusColor = _historyStatusColor(row.tone);
                  final donorName = (row.donorName != null && row.donorName!.isNotEmpty)
                      ? row.donorName!
                      : 'Anonymous';

                  return TableRow(
                    children: [
                      _AuditBodyCell(
                        '${row.date.year}-${row.date.month.toString().padLeft(2, '0')}-${row.date.day.toString().padLeft(2, '0')}',
                      ),
                      _AuditBodyCell(row.reference ?? '--'),
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

