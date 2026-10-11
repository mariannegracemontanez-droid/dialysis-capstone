import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/signup_data.dart';
import '../../services/auth/auth_service.dart';
import '../../services/file_upload_service.dart';
import '../../services/medical_document_service.dart';
import '../../widgets/document_preview.dart';
import '../../utils/error_message.dart';

class ClinicInfoArguments {
  final SignupData signupData;
  final Map<String, dynamic> clinic;

  ClinicInfoArguments({required this.signupData, required this.clinic});
}

/// Step 3 of 3: review the selected clinic and upload the medical documents
/// it requires.
class ClinicInfoPage extends StatefulWidget {
  final ClinicInfoArguments arguments;

  const ClinicInfoPage({super.key, required this.arguments});

  @override
  State<ClinicInfoPage> createState() => _ClinicInfoPageState();
}

class _ClinicInfoPageState extends State<ClinicInfoPage> {
  final FileUploadService _fileUploadService = FileUploadService();
  late SignupData _signupData;
  final Map<String, String> _documentUrls = {};
  final Map<String, bool> _isUploading = {};
  String? _errorMessage;

  List<String> get _clinicRequirements {
    final requirements = widget.arguments.clinic['requirements'];

    if (requirements is List) {
      final items = requirements
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();

      return items.isEmpty ? ['Bring valid ID and referral documents'] : items;
    }

    if (requirements is String && requirements.trim().isNotEmpty) {
      return requirements
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    return ['Bring valid ID and referral documents'];
  }

  /// Upload slots for the clinic's requirements, as {key, label}.
  List<Map<String, String>> get _requirementSlots {
    return _signupData.clinicRequirements.map((label) {
      return {
        'key': MedicalDocumentService.columnForRequirement(label),
        'label': label,
      };
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _signupData = widget.arguments.signupData.copyWith(
      clinicRequirements: _clinicRequirements,
    );
    _documentUrls.addAll(_signupData.documentUrls);
  }

  /// Going back hands the application (if one was started) to Step 2 so
  /// choosing this clinic again reuses it.
  void _popWithProgress() {
    Navigator.of(
      context,
    ).pop(_signupData.copyWith(documentUrls: Map.of(_documentUrls)));
  }

  /// The `patients` application row is needed before the first upload (the
  /// storage path is keyed by it). It is created lazily so just viewing
  /// this step doesn't leave an application behind.
  Future<String> _ensurePatientApplication() async {
    if (_signupData.patientId.isNotEmpty) return _signupData.patientId;

    if (_signupData.profileId.isEmpty) {
      throw Exception(
        'Unable to create application without a valid patient account.',
      );
    }

    final patientId = await AuthService().createPatientRecord(
      profileId: _signupData.profileId,
      clinicId: _signupData.clinicId,
      details: _signupData.toPatientApplicationColumns(),
    );
    _signupData = _signupData.copyWith(patientId: patientId);
    return patientId;
  }

  Future<void> _showSourceChooser(String requirementKey) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt_outlined,
                    color: Color(0xFF2C5F7D),
                  ),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFF2C5F7D),
                  ),
                  title: const Text('Choose from gallery'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;
    await _pickDocumentFor(requirementKey, source);
  }

  Future<void> _pickDocumentFor(
    String requirementKey,
    ImageSource source,
  ) async {
    setState(() {
      _isUploading[requirementKey] = true;
      _errorMessage = null;
    });

    try {
      final XFile? file = await _fileUploadService.pickImage(source: source);

      if (file == null) {
        setState(() {
          _isUploading[requirementKey] = false;
          _errorMessage = source == ImageSource.camera
              ? 'No photo was taken.'
              : 'No file selected.';
        });
        return;
      }

      final patientId = await _ensurePatientApplication();

      final url = await _fileUploadService.uploadMedicalDocumentImage(
        imageFile: file,
        patientId: patientId,
        clinicId: _signupData.clinicId,
      );

      setState(() {
        _documentUrls[requirementKey] = url;
        _isUploading[requirementKey] = false;
        _errorMessage = null;
      });
    } catch (e, stack) {
      final message = e.toString().toLowerCase();
      final isPermissionIssue =
          message.contains('camera_access_denied') ||
          message.contains('photo_access_denied') ||
          message.contains('permission');

      setState(() {
        _isUploading[requirementKey] = false;
        _errorMessage = isPermissionIssue
            ? 'Camera access was denied. Please allow camera access in your '
                  'phone settings to take a photo.'
            : friendlyError(e);
      });
      debugPrint('Error uploading document: $e');
      debugPrint(stack.toString());
    }
  }

  /// Uploaded documents in requirement order, each file listed once (two
  /// requirements can share a document column).
  List<DocumentPreviewItem> get _uploadedPreviews {
    final seenUrls = <String>{};
    final previews = <DocumentPreviewItem>[];
    for (final slot in _requirementSlots) {
      final url = _documentUrls[slot['key']];
      if (url != null && url.isNotEmpty && seenUrls.add(url)) {
        previews.add(DocumentPreviewItem(label: slot['label']!, url: url));
      }
    }
    return previews;
  }

  void _viewDocument(String requirementKey) {
    final previews = _uploadedPreviews;
    final url = _documentUrls[requirementKey];
    final index = previews.indexWhere((item) => item.url == url);
    if (index < 0) return;
    showDocumentPreview(context, documents: previews, initialIndex: index);
  }

  void _handleNext() {
    final requirementSlots = _requirementSlots;
    final uploadedCount = requirementSlots
        .where((item) => _documentUrls[item['key']]?.isNotEmpty ?? false)
        .length;
    final requiredCount = requirementSlots.length >= 5
        ? 5
        : requirementSlots.length;

    if (requirementSlots.isNotEmpty && uploadedCount < requiredCount) {
      setState(() {
        final remaining = requiredCount - uploadedCount;
        _errorMessage = remaining == 1
            ? 'Please upload the remaining document before continuing.'
            : 'Please upload $remaining more required documents before continuing.';
      });
      return;
    }

    final updated = _signupData.copyWith(documentUrls: Map.of(_documentUrls));
    Navigator.of(context).pushNamed('/confirm-info', arguments: updated);
  }

  @override
  Widget build(BuildContext context) {
    final clinic = widget.arguments.clinic;
    final requirementSlots = _requirementSlots;
    final uploadedCount = requirementSlots
        .where((item) => _documentUrls[item['key']]?.isNotEmpty ?? false)
        .length;
    final isAnyUploading = _isUploading.values.any((uploading) => uploading);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithProgress();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F7FA),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _popWithProgress,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: Color(0xFF2C5F7D),
                      ),
                    ),

                    const SizedBox(width: 4),

                    const Expanded(
                      child: Text(
                        'Clinic Information',
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
                  'Review your selected clinic and upload the medical documents it requires.',
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
                      'Step 3 of 3',
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
                        color: Colors.black.withValues(alpha: 0.45),
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
                    color: Color(0xFF2C5F7D),
                    backgroundColor: Color(0xFFDDEAF0),
                  ),
                ),

                const SizedBox(height: 26),

                _buildCard(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C5F7D),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.local_hospital_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clinic['name']?.toString() ?? 'Selected Clinic',
                                style: const TextStyle(
                                  color: Color(0xFF173B4F),
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),

                              const SizedBox(height: 6),

                              if (clinic['address'] != null)
                                Text(
                                  clinic['address'].toString(),
                                  style: const TextStyle(
                                    color: Color(0xFF6B7C86),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (clinic['operating_hours'] != null ||
                        clinic['contact_number'] != null) ...[
                      const SizedBox(height: 22),

                      Row(
                        children: [
                          if (clinic['operating_hours'] != null)
                            Expanded(
                              child: _buildClinicInfoItem(
                                'Operating Hours',
                                clinic['operating_hours'].toString(),
                                Icons.schedule_outlined,
                              ),
                            ),

                          if (clinic['operating_hours'] != null &&
                              clinic['contact_number'] != null)
                            const SizedBox(width: 14),

                          if (clinic['contact_number'] != null)
                            Expanded(
                              child: _buildClinicInfoItem(
                                'Contact',
                                clinic['contact_number'].toString(),
                                Icons.phone_outlined,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 22),

                _buildCard(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  children: [
                    const Text(
                      'Medical Documents',
                      style: TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Upload the documents required by this clinic. Take a photo or choose one from your gallery — files are uploaded securely.',
                      style: TextStyle(
                        color: Color(0xFF7A8A94),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F8FA),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE3EDF2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.folder_copy_outlined,
                            color: Color(0xFF2C5F7D),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Uploaded: $uploadedCount / ${requirementSlots.length}',
                              style: const TextStyle(
                                color: Color(0xFF173B4F),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    const Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: Color(0xFF2C5F7D),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Required Documents',
                          style: TextStyle(
                            color: Color(0xFF173B4F),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    if (requirementSlots.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F8FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE3EDF2)),
                        ),
                        child: const Text(
                          'This clinic has not listed any required documents. You may continue.',
                          style: TextStyle(
                            color: Color(0xFF5B6D7D),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      )
                    else
                      ...requirementSlots.map((item) {
                        final key = item['key']!;
                        final label = item['label']!;
                        final documentUrl = _documentUrls[key];
                        final uploaded = documentUrl?.isNotEmpty ?? false;
                        final uploading = _isUploading[key] == true;

                        return _buildRequirementRow(
                          label: label,
                          documentUrl: uploaded ? documentUrl : null,
                          uploading: uploading,
                          onUpload: () => _showSourceChooser(key),
                          onView: uploaded ? () => _viewDocument(key) : null,
                        );
                      }),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.20),
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

                    const SizedBox(height: 28),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: isAnyUploading ? null : _handleNext,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xFF2C5F7D),
                          disabledBackgroundColor: const Color(
                            0xFF2C5F7D,
                          ).withValues(alpha: 0.55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'REVIEW APPLICATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
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
  }

  Widget _buildCard({
    required EdgeInsets padding,
    required List<Widget> children,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildClinicInfoItem(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EDF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2C5F7D)),

          const SizedBox(height: 10),

          Text(
            title,
            style: const TextStyle(color: Color(0xFF7A8A94), fontSize: 12),
          ),

          const SizedBox(height: 4),

          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF173B4F),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementRow({
    required String label,
    required String? documentUrl,
    required bool uploading,
    required VoidCallback onUpload,
    VoidCallback? onView,
  }) {
    final uploaded = documentUrl != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: uploaded ? const Color(0xFFF0F8F5) : const Color(0xFFF4F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: uploaded ? const Color(0xFFBFE5D2) : const Color(0xFFE3EDF2),
        ),
      ),
      child: Row(
        children: [
          if (uploaded)
            GestureDetector(
              onTap: onView,
              child: DocumentThumbnail(url: documentUrl, size: 44),
            )
          else
            const Icon(
              Icons.upload_file_outlined,
              color: Color(0xFF2C5F7D),
              size: 22,
            ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (uploaded) ...[
                  const SizedBox(height: 2),
                  const Text(
                    'Uploaded',
                    style: TextStyle(
                      color: Color(0xFF2A9D65),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          if (onView != null) ...[
            SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: onView,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2A9D65)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View',
                  style: TextStyle(
                    color: Color(0xFF2A9D65),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: uploading ? null : onUpload,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: uploaded
                    ? const Color(0xFF2A9D65)
                    : const Color(0xFF2C5F7D),
                disabledBackgroundColor: const Color(
                  0xFF2C5F7D,
                ).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      uploaded ? 'Replace' : 'Upload',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
