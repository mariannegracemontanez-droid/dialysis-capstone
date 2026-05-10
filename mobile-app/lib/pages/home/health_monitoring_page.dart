import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/health_monitoring_service.dart';

class HealthMonitoringPage extends StatefulWidget {
  const HealthMonitoringPage({super.key});

  @override
  State<HealthMonitoringPage> createState() => _HealthMonitoringPageState();
}

class _HealthMonitoringPageState extends State<HealthMonitoringPage> {
  final HealthMonitoringService _service = HealthMonitoringService();
  final int _dailyGoalMl = 1500;
  bool _isLoading = true;
  int _todayTotalMl = 0;
  List<Map<String, dynamic>> _todayLogs = [];
  List<Map<String, dynamic>> _historyLogs = [];
  Map<String, dynamic>? _latestBloodPressure;
  Map<String, dynamic>? _latestWeightLog;

  @override
  void initState() {
    super.initState();
    _loadHealthData();
  }

  Future<void> _loadHealthData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _service.getTodayWaterTotal(),
        _service.getTodayWaterLogs(),
        _service.getWaterHistory(),
        _service.getLatestBloodPressure(),
        _service.getLatestWeightLog(),
      ]);

      setState(() {
        _todayTotalMl = results[0] as int;
        _todayLogs = List<Map<String, dynamic>>.from(
          results[1] as List<dynamic>,
        );
        _historyLogs = List<Map<String, dynamic>>.from(
          results[2] as List<dynamic>,
        );
        _latestBloodPressure = results[3] as Map<String, dynamic>?;
        _latestWeightLog = results[4] as Map<String, dynamic>?;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load health data: $error')),
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

  double get _progressValue => min(_todayTotalMl / _dailyGoalMl, 1.0);

  String get _todayDateLabel =>
      DateFormat('MMMM d, yyyy').format(DateTime.now());

  String _formatTime(String loggedAt) {
    try {
      final parsed = DateTime.parse(loggedAt).toLocal();
      return DateFormat.jm().format(parsed);
    } catch (_) {
      return loggedAt;
    }
  }

  Future<void> _showAddWaterIntakeSheet() async {
    int? selectedAmount;
    final customController = TextEditingController();
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const Text(
                    'Add Water Intake',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text('Choose a preset or enter a custom amount in mL.'),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildAmountButton(100, selectedAmount, setModalState),
                      _buildAmountButton(250, selectedAmount, setModalState),
                      _buildAmountButton(500, selectedAmount, setModalState),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: customController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Custom amount (mL)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      setModalState(() {
                        selectedAmount = null;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF008B8B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final customText = customController.text.trim();
                              final amount = customText.isNotEmpty
                                  ? int.tryParse(customText)
                                  : selectedAmount;

                              if (amount == null || amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please select or enter a valid amount.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final scaffold = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(context);

                              setModalState(() {
                                isSaving = true;
                              });

                              try {
                                await _service.addWaterIntake(amount);
                                await _loadHealthData();
                                if (mounted) {
                                  navigator.pop();
                                }
                              } catch (error) {
                                if (mounted) {
                                  scaffold.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Unable to save intake: $error',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setModalState(() {
                                    isSaving = false;
                                  });
                                }
                              }
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          isSaving ? 'Saving...' : 'Save Intake',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAmountButton(
    int amount,
    int? selectedAmount,
    void Function(void Function()) setModalState,
  ) {
    final bool isSelected = selectedAmount == amount;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFF225E72) : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.black,
        side: BorderSide(
          color: isSelected ? Colors.transparent : Colors.grey.shade300,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      onPressed: () {
        setModalState(() {
          selectedAmount = amount;
        });
      },
      child: Text(
        '${amount} mL',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _showTodayLogs() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 6,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const Text(
                  'Today’s Water Intake Logs',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_todayLogs.isEmpty) ...[
                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      'No logs for today yet. Add water intake to start tracking.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ] else ...[
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _todayLogs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = _todayLogs[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${log['amount_ml']} mL',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _formatTime(log['logged_at'] as String? ?? ''),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderCard(String title, String message, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F7F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF008B8B), size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final bloodPressureContent = _latestBloodPressure == null
        ? _buildPlaceholderCard(
            'Blood Pressure',
            'Wait for the admin to input data',
            Icons.favorite_border,
          )
        : Container();

    final weightContent = _latestWeightLog == null
        ? _buildPlaceholderCard(
            'Weight Monitoring',
            'Wait for the admin to input data',
            Icons.monitor_weight_outlined,
          )
        : Container();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Latest Session',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _todayDateLabel,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          bloodPressureContent,
          const SizedBox(height: 18),
          weightContent,
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F7F7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.water_drop,
                        color: Color.fromARGB(255, 16, 98, 192),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Water Intake',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '${(_todayTotalMl / 1000).toStringAsFixed(1)} L',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Daily Goal: ${(_dailyGoalMl / 1000).toStringAsFixed(1)} L',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _progressValue,
                          minHeight: 12,
                          color: const Color.fromARGB(255, 22, 185, 226),
                          backgroundColor: const Color(0xFFE8F7F7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(_progressValue * 100).clamp(0, 100).round()}%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _showAddWaterIntakeSheet,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF225E72),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Add Water Intake',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _showTodayLogs,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color.fromARGB(255, 8, 80, 122),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'View Today’s Logs',
                          style: TextStyle(
                            color: Color.fromARGB(255, 3, 47, 83),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Manually log your water intake throughout the day',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_historyLogs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.history, size: 44, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No water intake history yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final log in _historyLogs) {
      final logDate = log['log_date'] as String? ?? '';
      final formatted = _formatHistoryDate(logDate);
      grouped.putIfAbsent(formatted, () => []).add(log);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: grouped.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ...entry.value.map((log) {
                final amount = log['amount_ml']?.toString() ?? '0';
                final time = _formatTime(log['logged_at'] as String? ?? '');
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$amount mL',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            time,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const Icon(
                        Icons.water_drop,
                        color: Color.fromARGB(255, 6, 145, 238),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 18),
            ],
          );
        }).toList(),
      ),
    );
  }

  String _formatHistoryDate(String dateValue) {
    try {
      final date = DateTime.parse(dateValue).toLocal();
      return DateFormat('EEEE, MMM d, yyyy').format(date);
    } catch (_) {
      return dateValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBFB),
      body: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF225E72), Color(0xFF1D4356)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.notifications_none,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Health Monitoring',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Track your vital signs and progress',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TabBar(
                        indicator: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        labelColor: const Color(0xFF225E72),
                        unselectedLabelColor: Colors.white70,
                        tabs: const [
                          Tab(text: 'Overview'),
                          Tab(text: 'History'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF225E72),
                        ),
                      )
                    : TabBarView(
                        children: [_buildOverviewTab(), _buildHistoryTab()],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
