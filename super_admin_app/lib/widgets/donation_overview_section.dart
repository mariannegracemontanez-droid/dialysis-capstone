import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/donation_overview.dart';
import '../models/payment_transaction.dart' show formatCentavosPhp;
import '../services/dashboard_service.dart';
import '../theme/app_theme.dart';

/// Dashboard "Donation Overview": the donation KPIs and two monthly trends.
///
/// Collected funds (verified, real money) and simulated payments are always
/// shown as separate figures and separate series; nothing simulated is ever
/// added to a money total. Every figure comes from [DonationOverview].
class DonationOverviewSection extends StatefulWidget {
  const DonationOverviewSection({super.key, this.loader});

  /// Defaults to [DashboardService.fetchDonationOverview]; injectable for tests.
  final Future<DonationOverview> Function()? loader;

  @override
  State<DonationOverviewSection> createState() => _DonationOverviewSectionState();
}

class _DonationOverviewSectionState extends State<DonationOverviewSection> {
  static final DateFormat _month = DateFormat('MMM');
  static final DateFormat _monthYear = DateFormat('MMM yyyy');

  static const Color _collected = AppTheme.accentGreen;
  static const Color _simulated = Color(0xFF8A7BB8);
  static const Color _other = AppTheme.borderStrong;

  DonationOverview? _overview;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader ?? DashboardService().fetchDonationOverview;
      final overview = await loader();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('Donation overview failed: $error');
      setState(() {
        _error = 'Donation figures could not be loaded.';
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------ widgets

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rXl),
          border: Border.all(color: AppTheme.border),
          boxShadow: AppTheme.shadowSm,
        ),
        child: child,
      );

  Widget _kpi({
    required Key key,
    required String label,
    required String value,
    required String caption,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: const TextStyle(color: AppTheme.blue3, fontSize: 21, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 2),
                Text(caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5)),
        ],
      );

  /// One bar per month. [segments] are stacked bottom-up; [maxValue] scales
  /// the column heights. [valueLabel] is printed above each bar.
  Widget _barChart({
    required Key key,
    required List<DonationTrendPoint> points,
    required List<List<(int, Color)>> segments,
    required int maxValue,
    required String Function(int index) valueLabel,
    required String Function(int index) tooltip,
  }) {
    const chartHeight = 150.0;
    return SizedBox(
      key: key,
      height: chartHeight + 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < points.length; i++)
            Expanded(
              child: Tooltip(
                message: tooltip(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(valueLabel(i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (value, color) in segments[i].reversed)
                              if (value > 0)
                                Container(
                                  height: maxValue == 0 ? 0 : (value / maxValue * chartHeight).clamp(2.0, chartHeight),
                                  color: color,
                                ),
                          ],
                        ),
                      ),
                    ),
                    Container(height: 1, color: AppTheme.border),
                    const SizedBox(height: 6),
                    Text(_month.format(points[i].month),
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _compactPeso(int centavos) {
    final pesos = centavos / 100;
    if (pesos >= 1000000) return '₱${(pesos / 1000000).toStringAsFixed(1)}M';
    if (pesos >= 1000) return '₱${(pesos / 1000).toStringAsFixed(1)}K';
    return '₱${pesos.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Donation Overview',
                  style: TextStyle(color: AppTheme.blue3, fontSize: 17, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('Collected funds are verified donations. Simulated payments are shown as activity and are never counted as funds.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
            ],
          ),
        ),
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ],
    );

    if (_loading && _overview == null) {
      return _card(
        child: Column(children: [
          header,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
          ),
        ]),
      );
    }
    if (_error != null && _overview == null) {
      return _card(
        child: Column(children: [
          header,
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.textMuted)),
          TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
        ]),
      );
    }

    final o = _overview!;
    final trend = o.trend;
    final maxCollected = trend.fold<int>(0, (m, p) => p.collectedCentavos > m ? p.collectedCentavos : m);
    final maxCount = trend.fold<int>(0, (m, p) => p.transactions > m ? p.transactions : m);
    final range = trend.isEmpty ? '' : '${_monthYear.format(trend.first.month)} – ${_monthYear.format(trend.last.month)}';

    final kpis = [
      _kpi(
        key: const ValueKey('kpi-collected'),
        label: 'Collected funds',
        value: formatCentavosPhp(o.collectedCentavos),
        caption: '${o.collectedCount} verified ${o.collectedCount == 1 ? 'donation' : 'donations'}',
        icon: Icons.volunteer_activism_rounded,
        color: _collected,
      ),
      _kpi(
        key: const ValueKey('kpi-awaiting'),
        label: 'Awaiting verification',
        value: '${o.awaitingVerificationCount}',
        caption: '${formatCentavosPhp(o.awaitingVerificationCentavos)} not yet verified',
        icon: Icons.hourglass_top_rounded,
        color: AppTheme.accentOrange,
      ),
      _kpi(
        key: const ValueKey('kpi-checkouts'),
        label: 'Checkout activity',
        value: '${o.simulatedCompletedCount} completed',
        caption: '${formatCentavosPhp(o.simulatedCompletedCentavos)} in simulated payments · '
            '${o.openCheckoutCount} open',
        icon: Icons.shopping_cart_checkout_rounded,
        color: _simulated,
      ),
      _kpi(
        key: const ValueKey('kpi-volume'),
        label: 'Transaction volume',
        value: '${o.transactionCount}',
        caption: '${o.failedOrCancelledCount} failed or cancelled · ${o.rejectedCount} rejected',
        icon: Icons.receipt_long_rounded,
        color: AppTheme.blue1,
      ),
    ];

    final collectedChart = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Collected funds by month',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(range, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
        const SizedBox(height: 12),
        _barChart(
          key: const ValueKey('trend-collected'),
          points: trend,
          segments: [for (final p in trend) [(p.collectedCentavos, _collected)]],
          maxValue: maxCollected,
          valueLabel: (i) => trend[i].collectedCentavos == 0 ? '' : _compactPeso(trend[i].collectedCentavos),
          tooltip: (i) => '${_monthYear.format(trend[i].month)}: '
              '${formatCentavosPhp(trend[i].collectedCentavos)} from ${trend[i].collectedCount} verified',
        ),
      ],
    );

    final activityChart = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Donation transactions by month',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _legend(_collected, 'Verified'),
          _legend(_simulated, 'Simulated payment'),
          _legend(_other, 'Pending, failed or rejected'),
        ]),
        const SizedBox(height: 12),
        _barChart(
          key: const ValueKey('trend-activity'),
          points: trend,
          segments: [
            for (final p in trend)
              [(p.collectedCount, _collected), (p.simulatedCount, _simulated), (p.otherCount, _other)],
          ],
          maxValue: maxCount,
          valueLabel: (i) => trend[i].transactions == 0 ? '' : '${trend[i].transactions}',
          tooltip: (i) => '${_monthYear.format(trend[i].month)}: ${trend[i].transactions} transactions '
              '(${trend[i].collectedCount} verified, ${trend[i].simulatedCount} simulated, ${trend[i].otherCount} other)',
        ),
      ],
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final columns = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
            final width = (c.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final k in kpis) SizedBox(width: width, child: k)],
            );
          }),
          const SizedBox(height: 22),
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 760) {
              return Column(children: [collectedChart, const SizedBox(height: 22), activityChart]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: collectedChart),
                const SizedBox(width: 28),
                Expanded(child: activityChart),
              ],
            );
          }),
        ],
      ),
    );
  }
}
