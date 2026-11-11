import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/payment_transaction.dart';
import '../services/donation_service.dart';
import '../theme/app_theme.dart';

/// Donations made through the GCash checkout workflow, with each one's
/// recipient allocation breakdown.
///
/// Read-only on purpose: payment status is set only by the payment workflow
/// (the payment simulator or a verified PayMongo webhook), so this section
/// offers no way to mark anything paid. Completed simulated payments are part
/// of the transaction activity but never of collected funds; each row's
/// status and payment type are in its details.
class PaymentTransactionsSection extends StatefulWidget {
  const PaymentTransactionsSection({super.key, this.loader});

  /// Defaults to [DonationService.fetchPaymentTransactions]; injectable for
  /// tests.
  final Future<List<PaymentTransaction>> Function()? loader;

  @override
  State<PaymentTransactionsSection> createState() =>
      _PaymentTransactionsSectionState();
}

class _PaymentTransactionsSectionState extends State<PaymentTransactionsSection> {
  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy · h:mm a');
  static final DateFormat _dayFormat = DateFormat('MMM d, yyyy');

  List<PaymentTransaction> _all = const [];
  bool _isLoading = true;
  String? _error;

  DateTimeRange? _range;
  String? _mode;
  String? _status;
  String? _environment;
  String? _clinicId;
  final TextEditingController _search = TextEditingController();

  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final loader = widget.loader ?? DonationService().fetchPaymentTransactions;
      final rows = await loader();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _all = rows;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      debugPrint('Failed to load payment transactions: $error');
      setState(() {
        _error = 'Transactions could not be loaded. Check the connection and try again.';
        _isLoading = false;
      });
    }
  }

  PaymentTransactionFilter get _filter => PaymentTransactionFilter(
        from: _range?.start,
        to: _range?.end,
        mode: _mode,
        paymentStatus: _status,
        environment: _environment,
        clinicId: _clinicId,
        query: _search.text,
      );

  List<PaymentTransaction> get _visible =>
      _all.where(_filter.matches).toList();

  /// Every centre that appears in any allocation, for the centre filter.
  List<MapEntry<String, String>> get _centers {
    final byId = <String, String>{};
    for (final t in _all) {
      for (final a in t.allocations) {
        byId.putIfAbsent(a.clinicId, () => a.clinicName);
      }
    }
    final list = byId.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return list;
  }

  bool get _hasFilters =>
      _range != null || _mode != null || _status != null ||
      _environment != null || _clinicId != null || _search.text.trim().isNotEmpty;

  // ------------------------------------------------------------- widgets

  Widget _summaryTile({
    required Key key,
    required String label,
    required String value,
    required String caption,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      key: key,
      width: 250,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: AppTheme.blue3, fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(caption, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required Map<T, String> options,
    required ValueChanged<T?> onChanged,
    double width = 190,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T?>(
        key: ValueKey('tx-$label-$value'),
        initialValue: value,
        isExpanded: true,
        dropdownColor: AppTheme.surface,
        style: AppTheme.fieldTextStyle,
        decoration: AppTheme.field(labelText: label, dense: true),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text('All')),
          for (final entry in options.entries)
            DropdownMenuItem<T?>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 250,
          child: TextField(
            key: const ValueKey('tx-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: AppTheme.fieldTextStyle,
            decoration: AppTheme.field(labelText: 'Search reference, donor or center', dense: true).copyWith(
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range_rounded, size: 18),
          label: Text(_range == null
              ? 'Any date'
              : '${_dayFormat.format(_range!.start)} – ${_dayFormat.format(_range!.end)}'),
        ),
        _dropdown<String>(
          label: 'Donation mode',
          value: _mode,
          options: const {
            'specific_center': 'Specific Center',
            'random_center': 'Random Center',
            'equal_distribution': 'Donate to All',
          },
          onChanged: (v) => setState(() => _mode = v),
        ),
        _dropdown<String>(
          label: 'Status',
          value: _status,
          options: const {
            'pending': 'Pending',
            'processing': 'Processing',
            'simulated_paid': 'Completed (simulated)',
            'paid': 'Paid',
            'failed': 'Failed',
            'cancelled': 'Cancelled',
          },
          onChanged: (v) => setState(() => _status = v),
        ),
        _dropdown<String>(
          label: 'Payment type',
          value: _environment,
          options: const {'sandbox': 'Simulated', 'production': 'Live'},
          onChanged: (v) => setState(() => _environment = v),
          width: 160,
        ),
        _dropdown<String>(
          label: 'Recipient center',
          value: _clinicId,
          options: {for (final c in _centers) c.key: c.value},
          onChanged: (v) => setState(() => _clinicId = v),
          width: 230,
        ),
        if (_hasFilters)
          TextButton(
            onPressed: () => setState(() {
              _range = null;
              _mode = null;
              _status = null;
              _environment = null;
              _clinicId = null;
              _search.clear();
            }),
            child: const Text('Clear filters'),
          ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  void _openDetails(PaymentTransaction t) {
    showDialog<void>(
      context: context,
      builder: (context) => _TransactionDetailsDialog(transaction: t),
    );
  }

  String _recipients(PaymentTransaction t) {
    if (t.allocations.isEmpty) return '--';
    if (t.allocations.length == 1) return t.allocations.first.clinicName;
    return '${t.allocations.length} centers · ${t.allocations.first.clinicName} and others';
  }

  Widget _buildTable(List<PaymentTransaction> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppTheme.surfaceTint),
        headingRowHeight: 42,
        dataRowMinHeight: 50,
        dataRowMaxHeight: 60,
        columnSpacing: 26,
        columns: const [
          DataColumn(label: Text('REFERENCE')),
          DataColumn(label: Text('DATE')),
          DataColumn(label: Text('MODE')),
          DataColumn(label: Text('AMOUNT'), numeric: true),
          DataColumn(label: Text('METHOD')),
          DataColumn(label: Text('PROVIDER')),
          DataColumn(label: Text('RECIPIENTS')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final t in rows)
            DataRow(
              cells: [
                DataCell(Text(t.reference, style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(_dateFormat.format(t.createdAt))),
                DataCell(Text(t.modeLabel)),
                DataCell(Text(formatCentavosPhp(t.amountCentavos))),
                DataCell(Text(t.paymentMethod == 'GCASH' ? 'GCash' : t.paymentMethod)),
                DataCell(Text(t.providerLabel)),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(_recipients(t), overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(
                  TextButton(
                    key: ValueKey('tx-view-${t.id}'),
                    onPressed: () => _openDetails(t),
                    child: const Text('View details'),
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
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final visible = _visible;
    final summary = PaymentTransactionSummary.of(visible);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryTile(
              key: const ValueKey('tx-tile-collected'),
              label: 'Collected funds',
              value: formatCentavosPhp(summary.collectedCentavos),
              caption: 'Confirmed live payments only',
              icon: Icons.account_balance_wallet_rounded,
              color: AppTheme.accentGreen,
            ),
            _summaryTile(
              key: const ValueKey('tx-tile-activity'),
              label: 'Checkout transactions',
              value: '${summary.count}',
              caption: '${summary.completedCount} completed · ${formatCentavosPhp(summary.completedCentavos)}'
                  '${summary.simulatedCompletedCount > 0 ? ' (${summary.simulatedCompletedCount} simulated, not collected)' : ''}',
              icon: Icons.receipt_long_rounded,
              color: AppTheme.blue1,
            ),
            _summaryTile(
              key: const ValueKey('tx-tile-open'),
              label: 'Awaiting payment',
              value: '${summary.openCount}',
              caption: 'Pending or processing',
              icon: Icons.hourglass_top_rounded,
              color: AppTheme.accentOrange,
            ),
            _summaryTile(
              key: const ValueKey('tx-tile-closed'),
              label: 'Failed or cancelled',
              value: '${summary.failedOrCancelledCount}',
              caption: 'Not counted as donations',
              icon: Icons.block_rounded,
              color: AppTheme.danger,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          key: ValueKey('tx-simulated-note'),
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.textMuted),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Simulated payments move no money and are never included in collected funds.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildFilters(),
        const SizedBox(height: 10),
        Text(
          '${visible.length} of ${_all.length} ${_all.length == 1 ? 'transaction' : 'transactions'}',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _all.isEmpty
                    ? 'No GCash checkout transactions yet.'
                    : 'No transactions match these filters.',
                style: const TextStyle(color: AppTheme.textMuted),
              ),
            ),
          )
        else
          _buildTable(visible),
      ],
    );
  }
}

class _TransactionDetailsDialog extends StatelessWidget {
  const _TransactionDetailsDialog({required this.transaction});

  final PaymentTransaction transaction;

  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy · h:mm:ss a');

  Widget _row(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget _text(String value) =>
      Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5));

  Widget _statusChip(PaymentTransaction t) {
    final (Color fg, Color bg) = switch (t.paymentStatus) {
      'paid' when !t.isSandbox => (AppTheme.accentGreen, AppTheme.accentGreenSoft),
      'paid' || 'simulated_paid' => (AppTheme.blue1, AppTheme.accentBlueSoft),
      'failed' || 'cancelled' => (AppTheme.danger, AppTheme.dangerSoft),
      _ => (AppTheme.accentOrange, AppTheme.accentOrangeSoft),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('tx-detail-status'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(t.paymentStatusLabel, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final matches = t.allocatedCentavos == t.amountCentavos;

    return AlertDialog(
      title: Text('Donation ${t.reference}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Status', _statusChip(t)),
              _row('Date', _text(_dateFormat.format(t.createdAt))),
              _row('Donor', _text(t.donorLabel ?? '--')),
              _row('Donation mode', _text(t.modeLabel)),
              _row('Total amount', _text(formatCentavosPhp(t.amountCentavos))),
              _row('Payment method', _text(t.paymentMethod == 'GCASH' ? 'GCash' : t.paymentMethod)),
              _row('Provider', _text(t.providerLabel)),
              _row('Payment type', _text(t.paymentTypeLabel)),
              if (t.confirmedAt != null)
                _row(t.isSimulated ? 'Completed at' : 'Confirmed at',
                    _text(_dateFormat.format(t.confirmedAt!))),
              if (t.statusReason != null) _row('Note', _text(t.statusReason!)),
              const SizedBox(height: 14),
              Text(
                'Recipient allocation (${t.allocations.length} '
                '${t.allocations.length == 1 ? 'center' : 'centers'})',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.blue3),
              ),
              const SizedBox(height: 8),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: IntrinsicColumnWidth(),
                  2: FlexColumnWidth(3),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: AppTheme.surfaceTint),
                    children: [
                      Padding(padding: EdgeInsets.all(8), child: Text('CENTER', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                      Padding(padding: EdgeInsets.all(8), child: Text('AMOUNT', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                      Padding(padding: EdgeInsets.all(8), child: Text('ALLOCATION STATUS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                    ],
                  ),
                  for (final a in t.allocations)
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text(a.clinicName)),
                        Padding(padding: const EdgeInsets.all(8), child: Text(formatCentavosPhp(a.amountCentavos))),
                        Padding(padding: const EdgeInsets.all(8), child: Text(a.statusLabel, style: const TextStyle(fontSize: 12.5))),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Total allocated: ${formatCentavosPhp(t.allocatedCentavos)}'
                '${matches ? ' (matches donation total)' : ' — DOES NOT MATCH donation total'}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: matches ? AppTheme.accentGreen : AppTheme.danger,
                ),
              ),
              if (t.isSandbox) ...[
                const SizedBox(height: 10),
                const Text(
                  'Simulated payment: these amounts show the intended distribution. No funds were transferred.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
