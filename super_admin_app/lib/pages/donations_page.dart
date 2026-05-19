import 'package:flutter/material.dart';
import '../models/donation_record.dart';
import '../models/donation_summary.dart';
import '../models/fund_distribution.dart';
import 'package:super_admin_app/services/donation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

int pendingCount = 0;
int verifiedCount = 0;
int rejectedCount = 0;

class DonationsPage extends StatefulWidget {
  const DonationsPage({super.key});

  @override
  State<DonationsPage> createState() => _DonationsPageState();
}

class _DonationsPageState extends State<DonationsPage> {
  final DonationService _service = DonationService();

  bool _isLoading = true;
  List<DonationRecord> _donations = [];
  List<DonationSummary> _summary = [];
  List<FundDistribution> _fundDistributions = [];
  List<Map<String, dynamic>> _centers = [];
  double _availableFunds = 0;

  Map<String, double> centerTotals = {};

  static const Color _primary = Color(0xFF0F719F);
  static const Color _dark = Color(0xFF0F3A55);
  static const Color _muted = Color(0xFF647583);
  static const Color _bg = Color(0xFFF3F7FA);
  static const Color _success = Color(0xFF2E7D32);
  static const Color _danger = Color(0xFFDE4D4D);
  static const Color _warning = Color(0xFFFB8B3C);

  String _formatCompactCurrency(double amount) {
    if (amount >= 1000000) {
      return '₱${(amount / 1000000).toStringAsFixed(amount % 1000000 == 0 ? 0 : 1)}M';
    }

    if (amount >= 1000) {
      return '₱${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}K';
    }

    return '₱${amount.toStringAsFixed(0)}';
  }

  @override
  void initState() {
    super.initState();
    _loadDonations();
  }

  Future<void> _loadDonations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final donations = await _service.fetchDonations();
      final summary = await _service.fetchDonationSummary();
      final distributions = await _service.fetchFundDistributions();
      final centers = await _service.fetchCenters();
      final totalDonations = await _service.fetchTotalDonations();
      final totalDistributed = await _service.fetchTotalDistributed();

      if (!mounted) return;

      setState(() {
        _availableFunds = totalDonations - totalDistributed;
        _donations = donations;
        pendingCount = donations.where((d) => d.status == 'pending').length;
        verifiedCount = donations.where((d) => d.status == 'verified').length;
        rejectedCount = donations.where((d) => d.status == 'rejected').length;
        _summary = summary;
        _fundDistributions = distributions;
        centerTotals.clear();

        for (final item in distributions) {
          centerTotals[item.centerName] =
              (centerTotals[item.centerName] ?? 0.0) + item.amount.toDouble();
        }

        _centers = centers;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load donations: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showDonationDialog() async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final remarksController = TextEditingController();

    Map<String, dynamic>? selectedCenter = _centers.isNotEmpty
        ? _centers.first
        : null;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _primary.withAlpha(25),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_outlined,
                                color: _primary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Distribute Funds',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: _dark,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Allocate available funds to a dialysis center.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5FAFD),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE1EEF5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.savings_outlined,
                                color: _primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Available Funds: ₱${_availableFunds.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: _dark,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          initialValue: selectedCenter,
                          items: _centers.map((center) {
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: center,
                              child: Text(center['name']),
                            );
                          }).toList(),
                          decoration: _inputDecoration(
                            'Center',
                            Icons.local_hospital_outlined,
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedCenter = value;
                            });
                          },
                          validator: (value) =>
                              value == null ? 'Select a center' : null,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          controller: amountController,
                          label: 'Amount',
                          icon: Icons.payments_outlined,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          controller: remarksController,
                          label: 'Remarks',
                          icon: Icons.notes_outlined,
                        ),
                        const SizedBox(height: 26),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }

                                      final amountText = amountController.text
                                          .trim();

                                      if (amountText.isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Enter amount'),
                                          ),
                                        );
                                        return;
                                      }

                                      double amount;
                                      try {
                                        amount = double.parse(amountText);
                                      } catch (_) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Invalid amount format',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      if (amount <= 0) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Enter a valid amount',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      if (selectedCenter == null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Select a center'),
                                          ),
                                        );
                                        return;
                                      }

                                      if (amount > _availableFunds) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Insufficient available funds',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      setDialogState(() {
                                        isSaving = true;
                                      });

                                      try {
                                        await _service.createFundDistribution(
                                          clinicId: selectedCenter!['id'],
                                          centerName: selectedCenter!['name'],
                                          amount: amount,
                                          remarks: remarksController.text
                                              .trim(),
                                        );

                                        Navigator.pop(context);
                                        await _loadDonations();

                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          this.context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Funds distributed successfully',
                                            ),
                                          ),
                                        );
                                      } catch (error) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          this.context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('Error: $error'),
                                          ),
                                        );
                                      } finally {
                                        setDialogState(() {
                                          isSaving = false;
                                        });
                                      }
                                    },
                              icon: isSaving
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(
                                isSaving ? 'Saving...' : 'Distribute',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
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
            );
          },
        );
      },
    );

    amountController.dispose();
    remarksController.dispose();
  }

  Future<void> _deleteDonation(DonationRecord donation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete donation record'),
        content: Text(
          'Delete donation of ₱${donation.amount.toStringAsFixed(0)} from ${donation.donorName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _service.deleteDonation(donation.id);
    await _loadDonations();
  }

  @override
  Widget build(BuildContext context) {
    final totalDonations = _summary.fold<double>(
      0,
      (sum, item) => sum + item.totalAmount,
    );

    final totalRecords = _donations.length;
    final distributionCount = _fundDistributions.length;
    final totalDistributed = totalDonations - _availableFunds;
    final hasPieData = pendingCount + verifiedCount + rejectedCount > 0;

    final double maxY = centerTotals.isNotEmpty
        ? centerTotals.values.reduce((a, b) => a > b ? a : b) + 1000.0
        : 1000.0;

    return Container(
      color: _bg,
      child: RefreshIndicator(
        onRefresh: _loadDonations,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(28),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1150;
              final statWidth = isWide
                  ? (constraints.maxWidth - 48) / 4
                  : constraints.maxWidth >= 760
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: statWidth,
                        child: _InfoCard(
                          icon: Icons.volunteer_activism_outlined,
                          label: 'Total Donations',
                          value: _formatCompactCurrency(totalDonations),
                          subtitle: '$totalRecords records collected',
                          color: _primary,
                        ),
                      ),
                      SizedBox(
                        width: statWidth,
                        child: _InfoCard(
                          icon: Icons.account_balance_outlined,
                          label: 'Available Funds',
                          value: _formatCompactCurrency(_availableFunds),
                          subtitle: 'Ready for distribution',
                          color: _success,
                        ),
                      ),
                      SizedBox(
                        width: statWidth,
                        child: _InfoCard(
                          icon: Icons.send_time_extension_outlined,
                          label: 'Distributed',
                          value: _formatCompactCurrency(totalDistributed),
                          subtitle: '$distributionCount distribution logs',
                          color: _warning,
                        ),
                      ),
                      SizedBox(
                        width: statWidth,
                        child: _InfoCard(
                          icon: Icons.pending_actions_outlined,
                          label: 'Pending Review',
                          value: pendingCount.toString(),
                          subtitle: 'Need admin action',
                          color: _danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      SizedBox(
                        width: isWide
                            ? (constraints.maxWidth - 20) * 0.42
                            : constraints.maxWidth,
                        child: _SectionCard(
                          title: 'Donation Status Overview',
                          subtitle:
                              'Monitor pending, approved, and rejected donation submissions.',
                          icon: Icons.donut_large_rounded,
                          child: SizedBox(
                            height: 330,
                            child: hasPieData
                                ? Column(
                                    children: [
                                      Expanded(
                                        child: PieChart(
                                          PieChartData(
                                            sectionsSpace: 8,
                                            centerSpaceRadius: 58,
                                            borderData: FlBorderData(
                                              show: false,
                                            ),
                                            sections: [
                                              PieChartSectionData(
                                                value: pendingCount.toDouble(),
                                                title: pendingCount == 0
                                                    ? ''
                                                    : 'Pending',
                                                color: _warning,
                                                radius: 76,
                                                titleStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              PieChartSectionData(
                                                value: verifiedCount.toDouble(),
                                                title: verifiedCount == 0
                                                    ? ''
                                                    : 'Approved',
                                                color: _primary,
                                                radius: 76,
                                                titleStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              PieChartSectionData(
                                                value: rejectedCount.toDouble(),
                                                title: rejectedCount == 0
                                                    ? ''
                                                    : 'Rejected',
                                                color: _danger,
                                                radius: 76,
                                                titleStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        alignment: WrapAlignment.center,
                                        children: [
                                          _LegendChip(
                                            label: 'Pending',
                                            color: _warning,
                                            value: pendingCount.toString(),
                                          ),
                                          _LegendChip(
                                            label: 'Approved',
                                            color: _primary,
                                            value: verifiedCount.toString(),
                                          ),
                                          _LegendChip(
                                            label: 'Rejected',
                                            color: _danger,
                                            value: rejectedCount.toString(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : const _EmptyState(
                                    icon: Icons.pie_chart_outline_rounded,
                                    title: 'No analytics available',
                                    message:
                                        'Donation status data will appear here once records are added.',
                                  ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isWide
                            ? (constraints.maxWidth - 20) * 0.58
                            : constraints.maxWidth,
                        child: _SectionCard(
                          title: 'Distribution Per Center',
                          subtitle:
                              'Compare how much funding each center has received.',
                          icon: Icons.bar_chart_rounded,
                          child: SizedBox(
                            height: 330,
                            child: centerTotals.isEmpty
                                ? const _EmptyState(
                                    icon: Icons.analytics_outlined,
                                    title: 'No distribution data',
                                    message:
                                        'Distributed funds will be visualized here.',
                                  )
                                : BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY: maxY,
                                      barTouchData: BarTouchData(enabled: true),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        horizontalInterval: maxY / 4,
                                        getDrawingHorizontalLine: (value) =>
                                            const FlLine(
                                              color: Color(0xFFE8EEF3),
                                              strokeWidth: 1,
                                            ),
                                      ),
                                      titlesData: FlTitlesData(
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            interval: maxY / 4,
                                            reservedSize: 48,
                                            getTitlesWidget: (value, meta) {
                                              return Text(
                                                '₱${value.toInt()}',
                                                style: const TextStyle(
                                                  color: Color(0xFF7F8B9B),
                                                  fontSize: 11,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 44,
                                            getTitlesWidget: (value, meta) {
                                              final keys = centerTotals.keys
                                                  .toList();

                                              if (value.toInt() >=
                                                  keys.length) {
                                                return const SizedBox();
                                              }

                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 10,
                                                ),
                                                child: SizedBox(
                                                  width: 86,
                                                  child: Text(
                                                    keys[value.toInt()],
                                                    maxLines: 2,
                                                    textAlign: TextAlign.center,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFF7F8B9B),
                                                      fontSize: 11,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      barGroups: centerTotals.entries
                                          .toList()
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                            final index = entry.key;
                                            final item = entry.value;

                                            return BarChartGroupData(
                                              x: index,
                                              barRods: [
                                                BarChartRodData(
                                                  toY: item.value.toDouble(),
                                                  width: 30,
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  color: _primary,
                                                  backDrawRodData:
                                                      BackgroundBarChartRodData(
                                                        show: true,
                                                        toY: maxY,
                                                        color: const Color(
                                                          0xFFEFF6FA,
                                                        ),
                                                      ),
                                                ),
                                              ],
                                            );
                                          })
                                          .toList(),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  _SectionCard(
                    title: 'Donation Records',
                    subtitle:
                        'Review donation submissions, verify valid receipts, reject invalid entries, or delete duplicate records.',
                    icon: Icons.receipt_long_outlined,
                    trailing: _isLoading
                        ? null
                        : TextButton.icon(
                            onPressed: _loadDonations,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Refresh'),
                          ),
                    child: _buildDonationRecords(),
                  ),
                  const SizedBox(height: 26),
                  _SectionCard(
                    title: 'Distribution Audit Log',
                    subtitle:
                        'Track fund allocation history, remarks, dates, and distribution status.',
                    icon: Icons.history_rounded,
                    child: _buildAuditLog(),
                  ),
                ],
              );
            },
          ),
        ),
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
            color: _primary.withAlpha(45),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withAlpha(40)),
                      ),
                      child: const Text(
                        'Donation Management',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Distribute Donation Funds',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Allocate donations to centers, review submissions, and keep every transaction transparent.',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withAlpha(215),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCompact) const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _showDonationDialog,
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('Distribute Funds'),
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
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDonationRecords() {
    if (_isLoading) {
      return const _LoadingBlock();
    }

    if (_donations.isEmpty) {
      return const _EmptyState(
        icon: Icons.volunteer_activism_outlined,
        title: 'No donations yet',
        message:
            'Donation records will appear here once donors submit their contributions.',
      );
    }

    final pending = _donations.where((d) => d.status == 'pending').toList();
    final approved = _donations.where((d) => d.status == 'verified').toList();
    final rejected = _donations.where((d) => d.status == 'rejected').toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 950;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DonationGroup(
              title: 'Pending Donations',
              count: pending.length,
              color: _warning,
              donations: pending,
              onDelete: _deleteDonation,
              onRefresh: _loadDonations,
              isScrollable: false,
            ),
            const SizedBox(height: 22),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DonationGroup(
                      title: 'Approved Donations',
                      count: approved.length,
                      color: _success,
                      donations: approved,
                      onDelete: _deleteDonation,
                      onRefresh: _loadDonations,
                      isScrollable: true,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _DonationGroup(
                      title: 'Rejected Donations',
                      count: rejected.length,
                      color: _danger,
                      donations: rejected,
                      onDelete: _deleteDonation,
                      onRefresh: _loadDonations,
                      isScrollable: true,
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _DonationGroup(
                    title: 'Approved Donations',
                    count: approved.length,
                    color: _success,
                    donations: approved,
                    onDelete: _deleteDonation,
                    onRefresh: _loadDonations,
                    isScrollable: true,
                  ),
                  const SizedBox(height: 22),
                  _DonationGroup(
                    title: 'Rejected Donations',
                    count: rejected.length,
                    color: _danger,
                    donations: rejected,
                    onDelete: _deleteDonation,
                    onRefresh: _loadDonations,
                    isScrollable: true,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildAuditLog() {
    if (_isLoading) {
      return const _LoadingBlock();
    }

    if (_fundDistributions.isEmpty) {
      return const _EmptyState(
        icon: Icons.manage_search_rounded,
        title: 'No audit entries',
        message: 'Fund distribution logs will appear here.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: double.infinity,
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(1.1),
              1: FlexColumnWidth(2.2),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(3.0),
              4: FlexColumnWidth(1.2),
            },
            border: const TableBorder(
              horizontalInside: BorderSide(color: Color(0xFFD8DEE6), width: 1),
            ),
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F9FC),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                children: const [
                  _AuditHeaderCell('Date'),
                  _AuditHeaderCell('Center'),
                  _AuditHeaderCell('Amount'),
                  _AuditHeaderCell('Remarks'),
                  _AuditHeaderCell('Status'),
                ],
              ),
              ..._fundDistributions.map((entry) {
                return TableRow(
                  children: [
                    _AuditBodyCell(
                      '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')}',
                    ),
                    _AuditBodyCell(entry.centerName, isBold: true),
                    _AuditBodyCell(
                      '₱${entry.amount.toStringAsFixed(0)}',
                      isBold: true,
                      color: _primary,
                    ),
                    _AuditBodyCell(
                      entry.remarks.isEmpty ? 'No remarks' : entry.remarks,
                      maxLines: 2,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _primary.withAlpha(22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            entry.status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _primary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: (value) =>
          (value == null || value.isEmpty) ? 'This field is required' : null,
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _primary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFDCEAF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primary, width: 1.6),
      ),
      filled: true,
      fillColor: const Color(0xFFF6FBFF),
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

class _DonationGroup extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final List<DonationRecord> donations;
  final Future<void> Function(DonationRecord donation) onDelete;
  final Future<void> Function() onRefresh;
  final bool isScrollable;

  const _DonationGroup({
    required this.title,
    required this.count,
    required this.color,
    required this.donations,
    required this.onDelete,
    required this.onRefresh,
    required this.isScrollable,
  });

  @override
  Widget build(BuildContext context) {
    const double cardHeight = 190;
    const double gap = 14;
    const double scrollHeight = (cardHeight * 5) + (gap * 4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withAlpha(24),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (donations.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5EEF4)),
            ),
            child: const Text(
              'No records in this section.',
              style: TextStyle(color: Color(0xFF647583)),
            ),
          )
        else
          SizedBox(
            height: isScrollable ? scrollHeight : null,
            child: ListView.separated(
              shrinkWrap: !isScrollable,
              physics: isScrollable
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: donations.length,
              separatorBuilder: (_, _) => const SizedBox(height: gap),
              itemBuilder: (context, index) {
                final donation = donations[index];

                return SizedBox(
                  height: isScrollable ? cardHeight : null,
                  child: _DonationRow(
                    donation: donation,
                    compactActions: isScrollable,
                    onDelete: () => onDelete(donation),
                    onRefresh: onRefresh,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE7EFF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF8FC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF0F719F)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F3A55),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF647583),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _LegendChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF324A5F),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F3A55),
            ),
          ),
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

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE7EFF5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 22,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withAlpha(24),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF647583),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F3A55),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

class _DonationRow extends StatelessWidget {
  final DonationRecord donation;
  final VoidCallback onDelete;
  final Future<void> Function() onRefresh;
  final bool compactActions;

  const _DonationRow({
    required this.donation,
    required this.onDelete,
    required this.onRefresh,
    this.compactActions = false,
  });

  Color get statusColor {
    if (donation.status == 'verified') return const Color(0xFF2E7D32);
    if (donation.status == 'rejected') return const Color(0xFFDE4D4D);
    return const Color(0xFFFB8B3C);
  }

  String get statusLabel {
    switch (donation.status) {
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  bool get isLocked {
    return donation.status == 'verified' || donation.status == 'rejected';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EFF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 720;

          final details = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: statusColor.withAlpha(24),
                child: Icon(Icons.person_outline_rounded, color: statusColor),
              ),
              const SizedBox(width: 14),
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
                          donation.donorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F3A55),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(24),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        _MiniInfo(
                          icon: Icons.payments_outlined,
                          text: '₱${donation.amount.toStringAsFixed(0)}',
                          isStrong: true,
                        ),
                        _MiniInfo(
                          icon: Icons.credit_card_rounded,
                          text: donation.paymentMethod ?? 'No payment method',
                        ),
                      ],
                    ),
                    if (donation.proofUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.network(donation.proofUrl!),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF8FC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.image_outlined,
                                  size: 17,
                                  color: Color(0xFF0F719F),
                                ),
                                SizedBox(width: 7),
                                Text(
                                  'View Receipt',
                                  style: TextStyle(
                                    color: Color(0xFF0F719F),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );

          Widget actionButtons({required bool vertical}) {
            final children = [
              ElevatedButton.icon(
                onPressed: isLocked
                    ? null
                    : () async {
                        try {
                          await Supabase.instance.client
                              .from('donations')
                              .update({'status': 'verified'})
                              .eq('id', donation.id)
                              .select();

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Donation verified'),
                              ),
                            );
                          }

                          await onRefresh();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  donation.status == 'verified' ? 'Verified' : 'Approve',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: donation.status == 'verified'
                      ? Colors.grey
                      : const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: isLocked
                    ? null
                    : () async {
                        try {
                          await Supabase.instance.client
                              .from('donations')
                              .update({'status': 'rejected'})
                              .eq('id', donation.id)
                              .select();

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Donation rejected'),
                              ),
                            );
                          }

                          await onRefresh();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(
                  donation.status == 'rejected' ? 'Rejected' : 'Reject',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: donation.status == 'rejected'
                      ? Colors.grey
                      : const Color(0xFFDE4D4D),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                color: const Color(0xFFDE4D4D),
                tooltip: 'Delete donation',
              ),
            ];

            if (vertical) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  children[0],
                  const SizedBox(height: 10),
                  children[1],
                  const SizedBox(height: 8),
                  children[2],
                ],
              );
            }

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: children,
            );
          }

          if (isCompact || compactActions) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 14),
                actionButtons(vertical: true),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: 18),
              SizedBox(width: 310, child: actionButtons(vertical: false)),
            ],
          );
        },
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isStrong;

  const _MiniInfo({
    required this.icon,
    required this.text,
    this.isStrong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF647583)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: isStrong ? const Color(0xFF0F719F) : const Color(0xFF647583),
            fontWeight: isStrong ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
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

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 180,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
