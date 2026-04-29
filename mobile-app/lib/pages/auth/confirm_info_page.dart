import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import '../../services/auth/auth_service.dart';

class ConfirmInfoPage extends StatefulWidget {
  final SignupData signupData;

  const ConfirmInfoPage({super.key, required this.signupData});

  @override
  State<ConfirmInfoPage> createState() => _ConfirmInfoPageState();
}

class _ConfirmInfoPageState extends State<ConfirmInfoPage> {
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _handleCreateAccount() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await AuthService().signUp(
        email: widget.signupData.email,
        password: widget.signupData.password,
        fullName: widget.signupData.fullName,
      );

      if (mounted) {
        await AuthService().signOut();
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insuranceLabel = widget.signupData.insuranceOptions.isEmpty
        ? 'None'
        : widget.signupData.insuranceOptions.join(', ');

    final medicalDocumentName =
        widget.signupData.medicalDocumentPaths.isNotEmpty
        ? widget.signupData.medicalDocumentPaths
              .map((path) => path.split('/').last)
              .join(', ')
        : widget.signupData.medicalDocumentPath.isEmpty
        ? 'Not provided'
        : widget.signupData.medicalDocumentPath.split('/').last;

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
                    'Confirm Your Information',
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
                value: 1.0,
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Review your account details before creation.',
                          style: TextStyle(
                            color: Color(0xFF3B5D6C),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildInfoRow(
                          'Patient Name',
                          widget.signupData.fullName,
                        ),
                        _buildInfoRow('Email', widget.signupData.email),
                        _buildInfoRow('Phone', widget.signupData.phone),
                        _buildInfoRow('CKD Level', widget.signupData.ckdLevel),
                        _buildInfoRow(
                          'Conditions',
                          widget.signupData.conditions.isEmpty
                              ? 'None'
                              : widget.signupData.conditions.join(', '),
                        ),
                        _buildInfoRow(
                          'Location',
                          widget.signupData.locationSummary,
                        ),
                        _buildInfoRow('Medical Records', medicalDocumentName),
                        _buildInfoRow(
                          'Referred by',
                          widget.signupData.referralDoctor.isEmpty
                              ? 'Not provided'
                              : widget.signupData.referralDoctor,
                        ),
                        _buildInfoRow('Insurance', insuranceLabel),
                        _buildInfoRow(
                          'Budget range',
                          widget.signupData.budgetRange,
                        ),
                        _buildInfoRow(
                          'Preferred clinic type',
                          widget.signupData.preferredClinicType,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleCreateAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C5F7D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Create Account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6A7B83), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? 'Not provided' : value,
            style: const TextStyle(
              color: Color(0xFF1F3F53),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
