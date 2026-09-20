import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../services/health_monitoring_service.dart';
import '../../services/medical_document_service.dart';
import '../../services/patient_service.dart';
import '../../utils/dialysis_readiness_analyzer.dart';

class MedicalRecordsPage extends StatefulWidget {
  final UserModel? user;

  const MedicalRecordsPage({super.key, this.user});

  @override
  State<MedicalRecordsPage> createState() => _MedicalRecordsPageState();
}

class _MedicalRecordsPageState extends State<MedicalRecordsPage> {
  final PatientService _patientService = PatientService();
  final MedicalDocumentService _documentService = MedicalDocumentService();
  final HealthMonitoringService _healthService = HealthMonitoringService();

  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _uploadedAt;
  List<MapEntry<String, String>> _documents = [];

  bool _isLoadingAnalysis = true;
  Map<String, dynamic>? _analyzedBp;
  Map<String, dynamic>? _analyzedWeight;
  bool _analysisIsToday = false;
  DialysisReadinessResult? _readinessResult;

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _loadReadinessAnalysis();
  }

  Future<void> _loadReadinessAnalysis() async {
    setState(() => _isLoadingAnalysis = true);

    try {
      final results = await Future.wait([
        _healthService.getBloodPressureRecords(),
        _healthService.getWeightRecords(),
      ]);

      final bpRecords = results[0];
      final weightRecords = results[1];

      final today = DateTime.now().toIso8601String().split('T').first;

      Map<String, dynamic>? findForToday(List<Map<String, dynamic>> records) {
        for (final record in records) {
          final sessionDate = record['session_date']?.toString().split('T').first;
          if (sessionDate == today) return record;
        }
        return null;
      }

      final todaysBp = findForToday(bpRecords);
      final todaysWeight = findForToday(weightRecords);

      final bp = todaysBp ?? (bpRecords.isNotEmpty ? bpRecords.first : null);
      final weight =
          todaysWeight ?? (weightRecords.isNotEmpty ? weightRecords.first : null);

      final systolic = int.tryParse(bp?['systolic']?.toString() ?? '');
      final diastolic = int.tryParse(bp?['diastolic']?.toString() ?? '');
      final beforeWeight = double.tryParse(
        weight?['before_weight']?.toString() ?? '',
      );
      final afterWeight = double.tryParse(
        weight?['after_weight']?.toString() ?? '',
      );

      if (!mounted) return;

      setState(() {
        _analyzedBp = bp;
        _analyzedWeight = weight;
        _analysisIsToday = todaysBp != null || todaysWeight != null;
        _readinessResult = DialysisReadinessAnalyzer.analyze(
          systolic: systolic,
          diastolic: diastolic,
          beforeWeight: beforeWeight,
          afterWeight: afterWeight,
        );
        _isLoadingAnalysis = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingAnalysis = false);
    }
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profileId = widget.user?.id;
      if (profileId == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to identify your account.';
        });
        return;
      }

      final patientRow = await _patientService.getActivePatientRow(
        profileId,
      );
      if (patientRow == null) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'You don\'t have an accepted clinic yet, so there are no '
              'medical records to show.';
        });
        return;
      }

      final documentsRow = await _documentService.getDocuments(
        patientId: patientRow['id'].toString(),
        clinicId: patientRow['clinic_id'],
      );

      if (documentsRow == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No medical documents were found on file.';
        });
        return;
      }

      final docs = <MapEntry<String, String>>[];
      for (final entry in MedicalDocumentService.documentLabels.entries) {
        final url = documentsRow[entry.key]?.toString();
        if (url != null && url.isNotEmpty) {
          docs.add(MapEntry(entry.value, url));
        }
      }

      setState(() {
        _documents = docs;
        _uploadedAt = DateTime.tryParse(
          documentsRow['uploaded_at']?.toString() ?? '',
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load medical records: $e';
      });
    }
  }

  void _viewImage(String label, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(24),
                  color: Colors.white,
                  child: const Text('Unable to load this image.'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color: Color(0xFF2C5F7D),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Medical Records',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF2C5F7D),
                onRefresh: () =>
                    Future.wait([_loadRecords(), _loadReadinessAnalysis()]),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildReadinessCard(),
                    const SizedBox(height: 20),
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: CircularProgressIndicator(
                            color: Color(0xFF2C5F7D),
                          ),
                        ),
                      )
                    else if (_errorMessage != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 24,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.folder_off_outlined,
                                size: 44,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF5B6D7D),
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                          if (_uploadedAt != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 18),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF6F7),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFD4E7EE),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.event_note_outlined,
                                    color: Color(0xFF2C5F7D),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Submitted on ${DateFormat('MMMM d, yyyy').format(_uploadedAt!)}',
                                      style: const TextStyle(
                                        color: Color(0xFF173B4F),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ..._documents.map((entry) {
                            final label = entry.key;
                            final url = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE1EAF0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _viewImage(label, url),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          12,
                                        ),
                                        child: Image.network(
                                          url,
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Container(
                                                    width: 64,
                                                    height: 64,
                                                    color: const Color(
                                                      0xFFF4F8FA,
                                                    ),
                                                    child: const Icon(
                                                      Icons
                                                          .image_not_supported_outlined,
                                                      color: Color(
                                                        0xFF5F7280,
                                                      ),
                                                    ),
                                                  ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              label,
                                              style: const TextStyle(
                                                color: Color(0xFF173B4F),
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            const Text(
                                              'Tap to view full image',
                                              style: TextStyle(
                                                color: Color(0xFF7A8A94),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Color(0xFF7A8A94),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessCard() {
    if (_isLoadingAnalysis) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1EAF0)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFF2C5F7D),
              ),
            ),
            SizedBox(width: 14),
            Text(
              'Analyzing today\'s BP and weight readings...',
              style: TextStyle(color: Color(0xFF5B6D7D), fontSize: 13),
            ),
          ],
        ),
      );
    }

    final result = _readinessResult;
    if (result == null || result.findings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1EAF0)),
        ),
        child: const Text(
          'No blood pressure or weight readings have been recorded yet, '
          'so there\'s nothing to analyze.',
          style: TextStyle(
            color: Color(0xFF5B6D7D),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      );
    }

    final Color accentColor = switch (result.level) {
      ReadinessLevel.critical => const Color(0xFFC0432A),
      ReadinessLevel.caution => const Color(0xFFB4690E),
      ReadinessLevel.normal => const Color(0xFF2A9D65),
    };
    final Color bgColor = switch (result.level) {
      ReadinessLevel.critical => const Color(0xFFFFF3F0),
      ReadinessLevel.caution => const Color(0xFFFFF8EC),
      ReadinessLevel.normal => const Color(0xFFF0FAF4),
    };
    final IconData icon = switch (result.level) {
      ReadinessLevel.critical => Icons.error_outline,
      ReadinessLevel.caution => Icons.warning_amber_rounded,
      ReadinessLevel.normal => Icons.check_circle_outline,
    };

    final sessionDate = _analyzedBp?['session_date'] ??
        _analyzedWeight?['session_date'];
    final parsedDate = DateTime.tryParse(sessionDate?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Health Analyzer',
                      style: TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.verdict,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _analysisIsToday
                ? 'Based on the BP/weight entered by your clinic today'
                    '${parsedDate != null ? ' (${DateFormat('MMM d, yyyy').format(parsedDate)})' : ''}.'
                : 'No entry for today yet — showing the most recent reading on '
                    'file${parsedDate != null ? ' (${DateFormat('MMM d, yyyy').format(parsedDate)})' : ''}.',
            style: const TextStyle(color: Color(0xFF7A8A94), fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          ...result.findings.map((finding) {
            final Color dotColor = switch (finding.level) {
              ReadinessLevel.critical => const Color(0xFFC0432A),
              ReadinessLevel.caution => const Color(0xFFB4690E),
              ReadinessLevel.normal => const Color(0xFF2A9D65),
            };

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      finding.message,
                      style: const TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
