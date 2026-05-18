import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/profile_update_service.dart';

class EditProfilePage extends StatefulWidget {
  final UserModel? user;

  const EditProfilePage({super.key, this.user});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _locationController;

  final ProfileUpdateService _profileService = ProfileUpdateService();

  bool _isSaving = false;
  String? _saveMessage;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _nameController = TextEditingController(text: widget.user?.fullName ?? '');
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _phoneController = TextEditingController(text: widget.user?.phone ?? '');
    _locationController = TextEditingController(
      text: widget.user?.location ?? '',
    );
  }

  Future<bool> _saveChanges() async {
    if (widget.user == null) return false;

    setState(() => _isSaving = true);

    try {
      await _profileService.updateContactInfo(
        patientId: widget.user!.id,
        email: _emailController.text,
        fullName: _nameController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        location: _locationController.text.isEmpty
            ? null
            : _locationController.text,
      );

      if (!mounted) return false;

      setState(() {
        _isSaving = false;
        _saveMessage = 'Saved successfully';
      });

      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _saveMessage = null);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _isSaving = false;
        _saveMessage = 'Failed to save: $e';
      });
      return false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C5F7D),
        title: const Text('Edit Contact Information'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update your contact information',
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
              _buildField('Full Name', _nameController, readOnly: true),
              const SizedBox(height: 16),
              _buildField('Email Address', _emailController, readOnly: true),
              const SizedBox(height: 16),
              _buildField('Phone Number', _phoneController),
              const SizedBox(height: 16),
              _buildField('Location', _locationController),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (await _saveChanges()) {
                            if (!mounted) return;
                            Navigator.of(context).pop(true);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C9B9E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    if (await _saveChanges()) {
                      if (!mounted) return;
                      navigator.pop(true);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2C9B9E)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Done'),
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
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: readOnly,
          decoration: InputDecoration(
            hintText: readOnly ? null : 'Enter $label',
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
}
