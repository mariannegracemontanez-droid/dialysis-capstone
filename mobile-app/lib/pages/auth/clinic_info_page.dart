import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/signup_data.dart';
import '../../services/auth/auth_service.dart';
import '../../utils/form_options.dart';
import '../../utils/validators.dart';

class ClinicInfoArguments {
  final SignupData signupData;
  final Map<String, dynamic> clinic;

  ClinicInfoArguments({required this.signupData, required this.clinic});
}

class ClinicInfoPage extends StatefulWidget {
  final ClinicInfoArguments arguments;

  const ClinicInfoPage({super.key, required this.arguments});

  @override
  State<ClinicInfoPage> createState() => _ClinicInfoPageState();
}

class _ClinicInfoPageState extends State<ClinicInfoPage> {
  late TextEditingController _dateOfBirthController;
  late TextEditingController _homeAddressController;
  late TextEditingController _bloodTypeController;
  late TextEditingController _emergencyContactNameController;
  late TextEditingController _emergencyContactNumberController;
  String _selectedStage = 'Stage 1';
  final List<String> _conditions = [
    'Diabetes',
    'Hypertension',
    'Heart Disease',
    'None',
  ];
  final List<String> _selectedConditions = [];
  String? _selectedBarangay;
  String? _selectedRelationship;
  String? _errorMessage;
  String? _addressError;
  String? _bloodTypeError;
  String? _contactNameError;
  String? _contactNumberError;
  bool _isSubmitting = false;

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

  @override
  void initState() {
    super.initState();
    _dateOfBirthController = TextEditingController(
      text: widget.arguments.signupData.dateOfBirth,
    );
    _homeAddressController = TextEditingController(
      text: widget.arguments.signupData.homeAddress,
    );
    _bloodTypeController = TextEditingController(
      text: widget.arguments.signupData.bloodType,
    );
    _emergencyContactNameController = TextEditingController(
      text: widget.arguments.signupData.emergencyContactName,
    );
    _emergencyContactNumberController = TextEditingController(
      text: widget.arguments.signupData.emergencyContactNumber,
    );
    if (widget.arguments.signupData.conditions.isNotEmpty) {
      _selectedConditions.addAll(widget.arguments.signupData.conditions);
    }
    _selectedStage = widget.arguments.signupData.ckdLevel.isNotEmpty
        ? widget.arguments.signupData.ckdLevel
        : 'Stage 3';
    _selectedBarangay = widget.arguments.signupData.barangay.isNotEmpty
        ? widget.arguments.signupData.barangay
        : null;
    _selectedRelationship =
        widget.arguments.signupData.emergencyContactRelationship.isNotEmpty
        ? widget.arguments.signupData.emergencyContactRelationship
        : null;
  }

  @override
  void dispose() {
    _dateOfBirthController.dispose();
    _homeAddressController.dispose();
    _bloodTypeController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactNumberController.dispose();
    super.dispose();
  }

  void _onAddressChanged(String value) {
    setState(() {
      _addressError = value.isEmpty
          ? null
          : Validators.validateAddress(value, fieldLabel: 'Home address');
    });
  }

  void _onBloodTypeChanged(String value) {
    setState(() {
      _bloodTypeError = value.isEmpty
          ? null
          : Validators.validateRequired(value, 'Blood type');
    });
  }

  void _onContactNameChanged(String value) {
    setState(() {
      _contactNameError = value.isEmpty
          ? null
          : Validators.validateName(
              value,
              fieldLabel: 'Emergency contact name',
            );
    });
  }

  void _onContactNumberChanged(String value) {
    setState(() {
      _contactNumberError = value.isEmpty
          ? null
          : Validators.validatePhone(value);
    });
  }

  void _toggleCondition(String condition) {
    setState(() {
      if (_selectedConditions.contains(condition)) {
        _selectedConditions.remove(condition);
      } else {
        if (condition == 'None') {
          _selectedConditions.clear();
          _selectedConditions.add(condition);
        } else {
          _selectedConditions.remove('None');
          _selectedConditions.add(condition);
        }
      }
    });
  }

  Future<void> _handleNext() async {
    final addressError = Validators.validateAddress(
      _homeAddressController.text,
      fieldLabel: 'Home address',
    );
    final bloodTypeError = Validators.validateRequired(
      _bloodTypeController.text,
      'Blood type',
    );
    final contactNameError = Validators.validateName(
      _emergencyContactNameController.text,
      fieldLabel: 'Emergency contact name',
    );
    final contactNumberError = Validators.validatePhone(
      _emergencyContactNumberController.text,
    );
    setState(() {
      _addressError = addressError;
      _bloodTypeError = bloodTypeError;
      _contactNameError = contactNameError;
      _contactNumberError = contactNumberError;
    });

    if (_dateOfBirthController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Date of birth is required.');
      return;
    }
    if (addressError != null) {
      setState(() => _errorMessage = addressError);
      return;
    }
    if (_selectedBarangay == null) {
      setState(() => _errorMessage = 'Please select your barangay.');
      return;
    }
    if (bloodTypeError != null) {
      setState(() => _errorMessage = bloodTypeError);
      return;
    }
    if (contactNameError != null) {
      setState(() => _errorMessage = contactNameError);
      return;
    }
    if (_selectedRelationship == null) {
      setState(
        () => _errorMessage = 'Please select the emergency contact\'s relationship to the patient.',
      );
      return;
    }
    if (contactNumberError != null) {
      setState(() => _errorMessage = contactNumberError);
      return;
    }

    final composedAddress =
        '${_homeAddressController.text.trim()}, Barangay $_selectedBarangay, Valenzuela City';
    final composedContactName =
        '${_emergencyContactNameController.text.trim()} ($_selectedRelationship)';

    final updated = widget.arguments.signupData.copyWith(
      dateOfBirth: _dateOfBirthController.text.trim(),
      homeAddress: composedAddress,
      barangay: _selectedBarangay,
      bloodType: _bloodTypeController.text.trim(),
      emergencyContactName: composedContactName,
      emergencyContactNumber: _emergencyContactNumberController.text.trim(),
      emergencyContactRelationship: _selectedRelationship,
      ckdLevel: _selectedStage,
      conditions: _selectedConditions.isEmpty
          ? ['None']
          : List.from(_selectedConditions),
      clinicRequirements: _clinicRequirements,
    );

    if (updated.profileId.isEmpty) {
      setState(() {
        _errorMessage =
            'Unable to create application without a valid patient account.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final patientId = await AuthService().createPatientRecord(
        profileId: updated.profileId,
        clinicId: updated.clinicId,
        fullName: updated.fullName,
        email: updated.email,
        phone: updated.phone,
        dateOfBirth: updated.dateOfBirth,
        homeAddress: updated.homeAddress,
        bloodType: updated.bloodType,
        emergencyContactName: updated.emergencyContactName,
        emergencyContactNumber: updated.emergencyContactNumber,
        ckdLevel: updated.ckdLevel,
        conditions: updated.conditions,
        insuranceOptions: updated.insuranceOptions,
        budgetRange: updated.budgetRange,
        preferredClinicType: updated.preferredClinicType,
        locationSummary: updated.locationSummary,
      );

      final patientReady = updated.copyWith(patientId: patientId);

      if (mounted) {
        Navigator.of(
          context,
        ).pushNamed('/medical-documents', arguments: patientReady);
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _pickBirthDate() async {
    final currentDate = DateTime.now();
    final initialDate =
        DateTime.tryParse(_dateOfBirthController.text) ??
        DateTime(currentDate.year - 40);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: currentDate,
    );

    if (pickedDate != null) {
      _dateOfBirthController.text =
          '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinic = widget.arguments.clinic;

    return Scaffold(
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
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: Color(0xFF2C5F7D),
                    ),
                  ),

                  const SizedBox(width: 4),

                  const Text(
                    'Clinic Information',
                    style: TextStyle(
                      color: Color(0xFF173B4F),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Text(
                'Review your selected clinic and complete the remaining medical information.',
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
                    'Step 3 of 5',
                    style: TextStyle(
                      color: Color(0xFF2C5F7D),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '60%',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.45),
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
                  value: 0.6,
                  minHeight: 8,
                  color: Color(0xFF2C5F7D),
                  backgroundColor: Color(0xFFDDEAF0),
                ),
              ),

              const SizedBox(height: 26),

              Container(
                padding: const EdgeInsets.all(20),
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

                        if (clinic['contact_number'] != null) ...[
                          const SizedBox(width: 14),

                          Expanded(
                            child: _buildClinicInfoItem(
                              'Contact',
                              clinic['contact_number'].toString(),
                              Icons.phone_outlined,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 24),

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
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    ..._clinicRequirements.map(
                      (requirement) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              child: const Icon(
                                Icons.check_circle,
                                size: 18,
                                color: Color(0xFF2C5F7D),
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Text(
                                requirement,
                                style: const TextStyle(
                                  color: Color(0xFF5B6D7D),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
                    const Text(
                      'Medical Information',
                      style: TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Complete the patient medical profile.',
                      style: TextStyle(color: Color(0xFF7A8A94), fontSize: 13),
                    ),

                    const SizedBox(height: 22),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedStage,
                      items: const [
                        DropdownMenuItem(
                          value: 'Stage 1',
                          child: Text('Stage 1'),
                        ),
                        DropdownMenuItem(
                          value: 'Stage 2',
                          child: Text('Stage 2'),
                        ),
                        DropdownMenuItem(
                          value: 'Stage 3',
                          child: Text('Stage 3'),
                        ),
                        DropdownMenuItem(
                          value: 'Stage 4',
                          child: Text('Stage 4'),
                        ),
                        DropdownMenuItem(
                          value: 'Stage 5',
                          child: Text('Stage 5'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedStage = value);
                        }
                      },
                      decoration: _modernInputDecoration(
                        'Dialysis Stage',
                        Icons.monitor_heart_outlined,
                      ),
                    ),

                    const SizedBox(height: 22),

                    const Text(
                      'Existing Conditions',
                      style: TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _conditions.map((condition) {
                        final selected = _selectedConditions.contains(
                          condition,
                        );

                        return GestureDetector(
                          onTap: () => _toggleCondition(condition),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF2C5F7D)
                                  : const Color(0xFFF4F8FA),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF2C5F7D)
                                    : const Color(0xFFE3EDF2),
                              ),
                            ),
                            child: Text(
                              condition,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF5B6D7D),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 22),

                    _buildModernTextField(
                      label: 'Date of Birth',
                      controller: _dateOfBirthController,
                      icon: Icons.calendar_month_outlined,
                      readOnly: true,
                      onTap: _pickBirthDate,
                    ),

                    const SizedBox(height: 16),

                    _buildModernTextField(
                      label: 'Street, House No. / Subdivision',
                      controller: _homeAddressController,
                      icon: Icons.home_outlined,
                      errorText: _addressError,
                      onChanged: _onAddressChanged,
                    ),

                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedBarangay,
                      decoration: _modernInputDecoration(
                        'Barangay (Valenzuela City)',
                        Icons.location_city_outlined,
                      ),
                      isExpanded: true,
                      hint: const Text('Select Barangay'),
                      items: FormOptions.valenzuelaBarangays.map((brgy) {
                        return DropdownMenuItem(value: brgy, child: Text(brgy));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedBarangay = value;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    _buildModernTextField(
                      label: 'Blood Type',
                      controller: _bloodTypeController,
                      icon: Icons.bloodtype_outlined,
                      errorText: _bloodTypeError,
                      onChanged: _onBloodTypeChanged,
                    ),

                    const SizedBox(height: 16),

                    _buildModernTextField(
                      label: 'Emergency Contact Name',
                      controller: _emergencyContactNameController,
                      icon: Icons.person_outline,
                      errorText: _contactNameError,
                      onChanged: _onContactNameChanged,
                    ),

                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedRelationship,
                      decoration: _modernInputDecoration(
                        'Relationship to Patient',
                        Icons.diversity_3_outlined,
                      ),
                      isExpanded: true,
                      hint: const Text('Select Relationship'),
                      items: FormOptions.emergencyContactRelationships.map((
                        relationship,
                      ) {
                        return DropdownMenuItem(
                          value: relationship,
                          child: Text(relationship),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedRelationship = value;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    _buildModernTextField(
                      label: 'Emergency Contact Number',
                      controller: _emergencyContactNumberController,
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      errorText: _contactNumberError,
                      onChanged: _onContactNumberChanged,
                    ),

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

                    const SizedBox(height: 28),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _handleNext,
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
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.4,
                                ),
                              )
                            : const Text(
                                'Continue To Documents',
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
              ),
            ],
          ),
        ),
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

  Widget _buildModernTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      decoration: _modernInputDecoration(
        label,
        icon,
        showCounter: maxLength == null,
        errorText: errorText,
      ),
    );
  }

  InputDecoration _modernInputDecoration(
    String label,
    IconData icon, {
    bool showCounter = true,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF6F7F89),
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF5F7280)),
      errorText: errorText,
      counterText: showCounter ? null : '',
      filled: true,
      fillColor: const Color(0xFFF4F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE3EDF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2C5F7D), width: 1.2),
      ),
    );
  }
}
