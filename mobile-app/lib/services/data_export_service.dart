import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/user_model.dart';
import 'appointment_service.dart';
import 'health_monitoring_service.dart';
import 'medical_document_service.dart';
import 'patient_service.dart';

/// Builds a single PDF containing everything a patient might want a copy
/// of: their dialysis schedule, BP/weight/water intake history, and the
/// medical documents they submitted when applying to their clinic.
class DataExportService {
  final PatientService _patientService = PatientService();
  final HealthMonitoringService _healthService = HealthMonitoringService();
  final AppointmentService _appointmentService = AppointmentService();
  final MedicalDocumentService _documentService = MedicalDocumentService();

  static const _brandColor = PdfColor.fromInt(0xFF2C5F7D);
  static const _mutedColor = PdfColor.fromInt(0xFF5B6D7D);

  Future<Uint8List> generateMyDataPdf(UserModel user) async {
    final results = await Future.wait([
      _patientService.getActivePatientRow(user.id),
      _healthService.getBloodPressureRecords(),
      _healthService.getWeightRecords(),
      _healthService.getAllWaterHistory(),
      _appointmentService.getMySchedule().catchError((_) => null),
    ]);

    final patientRow = results[0] as Map<String, dynamic>?;
    final bpRecords = results[1] as List<Map<String, dynamic>>;
    final weightRecords = results[2] as List<Map<String, dynamic>>;
    final waterRecords = results[3] as List<Map<String, dynamic>>;
    final scheduleData = results[4] as Map<String, dynamic>?;

    Map<String, dynamic>? documentsRow;
    if (patientRow != null) {
      try {
        documentsRow = await _documentService.getDocuments(
          patientId: patientRow['id'].toString(),
          clinicId: patientRow['clinic_id'],
        );
      } catch (_) {
        documentsRow = null;
      }
    }

    final documentImages = <String, Uint8List>{};
    if (documentsRow != null) {
      for (final key in MedicalDocumentService.documentLabels.keys) {
        final url = documentsRow[key]?.toString();
        if (url == null || url.isEmpty) continue;
        try {
          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            documentImages[key] = response.bodyBytes;
          }
        } catch (_) {
          // Skip documents that fail to download — the label/date still
          // appears in the PDF, just without the image.
        }
      }
    }

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildHeader(user),
        build: (context) => [
          _sectionTitle('Patient Information'),
          _patientInfoTable(user, patientRow),
          pw.SizedBox(height: 18),

          _sectionTitle('Dialysis Schedule'),
          _scheduleSection(scheduleData),
          pw.SizedBox(height: 18),

          _sectionTitle('Blood Pressure History'),
          _bpTable(bpRecords),
          pw.SizedBox(height: 18),

          _sectionTitle('Weight History'),
          _weightTable(weightRecords),
          pw.SizedBox(height: 18),

          _sectionTitle('Water Intake History'),
          _waterTable(waterRecords),
          pw.SizedBox(height: 18),

          _sectionTitle('Submitted Medical Documents'),
          if (documentsRow == null)
            pw.Text(
              'No medical documents on file.',
              style: pw.TextStyle(color: _mutedColor, fontSize: 10),
            )
          else ...[
            pw.Text(
              'Submitted on: ${_formatDate(documentsRow['uploaded_at']?.toString())}',
              style: pw.TextStyle(
                color: _mutedColor,
                fontSize: 10,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.SizedBox(height: 10),
            ..._documentEntries(documentsRow, documentImages),
          ],
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildHeader(UserModel user) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'CureNurture — My Health Data',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: _brandColor,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Generated on ${DateFormat('MMMM d, yyyy, h:mm a').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 9, color: _mutedColor),
        ),
        pw.Divider(color: _brandColor, thickness: 1),
      ],
    );
  }

  pw.Widget _sectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: _brandColor,
        ),
      ),
    );
  }

  pw.Widget _patientInfoTable(UserModel user, Map<String, dynamic>? patient) {
    final rows = <List<String>>[
      ['Full Name', user.fullName],
      ['Email', user.email],
      ['Phone', user.phone ?? '—'],
      ['Home Address', patient?['home_address']?.toString() ?? '—'],
      ['Blood Type', patient?['blood_type']?.toString() ?? '—'],
      ['Dialysis Stage', patient?['dialysis_stage']?.toString() ?? '—'],
    ];

    return _keyValueTable(rows);
  }

  pw.Widget _scheduleSection(Map<String, dynamic>? scheduleData) {
    final weeklySchedule =
        scheduleData?['weekly_schedule'] as Map<String, dynamic>?;
    final scheduledDays = weeklySchedule?['scheduled_days'];

    String daysText = 'No schedule assigned yet.';
    if (scheduledDays is List && scheduledDays.isNotEmpty) {
      daysText = scheduledDays.map((d) => d.toString()).join(', ');
    } else if (scheduledDays is String && scheduledDays.isNotEmpty) {
      daysText = scheduledDays;
    }

    return pw.Text(
      'Scheduled dialysis days: $daysText',
      style: const pw.TextStyle(fontSize: 10),
    );
  }

  pw.Widget _bpTable(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return pw.Text(
        'No blood pressure records yet.',
        style: pw.TextStyle(color: _mutedColor, fontSize: 10),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: ['Date', 'Systolic/Diastolic (mmHg)', 'Notes'],
      data: records.map((r) {
        return [
          _formatDate(r['session_date']?.toString()),
          '${r['systolic'] ?? '--'}/${r['diastolic'] ?? '--'}',
          r['notes']?.toString() ?? '',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(color: _brandColor),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellHeight: 22,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.4),
        1: const pw.FlexColumnWidth(1.6),
        2: const pw.FlexColumnWidth(2),
      },
    );
  }

  pw.Widget _weightTable(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return pw.Text(
        'No weight records yet.',
        style: pw.TextStyle(color: _mutedColor, fontSize: 10),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: ['Date', 'Before (kg)', 'After (kg)', 'Removed (kg)', 'Notes'],
      data: records.map((r) {
        final before = double.tryParse(r['before_weight'].toString()) ?? 0;
        final after = double.tryParse(r['after_weight'].toString()) ?? 0;
        return [
          _formatDate(r['session_date']?.toString()),
          before.toStringAsFixed(1),
          after.toStringAsFixed(1),
          (before - after).toStringAsFixed(1),
          r['notes']?.toString() ?? '',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(color: _brandColor),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellHeight: 22,
    );
  }

  pw.Widget _waterTable(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return pw.Text(
        'No water intake records yet.',
        style: pw.TextStyle(color: _mutedColor, fontSize: 10),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: ['Date', 'Amount (mL)', 'Notes'],
      data: records.map((r) {
        return [
          _formatDate(r['log_date']?.toString()),
          r['amount_ml']?.toString() ?? '0',
          r['notes']?.toString() ?? '',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(color: _brandColor),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellHeight: 22,
    );
  }

  List<pw.Widget> _documentEntries(
    Map<String, dynamic> documentsRow,
    Map<String, Uint8List> images,
  ) {
    final widgets = <pw.Widget>[];

    for (final entry in MedicalDocumentService.documentLabels.entries) {
      final url = documentsRow[entry.key]?.toString();
      if (url == null || url.isEmpty) continue;

      final imageBytes = images[entry.key];

      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                entry.value,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              if (imageBytes != null)
                pw.Image(
                  pw.MemoryImage(imageBytes),
                  height: 160,
                  fit: pw.BoxFit.contain,
                )
              else
                pw.Text(
                  'Image unavailable.',
                  style: pw.TextStyle(color: _mutedColor, fontSize: 9),
                ),
            ],
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      widgets.add(
        pw.Text(
          'No medical documents on file.',
          style: pw.TextStyle(color: _mutedColor, fontSize: 10),
        ),
      );
    }

    return widgets;
  }

  pw.Widget _keyValueTable(List<List<String>> rows) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2.5),
      },
      children: rows.map((row) {
        return pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(
                row[0],
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _mutedColor,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(row[1], style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        );
      }).toList(),
    );
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '—';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return DateFormat('MMM d, yyyy').format(parsed);
  }
}
