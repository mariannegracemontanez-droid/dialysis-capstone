import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import '../../services/auth/auth_service.dart';
import '../../services/medical_document_service.dart';
import '../../services/patient_service.dart';
import '../../widgets/document_preview.dart';
import '../../utils/error_message.dart';

class ConfirmInfoPage extends StatefulWidget {
  final SignupData signupData;

  const ConfirmInfoPage({super.key, required this.signupData});

  @override
  State<ConfirmInfoPage> createState() => _ConfirmInfoPageState();
}

class _ConfirmInfoPageState extends State<ConfirmInfoPage> {
  bool _isSubmitting = false;
  String? _errorMessage;
  // Set once this page creates the application, so a retry after a later
  // failure updates that row instead of trying to create a duplicate.
  String? _createdPatientId;

  Future<void> _handleSubmit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final profileId = widget.signupData.profileId;
      if (profileId.isEmpty) {
        throw Exception(
          'Internal error: missing profile ID for patient application.',
        );
      }

      final signupData = widget.signupData;
      final details = signupData.toPatientApplicationColumns();
      var patientId = _createdPatientId ?? signupData.patientId;
      if (patientId.isEmpty) {
        patientId = await AuthService().createPatientRecord(
          profileId: profileId,
          clinicId: signupData.clinicId,
          details: details,
        );
        _createdPatientId = patientId;
      } else {
        await PatientService().updatePatientApplication(
          patientId: patientId,
          updates: details,
        );
      }

      // Keep the account profile's name in step with what was submitted.
      await PatientService().updateProfileName(
        profileId: profileId,
        name: signupData.name,
      );

      if (widget.signupData.documentUrls.isNotEmpty) {
        await MedicalDocumentService().saveDocumentUrls(
          patientId: patientId,
          clinicId: widget.signupData.clinicId,
          documentUrls: widget.signupData.documentUrls,
        );
      }

      if (mounted) {
        final isAdditionalClinicFlow = widget.signupData.password.isEmpty;

        Navigator.of(context).pushReplacementNamed(
          isAdditionalClinicFlow
              ? '/application_complete'
              : '/signup-complete_page',
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = friendlyError(e);
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  /// Uploaded documents in requirement order. Two requirements can map to
  /// the same document column, so each file is listed once.
  List<DocumentPreviewItem> get _uploadedDocuments {
    final documentUrls = widget.signupData.documentUrls;
    final seenUrls = <String>{};
    final documents = <DocumentPreviewItem>[];
    for (final label in widget.signupData.clinicRequirements) {
      final url =
          documentUrls[MedicalDocumentService.columnForRequirement(label)];
      if (url != null && url.isNotEmpty && seenUrls.add(url)) {
        documents.add(DocumentPreviewItem(label: label, url: url));
      }
    }
    return documents;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.signupData.name;
    final uploadedDocuments = _uploadedDocuments;
    final insuranceLabel = widget.signupData.insuranceOptions.isEmpty
        ? 'None'
        : widget.signupData.insuranceOptions.join(', ');

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: Color(0xFF2C5F7D),
                    ),
                  ),

                  const SizedBox(width: 4),

                  const Expanded(
                    child: Text(
                      'Confirm Information',
                      style: TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Text(
                'Please review all information before submitting your application.',
                style: TextStyle(
                  color: Color(0xFF6B7C86),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 22),

              Row(
                children: [
                  const Text(
                    'Final Review',
                    style: TextStyle(
                      color: Color(0xFF2C5F7D),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '100%',
                    style: TextStyle(
                      color: const Color.fromARGB(
                        255,
                        24,
                        138,
                        28,
                      ).withOpacity(0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const LinearProgressIndicator(
                  value: 1,
                  minHeight: 8,
                  color: Color.fromARGB(255, 56, 224, 58),
                  backgroundColor: Color(0xFFDDEAF0),
                ),
              ),

              const SizedBox(height: 24),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE1EAF0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              color: Color(0xFF2C5F7D),
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Review Details',
                              style: TextStyle(
                                color: Color(0xFF173B4F),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'Make sure your information is correct before continuing.',
                          style: TextStyle(
                            color: Color(0xFF7A8A94),
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 24),

                        _buildInfoRow(
                          icon: Icons.person_outline,
                          label: 'Patient Name',
                          value: name.displayName,
                        ),

                        _buildInfoRow(
                          icon: Icons.badge_outlined,
                          label: 'First Name · Middle Name · Last Name',
                          value:
                              '${name.firstName} · '
                              '${name.middleName ?? 'No middle name'} · '
                              '${name.lastName}',
                        ),

                        _buildInfoRow(
                          icon: Icons.alternate_email,
                          label: 'Email',
                          value: widget.signupData.email,
                        ),

                        _buildInfoRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone Number',
                          value: widget.signupData.phone,
                        ),

                        _buildInfoRow(
                          icon: Icons.calendar_month_outlined,
                          label: 'Date of Birth',
                          value: widget.signupData.dateOfBirth,
                        ),

                        _buildInfoRow(
                          icon: Icons.home_outlined,
                          label: 'Home Address',
                          value: widget.signupData.composedHomeAddress,
                        ),

                        _buildInfoRow(
                          icon: Icons.bloodtype_outlined,
                          label: 'Blood Type',
                          value: widget.signupData.bloodType,
                        ),

                        _buildInfoRow(
                          icon: Icons.emergency_outlined,
                          label: 'Emergency Contact',
                          value: widget.signupData.emergencyContactName.isEmpty
                              ? 'Not provided'
                              : '${widget.signupData.composedEmergencyContactName} · ${widget.signupData.emergencyContactNumber}',
                        ),

                        _buildInfoRow(
                          icon: Icons.local_hospital_outlined,
                          label: 'Selected Clinic',
                          value: widget.signupData.clinicName.isEmpty
                              ? 'Not selected'
                              : widget.signupData.clinicName,
                        ),

                        _buildInfoRow(
                          icon: Icons.monitor_heart_outlined,
                          label: 'CKD Level',
                          value: widget.signupData.ckdLevel,
                        ),

                        _buildInfoRow(
                          icon: Icons.medical_information_outlined,
                          label: 'Conditions',
                          value: widget.signupData.conditions.isEmpty
                              ? 'None'
                              : widget.signupData.conditions.join(', '),
                        ),

                        _buildInfoRow(
                          icon: Icons.health_and_safety_outlined,
                          label: 'Insurance',
                          value: insuranceLabel,
                        ),

                        _buildInfoRow(
                          icon: Icons.business_outlined,
                          label: 'Preferred Clinic Type',
                          value: widget.signupData.preferredClinicType,
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Uploaded Medical Documents '
                          '(${uploadedDocuments.length})',
                          style: const TextStyle(
                            color: Color(0xFF173B4F),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 4),

                        const Text(
                          'Tap a document to check it before submitting.',
                          style: TextStyle(
                            color: Color(0xFF7A8A94),
                            fontSize: 12.5,
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (uploadedDocuments.isEmpty)
                          const Text(
                            'No documents uploaded.',
                            style: TextStyle(
                              color: Color(0xFF5B6D7D),
                              fontSize: 13,
                            ),
                          )
                        else
                          DocumentGallery(documents: uploadedDocuments),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 18),

                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.20),
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF2C5F7D),
                    disabledBackgroundColor: const Color(
                      0xFF2C5F7D,
                    ).withOpacity(0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Text(
                          'SUBMIT APPLICATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EDF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2C5F7D), size: 20),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF7A8A94),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  value.isEmpty ? 'Not provided' : value,
                  style: const TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
