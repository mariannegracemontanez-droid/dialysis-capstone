import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/signup_data.dart';
import '../../services/file_upload_service.dart';

class MedicalDocumentsPage extends StatefulWidget {
  final SignupData signupData;

  const MedicalDocumentsPage({super.key, required this.signupData});

  @override
  State<MedicalDocumentsPage> createState() => _MedicalDocumentsPageState();
}

class _MedicalDocumentsPageState extends State<MedicalDocumentsPage> {
  final FileUploadService _fileUploadService = FileUploadService();
  final TextEditingController _referralController = TextEditingController();
  final List<XFile> _selectedDocuments = [];
  final List<Uint8List> _selectedDocumentBytes = [];
  bool _isPicking = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _referralController.text = widget.signupData.referralDoctor;
  }

  @override
  void dispose() {
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    setState(() {
      _isPicking = true;
      _uploadError = null;
    });

    try {
      final files = await _fileUploadService.pickImages();
      if (files != null && files.isNotEmpty) {
        final bytesList = await Future.wait(
          files.map((file) => file.readAsBytes()),
        );
        setState(() {
          _selectedDocuments
            ..clear()
            ..addAll(files);
          _selectedDocumentBytes
            ..clear()
            ..addAll(bytesList);
        });
      }
    } catch (e) {
      setState(() {
        _uploadError = 'Could not pick documents. Try again.';
      });
    } finally {
      setState(() {
        _isPicking = false;
      });
    }
  }

  void _handleNext() {
    final updated = widget.signupData.copyWith(
      medicalDocumentPath: _selectedDocuments.isNotEmpty
          ? _selectedDocuments.first.path
          : widget.signupData.medicalDocumentPath,
      medicalDocumentPaths: _selectedDocuments
          .map((document) => document.path)
          .toList(),
      referralDoctor: _referralController.text.trim(),
    );
    Navigator.of(context).pushNamed('/financial', arguments: updated);
  }

  @override
  Widget build(BuildContext context) {
    final fileCount = _selectedDocuments.length;
    final fileName = fileCount == 0
        ? 'No documents uploaded'
        : '$fileCount document${fileCount == 1 ? '' : 's'} selected';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF2C5F7D),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Your medical background',
                    style: TextStyle(
                      color: Color(0xFF2C5F7D),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: 0.83,
                color: const Color(0xFF2C5F7D),
                backgroundColor: const Color(0xFFE7F0F3),
                minHeight: 8,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Do you have existing medical records?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Upload medical reports or referral notes from your hospital or doctor.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 160,
                            child: InkWell(
                              onTap: _isPicking ? null : _pickDocument,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6FAFF),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFD8E7F6),
                                  ),
                                ),
                                child: Center(
                                  child: _selectedDocumentBytes.isEmpty
                                      ? _buildUploadPrompt()
                                      : GridView.builder(
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          padding: const EdgeInsets.all(8),
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: 3,
                                                crossAxisSpacing: 8,
                                                mainAxisSpacing: 8,
                                              ),
                                          itemCount:
                                              _selectedDocumentBytes.length,
                                          itemBuilder: (context, index) {
                                            return ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.memory(
                                                _selectedDocumentBytes[index],
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            fileName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6C7A8E),
                            ),
                          ),
                          if (_uploadError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _uploadError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                          const SizedBox(height: 24),
                          TextField(
                            controller: _referralController,
                            decoration: InputDecoration(
                              hintText: 'Enter name of the hospital/doctor',
                              filled: true,
                              fillColor: const Color(0xFFF7FBFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'This information helps us locate the right dialysis support network for you.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _handleNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C5F7D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadPrompt() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _isPicking ? Icons.cloud_upload : Icons.upload_file,
          color: const Color(0xFF2C5F7D),
          size: 36,
        ),
        const SizedBox(height: 10),
        Text(
          _isPicking ? 'Uploading...' : 'Tap to upload medical documents',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF4A637B)),
        ),
      ],
    );
  }
}
