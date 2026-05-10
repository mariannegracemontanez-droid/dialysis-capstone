import 'package:flutter/material.dart';
import '../models/donation_record.dart';
import '../models/donation_summary.dart';
import '../models/fund_distribution.dart';
import 'package:super_admin_app/services/donation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

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
  List<Map<String, dynamic>>_centers = [];
  int _donorCount = 0;
  double _availableFunds = 0;

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
      final donorCount = await _service.fetchDonorCount();
      final totalDonations = await _service.fetchTotalDonations();
      final totalDistributed = await _service.fetchTotalDistributed();


      if (!mounted) return;

      setState(() {
        _availableFunds = totalDonations - totalDistributed;
        _donations = donations;
        _summary = summary;
        _fundDistributions = distributions;
        _centers = centers;
        _donorCount = donorCount;
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

  Map<String, dynamic>? selectedCenter =
    _centers.isNotEmpty ? _centers.first : null;

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
                  /// CENTER DROPDOWN
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
                    validator: (value) =>
                        value == null ? 'Select a center' : null,
                  ),

                  const SizedBox(height: 12),

                  /// AMOUNT
                  _buildTextField(
                    controller: amountController,
                    label: 'Amount',
                    keyboardType: TextInputType.number,
                  ),

                  const SizedBox(height: 12),

                  /// REMARKS
                  _buildTextField(
                    controller: remarksController,
                    label: 'Remarks',
                  ),
                ],
              ),
            ),
          ),

          /// ACTIONS
          actions: [
            TextButton(
              onPressed:
                  isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),

            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      /// VALIDATION
                      if (!formKey.currentState!.validate()) return;

                      final amountText =
                          amountController.text.trim();

                      if (amountText.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Enter amount"),
                          ),
                        );
                        return;
                      }

                      double amount;

                      try {
                        amount = double.parse(amountText);
                      } catch (_) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content:
                                Text("Invalid amount format"),
                          ),
                        );
                        return;
                      }

                      if (amount <= 0) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content:
                                Text("Enter a valid amount"),
                          ),
                        );
                        return;
                      }

                      /// 🔥 CENTER CHECK
                      if (selectedCenter == null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content:
                                Text("Select a center"),
                          ),
                        );
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                      });

                      try {
                        print("CENTER: ${selectedCenter!['name']}");
                        print("CLINIC ID: ${selectedCenter!['id']}");
                        print("AMOUNT: $amount");

                        await _service.createFundDistribution(
                          clinicId: selectedCenter!['id'],
                          centerName: selectedCenter!['name'],
                          amount: amount,
                          remarks:
                              remarksController.text.trim(),
                        );

                        Navigator.pop(context);

                        await _loadDonations();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Funds distributed successfully',
                              ),
                            ),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content:
                                  Text('Error: $error'),
                            ),
                          );
                        }
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

   return SingleChildScrollView(
  child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// HEADER
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Distribute Donation',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F3A55),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Allocate donations to centers, track audit logs, and keep donor engagement visible.',
                    style: TextStyle(fontSize: 16, color: Color(0xFF647583)),
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
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        /// STATS
        Row(
          children: [
            _InfoCard(label: 'Donors', value: _donorCount.toString()),
            const SizedBox(width: 14),
            _InfoCard(
              label: 'Total Donations',
              value: '₱${_summary.fold<double>(0, (sum, item) => sum + item.totalAmount).toStringAsFixed(0)}',
            ),
            const SizedBox(width: 14),
            _InfoCard(
              label: 'Distributions',
              value: _fundDistributions.length.toString(),
            ),
            _InfoCard(
          label: 'Available Funds',
          value: '₱${_availableFunds.toStringAsFixed(0)}',
        ),
          ],
        ),

        const SizedBox(height: 24),

        /// 🔥 DONATIONS LIST (NEW)
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Donations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _donations.isEmpty
                      ? const Text("No donations yet")
                      : Column(
                          children: _donations.map((donation) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _DonationRow(
                              donation: donation,
                              onDelete: () => _deleteDonation(donation),
                              onRefresh: _loadDonations,
                            ),
                            );
                          }).toList(),
                        ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        /// DISTRIBUTION CHART
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Donation Distribution by Center',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),

              _summary.isEmpty
                  ? const Center(child: Text('No donation data available yet.'))
                  : Column(
                      children: _summary.map((item) {
                         final total = _summary.fold<double>(
                        0,
                        (sum, e) => sum + e.totalAmount,
                      );

                      final progress = total > 0 ? (item.totalAmount / total) : 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.centerName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    '₱${item.totalAmount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 10,
                                    color: const Color(0xFF0F719F),
                                    backgroundColor: const Color(0xFFE8F1F6),
                                  ),
                                ),
                              ],
                          ),
                        );
                      }).toList(),
                    ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        /// AUDIT LOG
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Audit Log',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _fundDistributions.isEmpty
                      ? const Center(
                          child:
                              Text('No distribution audit entries available.'))
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Center')),
                              DataColumn(label: Text('Amount')),
                              DataColumn(label: Text('Remarks')),
                              DataColumn(label: Text('Status')),
                            ],
                            rows: _fundDistributions.map((entry) {
                              return DataRow(cells: [
                                DataCell(Text(
                                    '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')}')),
                                DataCell(Text(entry.centerName)),
                                DataCell(Text(
                                    '₱${entry.amount.toStringAsFixed(0)}')),
                                DataCell(Text(entry.remarks)),
                                DataCell(Text(entry.status)),
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

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;

  const _InfoCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 18, offset: Offset(0, 8))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF647583), fontSize: 12)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF0F3A55))),
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
  

  const _DonationRow({
    required this.donation,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FCFE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// LEFT SIDE (INFO)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  donation.donorName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),

                Text(
                  donation.paymentMethod ?? 'No payment method',
                  style: const TextStyle(color: Color(0xFF647583)),
                ),
                const SizedBox(height: 6),

                Text(
                  '₱${donation.amount.toStringAsFixed(0)} • ${donation.status}',
                  style: const TextStyle(
                    color: Color(0xFF0F719F),
                    fontWeight: FontWeight.w600,
                  ),
                ),

                /// RECEIPT
                if (donation.proofUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
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
                        "View Receipt",
                        style: TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          /// RIGHT SIDE (ACTIONS)
          Column(
            children: [
              ElevatedButton(
                onPressed: donation.status == 'verified'
                    ? null
                    : () async {
                        try {
                          final response = await Supabase.instance.client
                              .from('donations')
                              .update({'status': 'verified'})
                              .eq('id', donation.id)
                              .select();

                          print("UPDATED: $response");

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Donation verified')),
                            );
                          }

                          await onRefresh(); // 🔥 IMPORTANT
                        } catch (e) {
                          print("ERROR: $e");

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: donation.status == 'verified'
                      ? Colors.grey
                      : const Color(0xFF38A6DB),
                ),
                child: Text(
                  donation.status == 'verified' ? "Verified" : "Approve",
                ),
              ),

              const SizedBox(height: 8),

              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}