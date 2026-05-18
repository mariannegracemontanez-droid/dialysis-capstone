import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/health_monitoring_service.dart';
import 'package:fl_chart/fl_chart.dart';

class HealthMonitoringPage extends StatefulWidget {
  const HealthMonitoringPage({super.key});

  @override
  State<HealthMonitoringPage> createState() => _HealthMonitoringPageState();
}

class _HealthMonitoringPageState extends State<HealthMonitoringPage> {
  final HealthMonitoringService _service = HealthMonitoringService();
  final int _dailyGoalMl = 1000;
  bool _isLoading = true;
  int _todayTotalMl = 0;
  int _selectedTabIndex = 0;
  List<Map<String, dynamic>> _todayLogs = [];
  List<Map<String, dynamic>> _historyLogs = [];
  Map<String, dynamic>? _latestBloodPressure;
  Map<String, dynamic>? _latestWeightLog;

  RealtimeChannel? _monitoringChannel;

  @override
  void initState() {
    super.initState();
    _loadHealthData();
    _setupRealtime();
  }

  void _setupRealtime() {
    _monitoringChannel = Supabase.instance.client
        .channel('mobile-health-monitoring')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blood_pressure_logs',
          callback: (payload) {
            if (!mounted) return;
            _loadHealthData();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'weight_logs',
          callback: (payload) {
            if (!mounted) return;
            _loadHealthData();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _monitoringChannel?.unsubscribe();
    super.dispose();
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

  double get _progressValue {
    if (_todayTotalMl <= 0) return 0;

    final progress = _todayTotalMl / _dailyGoalMl;

    if (progress > 1.0) {
      return 1.0;
    }

    return progress;
  }

  bool get _isWaterExceeded => _todayTotalMl > _dailyGoalMl;

  Color get _waterStatusColor =>
      _isWaterExceeded ? const Color(0xFFE53935) : const Color(0xFF16B9E2);

  int get _waterPercent => ((_todayTotalMl / _dailyGoalMl) * 100).round();

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
                      _buildAmountButton(
                        amount: 100,
                        selectedAmount: selectedAmount,
                        onTap: () {
                          setModalState(() {
                            selectedAmount = 100;
                            customController.clear();
                          });
                        },
                      ),
                      _buildAmountButton(
                        amount: 250,
                        selectedAmount: selectedAmount,
                        onTap: () {
                          setModalState(() {
                            selectedAmount = 250;
                            customController.clear();
                          });
                        },
                      ),
                      _buildAmountButton(
                        amount: 500,
                        selectedAmount: selectedAmount,
                        onTap: () {
                          setModalState(() {
                            selectedAmount = 500;
                            customController.clear();
                          });
                        },
                      ),
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

  Widget _buildAmountButton({
    required int amount,
    required int? selectedAmount,
    required VoidCallback onTap,
  }) {
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
      onPressed: onTap,
      child: Text(
        '$amount mL',
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
                    separatorBuilder: (_, _) => const Divider(height: 1),
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
        : _buildBloodPressureCard(_latestBloodPressure!);

    final weightContent = _latestWeightLog == null
        ? _buildPlaceholderCard(
            'Weight Monitoring',
            'Wait for the admin to input data',
            Icons.monitor_weight_outlined,
          )
        : _buildWeightCard(_latestWeightLog!);

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
                          backgroundColor: const Color(0xFFE8F7F7),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _waterStatusColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$_waterPercent%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _waterStatusColor,
                      ),
                    ),
                  ],
                ),

                if (_isWaterExceeded) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'You have exceeded your recommended water intake for today.',
                    style: TextStyle(
                      color: Color(0xFFE53935),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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

  Widget _buildBloodPressureCard(Map<String, dynamic> bp) {
    final systolic = bp['systolic']?.toString() ?? '--';
    final diastolic = bp['diastolic']?.toString() ?? '--';
    final date = bp['session_date']?.toString() ?? '';
    final notes = bp['notes']?.toString();

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _showBloodPressureDetails,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            _iconBox(Icons.favorite, Colors.red),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Blood Pressure',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$systolic/$diastolic mmHg',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getBpDescription(
                      int.tryParse(systolic),
                      int.tryParse(diastolic),
                    ),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      notes,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    date,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightCard(Map<String, dynamic> weight) {
    final before = double.tryParse(weight['before_weight'].toString()) ?? 0;
    final after = double.tryParse(weight['after_weight'].toString()) ?? 0;
    final removed = before - after;
    final date = weight['session_date']?.toString() ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _showWeightDetails,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            _iconBox(Icons.monitor_weight_outlined, const Color(0xFF225E72)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Weight Monitoring',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${before.toStringAsFixed(1)} kg → ${after.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fluid removed: ${removed.toStringAsFixed(1)} kg',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getWeightDescription(removed),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    date,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 14,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }

  String _getBpDescription(int? systolic, int? diastolic) {
    if (systolic == null || diastolic == null) {
      return 'Blood pressure data is incomplete.';
    }

    if (systolic < 90 || diastolic < 60) {
      return 'Your blood pressure is lower than normal.';
    }

    if (systolic <= 120 && diastolic <= 80) {
      return 'Your blood pressure is within the normal range.';
    }

    return 'Your blood pressure is higher than normal.';
  }

  String _getWeightDescription(double removed) {
    if (removed <= 0) {
      return 'No fluid removal detected or data may be incomplete.';
    }

    if (removed <= 3) {
      return 'Fluid removed is within a common range.';
    }

    return 'Fluid removed is high. Please follow your clinic’s advice.';
  }

  Future<void> _showBloodPressureDetails() async {
    final records = await _service.getBloodPressureRecords();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sheetHandle(),
                    const Text(
                      'Blood Pressure Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildBloodPressureChart(records),
                    const SizedBox(height: 16),
                    _analysisBox(
                      'Blood Pressure Analysis',
                      records.isEmpty
                          ? 'No blood pressure records yet.'
                          : 'This section shows your BP trend based on admin-recorded dialysis sessions.',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'BP Records',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (records.isEmpty)
                      const Text('No BP records available.')
                    else
                      ...records.map((bp) {
                        return _recordTile(
                          title: '${bp['systolic']}/${bp['diastolic']} mmHg',
                          subtitle: bp['session_date']?.toString() ?? '',
                          notes: bp['notes']?.toString(),
                          icon: Icons.favorite,
                        );
                      }),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showWeightDetails() async {
    final records = await _service.getWeightRecords();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sheetHandle(),
                    const Text(
                      'Weight Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildWeightChart(records),
                    const SizedBox(height: 16),
                    _analysisBox(
                      'Weight Analysis',
                      records.isEmpty
                          ? 'No weight records yet.'
                          : 'This section shows your before and after dialysis weight trend.',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Weight Records',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (records.isEmpty)
                      const Text('No weight records available.')
                    else
                      ...records.map((weight) {
                        final before =
                            double.tryParse(
                              weight['before_weight'].toString(),
                            ) ??
                            0;
                        final after =
                            double.tryParse(
                              weight['after_weight'].toString(),
                            ) ??
                            0;
                        final removed = before - after;

                        return _recordTile(
                          title:
                              '${before.toStringAsFixed(1)} kg → ${after.toStringAsFixed(1)} kg',
                          subtitle:
                              'Fluid removed: ${removed.toStringAsFixed(1)} kg • ${weight['session_date']}',
                          notes: weight['notes']?.toString(),
                          icon: Icons.monitor_weight_outlined,
                        );
                      }),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 50,
        height: 6,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _chartPlaceholder(String title, String subtitle) {
    return Container(
      width: double.infinity,
      height: 180,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.show_chart, size: 42, color: Color(0xFF225E72)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _analysisBox(String title, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0EEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _recordTile({
    required String title,
    required String subtitle,
    required IconData icon,
    String? notes,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF225E72)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(notes, style: TextStyle(color: Colors.grey.shade500)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloodPressureChart(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return _emptyChart('No BP chart data available.');
    }

    final reversed = records.reversed.toList();

    final systolicSpots = <FlSpot>[];
    final diastolicSpots = <FlSpot>[];

    for (int i = 0; i < reversed.length; i++) {
      final item = reversed[i];

      final systolic = double.tryParse(item['systolic'].toString()) ?? 0;

      final diastolic = double.tryParse(item['diastolic'].toString()) ?? 0;

      systolicSpots.add(FlSpot(i.toDouble(), systolic));
      diastolicSpots.add(FlSpot(i.toDouble(), diastolic));
    }

    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Blood Pressure Trend',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 40,
                maxY: 200,
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: systolicSpots,
                    isCurved: true,
                    barWidth: 4,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: diastolicSpots,
                    isCurved: true,
                    barWidth: 4,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Icon(Icons.circle, size: 12),
              SizedBox(width: 6),
              Text('Systolic'),
              SizedBox(width: 20),
              Icon(Icons.circle_outlined, size: 12),
              SizedBox(width: 6),
              Text('Diastolic'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeightChart(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return _emptyChart('No weight chart data available.');
    }

    final reversed = records.reversed.toList();

    final beforeSpots = <FlSpot>[];
    final afterSpots = <FlSpot>[];

    for (int i = 0; i < reversed.length; i++) {
      final item = reversed[i];

      final before = double.tryParse(item['before_weight'].toString()) ?? 0;

      final after = double.tryParse(item['after_weight'].toString()) ?? 0;

      beforeSpots.add(FlSpot(i.toDouble(), before));
      afterSpots.add(FlSpot(i.toDouble(), after));
    }

    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weight Trend',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: beforeSpots,
                    isCurved: true,
                    barWidth: 4,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: afterSpots,
                    isCurved: true,
                    barWidth: 4,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Icon(Icons.circle, size: 12),
              SizedBox(width: 6),
              Text('Before'),
              SizedBox(width: 20),
              Icon(Icons.circle_outlined, size: 12),
              SizedBox(width: 6),
              Text('After'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyChart(String message) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(message, style: TextStyle(color: Colors.grey.shade600)),
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
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
              decoration: const BoxDecoration(
                color: Color(0xFF225E72),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Health Monitoring',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Track your health records, water intake, and dialysis monitoring progress.',
                    style: TextStyle(
                      color: Color(0xFFD9EDF3),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 22),

                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedTabIndex = 0;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                color: _selectedTabIndex == 0
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Overview',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _selectedTabIndex == 0
                                      ? const Color(0xFF225E72)
                                      : Colors.white70,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),

                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedTabIndex = 1;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                color: _selectedTabIndex == 1
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'History',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _selectedTabIndex == 1
                                      ? const Color(0xFF225E72)
                                      : Colors.white70,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
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
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _selectedTabIndex == 0
                          ? _buildOverviewTab()
                          : _buildHistoryTab(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
