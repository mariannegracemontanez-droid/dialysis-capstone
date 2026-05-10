import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/profile_update_service.dart';

class MedicalInfoPage extends StatefulWidget {
  final UserModel? user;

  const MedicalInfoPage({super.key, this.user});

  @override
  State<MedicalInfoPage> createState() => _MedicalInfoPageState();
}

class _MedicalInfoPageState extends State<MedicalInfoPage> {
  late TextEditingController _bloodTypeController;
  late TextEditingController _weightController;
  late TextEditingController _heightController;
  late TextEditingController _lastDialysisController;

  final ProfileUpdateService _profileService = ProfileUpdateService();

  bool _isSaving = false;
  String? _saveMessage;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _bloodTypeController = TextEditingController(
      text: widget.user?.bloodType ?? '',
    );
    _weightController = TextEditingController(
      text: widget.user?.weight?.toString() ?? '',
    );
    _heightController = TextEditingController(
      text: widget.user?.height?.toString() ?? '',
    );
    _lastDialysisController = TextEditingController(
      text: widget.user?.lastDialysisDate != null
          ? '${widget.user!.lastDialysisDate!.year}-${widget.user!.lastDialysisDate!.month.toString().padLeft(2, '0')}-${widget.user!.lastDialysisDate!.day.toString().padLeft(2, '0')}'
          : '',
    );

    _bloodTypeController.addListener(_scheduleSave);
    _weightController.addListener(_scheduleSave);
    _heightController.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    if (_isSaving) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), _saveChanges);
  }

  Future<void> _pickDialysisDate() async {
    final initialDate = widget.user?.lastDialysisDate ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      _lastDialysisController.text =
          '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
      _scheduleSave();
    }
  }

  Future<void> _saveChanges() async {
    if (widget.user == null) return;

    setState(() => _isSaving = true);

    try {
      double? weight;
      if (_weightController.text.isNotEmpty) {
        weight = double.tryParse(_weightController.text);
      }

      double? height;
      if (_heightController.text.isNotEmpty) {
        height = double.tryParse(_heightController.text);
      }

      DateTime? lastDialysisDate;
      if (_lastDialysisController.text.isNotEmpty) {
        lastDialysisDate = DateTime.tryParse(_lastDialysisController.text);
      }

      await _profileService.updateMedicalInfo(
        userId: widget.user!.id,
        bloodType: _bloodTypeController.text.isEmpty
            ? null
            : _bloodTypeController.text,
        weight: weight,
        height: height,
        lastDialysisDate: lastDialysisDate,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _saveMessage = 'Medical information saved';
      });

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() => _saveMessage = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveMessage = 'Failed to save: $e';
      });
    }
  }

  @override
  void dispose() {
    _bloodTypeController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _lastDialysisController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C5F7D),
        title: const Text('Medical Information'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update your medical information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_saveMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _saveMessage!.startsWith('Failed')
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _saveMessage!.startsWith('Failed')
                          ? Colors.red
                          : Colors.green,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _saveMessage!.startsWith('Failed')
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: _saveMessage!.startsWith('Failed')
                            ? Colors.red
                            : Colors.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _saveMessage!,
                          style: TextStyle(
                            color: _saveMessage!.startsWith('Failed')
                                ? Colors.red
                                : Colors.green,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              _buildField(
                'Blood Type',
                _bloodTypeController,
                hint: 'e.g., O+, A-, B+',
              ),
              const SizedBox(height: 16),
              _buildField(
                'Weight (kg)',
                _weightController,
                hint: 'e.g., 70.5',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildField(
                'Height (cm)',
                _heightController,
                hint: 'e.g., 175',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildDateField('Last Dialysis Date', _lastDialysisController),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF6F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFF2C5F7D),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Changes are saved automatically when you edit',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2C5F7D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C9B9E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

  Widget _buildField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint ?? 'Enter $label',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDialysisDate,
          child: AbsorbPointer(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Select a date',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: const Icon(Icons.calendar_today),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
