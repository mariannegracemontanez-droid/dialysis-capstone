import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/medical_document_service.dart';
import '../../utils/patient_name.dart';
import '../../widgets/document_preview.dart';

/// One clinic application on the Pending Account page. Collapsed it shows
/// the clinic and status; expanded it shows the clinic's details, its
/// document requirements, and exactly what was submitted to that clinic.
///
/// [application] is a row from `PatientService.getPendingApplications`:
/// the `patients` row (the per-clinic snapshot) plus `clinic` and
/// `documents`.
class PendingApplicationCard extends StatefulWidget {
  final Map<String, dynamic> application;

  const PendingApplicationCard({super.key, required this.application});

  @override
  State<PendingApplicationCard> createState() => _PendingApplicationCardState();
}

class _PendingApplicationCardState extends State<PendingApplicationCard> {
  static const _ink = Color(0xFF173B4F);
  static const _muted = Color(0xFF5B6D7D);
  static const _teal = Color(0xFF225E72);
  static const _border = Color(0xFFE1EAF0);

  bool _expanded = false;

  Map<String, dynamic> get _application => widget.application;

  Map<String, dynamic> get _clinic {
    final clinic = _application['clinic'];
    return clinic is Map ? Map<String, dynamic>.from(clinic) : const {};
  }

  Map<String, dynamic>? get _documents {
    final documents = _application['documents'];
    return documents is Map ? Map<String, dynamic>.from(documents) : null;
  }

  String _text(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  List<String> get _requirements {
    final requirements = _clinic['requirements'];
    final items = requirements is List
        ? requirements.map((item) => item?.toString() ?? '')
        : (requirements?.toString() ?? '').split(',');
    return items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final clinicName = _application['clinic_name']?.toString() ?? 'Clinic';
    final address = _text(_clinic, 'address');
    final rawStatus =
        _application['status']?.toString().toLowerCase().trim() ?? 'pending';
    final isDeclined = rawStatus == 'declined';
    final declineReason = _text(_application, 'decline_reason');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDeclined ? const Color(0xFFFECACA) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: isDeclined
                          ? const Color(0xFFFFE4E6)
                          : const Color(0xFFEAF4F7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isDeclined
                          ? Icons.cancel_outlined
                          : Icons.local_hospital_outlined,
                      color: isDeclined ? const Color(0xFFB91C1C) : _teal,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clinicName,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 1),
                                child: Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: _muted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  address,
                                  maxLines: _expanded ? null : 2,
                                  overflow: _expanded
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        _buildStatusChip(rawStatus, isDeclined),
                        if (isDeclined && declineReason.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                            child: Text(
                              'Reason: $declineReason',
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: _teal,
                      semanticLabel: _expanded
                          ? 'Hide application details'
                          : 'Show application details',
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _buildExpandedDetails(isDeclined)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String rawStatus, bool isDeclined) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDeclined ? const Color(0xFFFFE4E6) : const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        rawStatus.toUpperCase(),
        style: TextStyle(
          color: isDeclined ? const Color(0xFFB91C1C) : const Color(0xFF8A6200),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildExpandedDetails(bool isDeclined) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isDeclined
                ? 'Your application was declined by this center.'
                : 'Please wait for the clinic to review your request. You will gain access once approved.',
            style: TextStyle(
              color: isDeclined ? const Color(0xFF991B1B) : _muted,
              fontSize: 12.5,
              height: 1.4,
              fontWeight: isDeclined ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          const Divider(height: 28, color: _border),
          _buildClinicInformation(),
          const Divider(height: 28, color: _border),
          _buildDocumentsNeeded(),
          const Divider(height: 28, color: _border),
          _buildReviewDetails(),
          const Divider(height: 28, color: _border),
          _buildUploadedDocuments(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              style: const TextStyle(
                color: _ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyNote(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EDF2)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
      ),
    );
  }

  Widget _buildClinicInformation() {
    final clinic = _clinic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(Icons.local_hospital_outlined, 'Clinic Information'),
        if (clinic.isEmpty)
          _buildEmptyNote('Clinic details are unavailable right now.')
        else ...[
          _buildDetailRow(
            'Clinic name',
            _application['clinic_name']?.toString() ?? '',
          ),
          _buildDetailRow('Address', _text(clinic, 'address')),
          if (_text(clinic, 'operating_hours').isNotEmpty)
            _buildDetailRow(
              'Operating hours',
              _text(clinic, 'operating_hours'),
            ),
          if (_text(clinic, 'contact_number').isNotEmpty)
            _buildDetailRow('Contact', _text(clinic, 'contact_number')),
        ],
      ],
    );
  }

  Widget _buildDocumentsNeeded() {
    final requirements = _requirements;
    final documents = _documents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(Icons.description_outlined, 'Documents Needed'),
        if (requirements.isEmpty)
          _buildEmptyNote(
            'This clinic has not listed any document requirements.',
          )
        else
          ...requirements.map((requirement) {
            final column = MedicalDocumentService.columnForRequirement(
              requirement,
            );
            final submitted = (documents?[column]?.toString() ?? '').isNotEmpty;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    submitted
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: submitted
                        ? const Color(0xFF2A9D65)
                        : const Color(0xFF9AA8B2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      requirement,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    submitted ? 'Submitted' : 'Not submitted',
                    style: TextStyle(
                      color: submitted
                          ? const Color(0xFF2A9D65)
                          : const Color(0xFF8A6200),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  String _formatDate(String value, String pattern) {
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? value
        : DateFormat(pattern).format(parsed.toLocal());
  }

  Widget _buildReviewDetails() {
    // Everything here comes from this application's own row, i.e. what was
    // submitted to this clinic, not the current profile.
    final row = _application;
    final name = PatientName.fromRow(row);
    final contactName = _text(row, 'emergency_contact_name');
    final contactNumber = _text(row, 'emergency_contact_number');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(Icons.verified_user_outlined, 'Review Details'),
        _buildDetailRow('Patient name', name.displayName),
        if (name.hasComponents) ...[
          _buildDetailRow('First name', name.firstName),
          _buildDetailRow('Middle name', name.middleName ?? 'No middle name'),
          _buildDetailRow('Last name', name.lastName),
        ] else
          _buildDetailRow(
            'Name parts',
            'Submitted before names were stored separately',
          ),
        _buildDetailRow('Email', _text(row, 'email')),
        _buildDetailRow('Phone', _text(row, 'phone')),
        _buildDetailRow(
          'Date of birth',
          _formatDate(_text(row, 'date_of_birth'), 'MMM d, yyyy'),
        ),
        _buildDetailRow('Home address', _text(row, 'home_address')),
        _buildDetailRow('Blood type', _text(row, 'blood_type')),
        _buildDetailRow(
          'Emergency contact',
          [
            contactName,
            contactNumber,
          ].where((part) => part.isNotEmpty).join(' · '),
        ),
        _buildDetailRow('CKD level', _text(row, 'dialysis_stage')),
        _buildDetailRow('Conditions', _text(row, 'existing_condition')),
        _buildDetailRow('Insurance', _text(row, 'insurance')),
        _buildDetailRow(
          'Submitted on',
          _formatDate(_text(row, 'created_at'), 'MMM d, yyyy • h:mm a'),
        ),
      ],
    );
  }

  Widget _buildUploadedDocuments() {
    final uploaded = MedicalDocumentService.uploadedDocuments(_documents)
        .map(
          (entry) => DocumentPreviewItem(
            label:
                MedicalDocumentService.documentLabels[entry.key] ?? entry.key,
            url: entry.value,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          Icons.photo_library_outlined,
          'Uploaded Medical Documents',
        ),
        if (uploaded.isEmpty)
          _buildEmptyNote(
            'No uploaded documents were found for this application.',
          )
        else
          DocumentGallery(documents: uploaded),
      ],
    );
  }
}
