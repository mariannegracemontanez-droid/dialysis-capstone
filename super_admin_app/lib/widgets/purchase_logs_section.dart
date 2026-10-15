import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/purchase_log.dart';
import '../services/donation_service.dart';
import '../theme/app_theme.dart';

/// Purchase logs recorded by centres in the Admin Panel, read live from the
/// shared `donation_purchase_logs` table.
///
/// Stays current through a realtime subscription to that table (the same
/// mechanism the Admin Panel dashboard uses for it): any insert, update or
/// delete triggers a debounced re-fetch. Each re-fetch replaces the list
/// (see purchaseLogsFromRows), so refreshes and repeated events can never
/// duplicate a log, and an edited log always shows its latest saved values.
class PurchaseLogsSection extends StatefulWidget {
  const PurchaseLogsSection({
    super.key,
    this.loader,
    this.listenForChanges = true,
  });

  /// Loads the logs. Defaults to [DonationService.fetchPurchaseLogs];
  /// injectable for tests.
  final Future<List<PurchaseLog>> Function()? loader;

  /// Whether to subscribe to realtime changes. Off in tests.
  final bool listenForChanges;

  @override
  State<PurchaseLogsSection> createState() => _PurchaseLogsSectionState();
}

class _PurchaseLogsSectionState extends State<PurchaseLogsSection> {
  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy · h:mm a');
  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  List<PurchaseLog> _logs = const [];
  bool _isLoading = true;
  String? _error;
  String? _centerFilter;

  RealtimeChannel? _channel;
  Timer? _refreshDebounce;

  /// Incremented per load so a slow, older response never overwrites a
  /// newer one.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.listenForChanges) _subscribe();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    final channel = _channel;
    if (channel != null) {
      SupabaseConfig.client.removeChannel(channel);
    }
    super.dispose();
  }

  void _subscribe() {
    try {
      _channel = SupabaseConfig.client
          .channel('super_admin_purchase_logs')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'donation_purchase_logs',
            callback: (_) => _scheduleRefresh(),
          )
          .subscribe();
    } catch (error) {
      // Live updates are a convenience; the list still loads and the
      // Refresh button still works without them.
      debugPrint('Purchase log realtime subscription failed: $error');
    }
  }

  /// Coalesces a burst of realtime events into one re-fetch.
  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load(showSpinner: false);
    });
  }

  Future<void> _load({bool showSpinner = true}) async {
    final generation = ++_loadGeneration;
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final loader = widget.loader ?? DonationService().fetchPurchaseLogs;
      final logs = await loader();
      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        _logs = logs;
        _error = null;
        _isLoading = false;
        if (_centerFilter != null &&
            !logs.any((log) => log.clinicName == _centerFilter)) {
          _centerFilter = null;
        }
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      debugPrint('Failed to load purchase logs: $error');
      setState(() {
        _error =
            'Purchase logs could not be loaded. Check the connection '
            'and try again.';
        _isLoading = false;
      });
    }
  }

  List<String> get _centerNames {
    final names = _logs
        .map((log) => log.clinicName)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  List<PurchaseLog> get _visibleLogs => _centerFilter == null
      ? _logs
      : _logs.where((log) => log.clinicName == _centerFilter).toList();

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: 'Purchase logs unavailable',
        message: error,
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );
    }

    if (_logs.isEmpty) {
      return _Message(
        icon: Icons.receipt_long_outlined,
        title: 'No purchase logs yet',
        message:
            'Purchases recorded by centers in the Admin Panel will appear '
            'here automatically.',
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      );
    }

    final visible = _visibleLogs;
    final total = visible.fold<double>(0, (sum, log) => sum + log.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                key: ValueKey('purchase-center-$_centerFilter'),
                initialValue: _centerFilter,
                isExpanded: true,
                dropdownColor: AppTheme.surface,
                decoration: InputDecoration(
                  labelText: 'Center',
                  prefixIcon: const Icon(
                    Icons.local_hospital_outlined,
                    color: AppTheme.blue1,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Centers'),
                  ),
                  for (final name in _centerNames)
                    DropdownMenuItem<String?>(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _centerFilter = value),
              ),
            ),
            Text(
              '${visible.length} ${visible.length == 1 ? 'purchase' : 'purchases'}'
              ' · ${_currency.format(total)} spent',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppTheme.surfaceTint),
            headingRowHeight: 42,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 60,
            columnSpacing: 28,
            columns: const [
              DataColumn(label: Text('DATE')),
              DataColumn(label: Text('CENTER')),
              DataColumn(label: Text('ITEM')),
              DataColumn(label: Text('AMOUNT'), numeric: true),
            ],
            rows: [
              for (final log in visible)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        log.date == null ? '--' : _dateFormat.format(log.date!),
                      ),
                    ),
                    DataCell(
                      Text(log.clinicName.isEmpty ? '--' : log.clinicName),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          log.itemName.isEmpty ? '--' : log.itemName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(_currency.format(log.amount))),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppTheme.iconMuted),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.blue3,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
