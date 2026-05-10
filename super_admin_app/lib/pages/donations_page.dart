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
          centerTotals[item.centerName] = (centerTotals[item.centerName] ?? 0.0) + item.amount.toDouble();
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

    Map<String, dynamic>? selectedCenter = _centers.isNotEmpty ? _centers.first : null;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Distribute Funds'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<Map<String, dynamic>>(
                        initialValue: selectedCenter,
                        items: _centers.map((center) {
                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: center,
                            child: Text(center['name']),
                          );
                        }).toList(),
                        decoration: const InputDecoration(
                          labelText: 'Center',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedCenter = value;
                          });
                        },
                        validator: (value) => value == null ? 'Select a center' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: amountController,
                        label: 'Amount',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: remarksController,
                        label: 'Remarks',
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          final amountText = amountController.text.trim();
                          if (amountText.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Invalid amount format'),
                              ),
                            );
                            return;
                          }

                          if (amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid amount'),
                              ),
                            );
                            return;
                          }

                          if (selectedCenter == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Select a center'),
                              ),
                            );
                            return;
                          }
                          if (amount > _availableFunds) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Insufficient available funds'),
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
                              remarks: remarksController.text.trim(),
                            );

                            Navigator.pop(context);
                            await _loadDonations();

                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Funds distributed successfully'),
                              ),
                            );
                          } catch (error) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
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
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Distribute'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteDonation(DonationRecord donation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA5353),
            ),
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
    final totalDonations = _summary.fold<double>(0, (sum, item) => sum + item.totalAmount);
    final distributionCount = _fundDistributions.length;
    final hasPieData = pendingCount + verifiedCount + rejectedCount > 0;
   final double maxY = centerTotals.isNotEmpty
    ? centerTotals.values.reduce(
          (a, b) => a > b ? a : b,
        ) +
        1000.0
    : 1000.0;

    return Container(
      color: const Color(0xFFF3F6F9),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Distribute Donation',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F3A55),
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Allocate donations to centers, track audit logs, and keep donor engagement visible.',
                          style: TextStyle(fontSize: 16, color: Color(0xFF647583), height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _showDonationDialog,
                    icon: const Icon(Icons.local_shipping),
                    label: const Text('Distribute Funds'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F719F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Wrap(
                runSpacing: 16,
                spacing: 16,
                children: [
                  SizedBox(
                    width: 280,
                    child: _InfoCard(
                      label: 'Total Donations',
                      value: '₱${totalDonations.toStringAsFixed(0)}',
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: _InfoCard(
                      label: 'Distributions',
                      value: distributionCount.toString(),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: _InfoCard(
                      label: 'Available Funds',
                      value: '₱${_availableFunds.toStringAsFixed(0)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width > 1150 ? 520 : double.infinity,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 22,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Donation Status Overview',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F3A55),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Visualize current donation status and workflow performance.',
                            style: TextStyle(fontSize: 14, color: Color(0xFF647583), height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 300,
                            child: hasPieData
                                ? Column(
                                    children: [
                                      Expanded(
                                        child: PieChart(
                                          PieChartData(
                                            sectionsSpace: 10,
                                            centerSpaceRadius: 52,
                                            borderData: FlBorderData(show: false),
                                            sections: [
                                              PieChartSectionData(
                                                value: pendingCount.toDouble(),
                                                title: 'Pending',
                                                color: const Color(0xFFFB8B3C),
                                                radius: 70,
                                                titleStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                titlePositionPercentageOffset: 0.55,
                                              ),
                                              PieChartSectionData(
                                                value: verifiedCount.toDouble(),
                                                title: 'Approved',
                                                color: const Color(0xFF0F719F),
                                                radius: 70,
                                                titleStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                titlePositionPercentageOffset: 0.55,
                                              ),
                                              PieChartSectionData(
                                                value: rejectedCount.toDouble(),
                                                title: 'Rejected',
                                                color: const Color(0xFFDE4D4D),
                                                radius: 70,
                                                titleStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                titlePositionPercentageOffset: 0.55,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          _LegendChip(label: 'Pending', color: const Color(0xFFFB8B3C), value: pendingCount.toString()),
                                          _LegendChip(label: 'Approved', color: const Color(0xFF0F719F), value: verifiedCount.toString()),
                                          _LegendChip(label: 'Rejected', color: const Color(0xFFDE4D4D), value: rejectedCount.toString()),
                                        ],
                                      ),
                                    ],
                                  )
                                : const Center(
                                    child: Text(
                                      'No donation analytics available yet.',
                                      style: TextStyle(color: Color(0xFF647583)),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width > 1150 ? 620 : double.infinity,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 22,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Distribution Per Center',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F3A55),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Compare fund distribution across centers with a cleaner bar view.',
                            style: TextStyle(fontSize: 14, color: Color(0xFF647583), height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 320,
                            child: centerTotals.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No distribution data available.',
                                      style: TextStyle(color: Color(0xFF647583)),
                                    ),
                                  )
                                : BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY: maxY,
                                      barTouchData: BarTouchData(enabled: false),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        horizontalInterval: maxY / 4,
                                        getDrawingHorizontalLine: (value) => FlLine(
                                          color: const Color(0xFFE9EEF3),
                                          strokeWidth: 1,
                                        ),
                                      ),
                                      titlesData: FlTitlesData(
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            interval: maxY / 4,
                                            reservedSize: 36,
                                            getTitlesWidget: (value, meta) => Text(
                                              '₱${value.toInt()}',
                                              style: const TextStyle(color: Color(0xFF7F8B9B), fontSize: 11),
                                            ),
                                          ),
                                        ),
                                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (value, meta) {
                                              final keys = centerTotals.keys.toList();
                                              if (value.toInt() >= keys.length) {
                                                return const SizedBox();
                                              }
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 10),
                                                child: Text(
                                                  keys[value.toInt()],
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(color: Color(0xFF7F8B9B), fontSize: 12),
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
                                              width: 28,
                                              borderRadius: BorderRadius.circular(14),
                                              color: const Color(0xFF0F719F),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 22,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Donations',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F3A55),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Review donation records, approve or reject submissions, and access receipts quickly.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF647583), height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _donations.isEmpty
                            ? const Text('No donations yet', style: TextStyle(color: Color(0xFF647583)))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Pending Donations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F719F))),
                                  const SizedBox(height: 12),
                                  ..._donations
                                      .where((d) => d.status == 'pending')
                                      .map((donation) => Padding(
                                            padding: const EdgeInsets.only(bottom: 16),
                                            child: _DonationRow(
                                              donation: donation,
                                              onDelete: () => _deleteDonation(donation),
                                              onRefresh: _loadDonations,
                                            ),
                                          ))
                                      .toList(),
                                  const SizedBox(height: 20),
                                  const Text('Approved Donations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                                  const SizedBox(height: 12),
                                  ..._donations
                                      .where((d) => d.status == 'verified')
                                      .map((donation) => Padding(
                                            padding: const EdgeInsets.only(bottom: 16),
                                            child: _DonationRow(
                                              donation: donation,
                                              onDelete: () => _deleteDonation(donation),
                                              onRefresh: _loadDonations,
                                            ),
                                          ))
                                      .toList(),
                                  const SizedBox(height: 20),
                                  const Text('Rejected Donations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFB00020))),
                                  const SizedBox(height: 12),
                                  ..._donations
                                      .where((d) => d.status == 'rejected')
                                      .map((donation) => Padding(
                                            padding: const EdgeInsets.only(bottom: 16),
                                            child: _DonationRow(
                                              donation: donation,
                                              onDelete: () => _deleteDonation(donation),
                                              onRefresh: _loadDonations,
                                            ),
                                          ))
                                      .toList(),
                                ],
                              ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 22,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Audit Log',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF0F3A55)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Track fund distributions and activity history with improved readability.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF647583), height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _fundDistributions.isEmpty
                            ? const Center(child: Text('No distribution audit entries available.', style: TextStyle(color: Color(0xFF647583))))
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 24,
                                  headingRowHeight: 56,
                                  dataRowMinHeight: 56,
                                  dataRowMaxHeight: 56,
                                  headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F3A55)),
                                  dataTextStyle: const TextStyle(color: Color(0xFF36424C)),
                                  columns: const [
                                    DataColumn(label: Text('Date')),
                                    DataColumn(label: Text('Center')),
                                    DataColumn(label: Text('Amount')),
                                    DataColumn(label: Text('Remarks')),
                                    DataColumn(label: Text('Status')),
                                  ],
                                  rows: _fundDistributions.map((entry) {
                                    return DataRow(cells: [
                                      DataCell(Text('${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')}')),
                                      DataCell(Text(entry.centerName)),
                                      DataCell(Text('₱${entry.amount.toStringAsFixed(0)}')),
                                      DataCell(Text(entry.remarks)),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF2F7FB),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(entry.status, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F719F))),
                                        ),
                                      ),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: (value) => (value == null || value.isEmpty) ? 'This field is required' : null,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: const Color(0xFFF6FBFF),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _LegendChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha((0.12 * 255).round()),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF324A5F))),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F3A55))),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;

  const _InfoCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF647583), fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF0F3A55))),
        ],
      ),
    );
  }
}

class _DonationRow extends StatelessWidget {
  final DonationRecord donation;
  final VoidCallback onDelete;
  final Future<void> Function() onRefresh;

  const _DonationRow({
    required this.donation,
    required this.onDelete,
    required this.onRefresh,
  });

  Color get statusColor {
    if (donation.status == 'verified') return const Color(0xFF2E7D32);
    if (donation.status == 'rejected') return const Color(0xFFDE4D4D);
    return const Color(0xFF0F719F);
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 18, offset: Offset(0, 12)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        donation.donorName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F3A55)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha((0.14 * 255).round()),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  donation.paymentMethod ?? 'No payment method',
                  style: const TextStyle(color: Color(0xFF647583)),
                ),
                const SizedBox(height: 10),
                Text(
                  '₱${donation.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F719F)),
                ),
                if (donation.proofUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            child: Image.network(donation.proofUrl!),
                          ),
                        );
                      },
                      child: const Text(
                        'View Receipt',
                        style: TextStyle(color: Color(0xFF0F719F), decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ElevatedButton(
                onPressed: donation.status == 'verified' || donation.status == 'rejected'
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
                              const SnackBar(content: Text('Donation verified')),
                            );
                          }
                          await onRefresh();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: donation.status == 'verified' ? Colors.grey : const Color(0xFF38A6DB),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(donation.status == 'verified' ? 'Verified' : 'Approve'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: donation.status == 'verified' || donation.status == 'rejected'
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
                              const SnackBar(content: Text('Donation rejected')),
                            );
                          }
                          await onRefresh();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: donation.status == 'rejected' ? Colors.grey : const Color(0xFFDE4D4D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(donation.status == 'rejected' ? 'Rejected' : 'Reject'),
              ),
              const SizedBox(height: 8),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete, color: Color(0xFFDE4D4D)),
                tooltip: 'Delete donation',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
