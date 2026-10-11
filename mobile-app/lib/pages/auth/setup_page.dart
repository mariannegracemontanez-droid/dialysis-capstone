import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/signup_data.dart';
import '../../utils/form_options.dart';
import '../../utils/validators.dart';
import '../../widgets/patient_name_fields.dart';

class SetupPage extends StatefulWidget {
  final SignupData signupData;

  const SetupPage({super.key, required this.signupData});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

/// Step 1 of 3: patient name, personal details, emergency contact, medical
/// information and insurance coverage.
class _SetupPageState extends State<SetupPage> {
  late final PatientNameController _nameController;
  final _dobController = TextEditingController();
  final _homeAddressController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyNumberController = TextEditingController();
  final List<String> _bloodTypes = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];
  static const List<String> _stages = [
    'Stage 1',
    'Stage 2',
    'Stage 3',
    'Stage 4',
    'Stage 5',
  ];
  static const List<String> _conditions = [
    'Diabetes',
    'Hypertension',
    'Heart Disease',
    'None',
  ];
  static const List<String> _insuranceOptions = [
    'PhilHealth',
    'HMO',
    'Health Insurance',
    'None',
  ];
  String? _selectedBloodType = 'O+';
  String? _selectedStage;
  final List<String> _selectedConditions = [];
  final Set<String> _selectedInsurance = {};
  Map<String, ApplicationDraft> _applicationDrafts = {};
  String? _selectedBarangay;
  String? _selectedRelationship;
  String? _errorMessage;
  String? _addressError;
  String? _contactNameError;
  String? _contactNumberError;

  @override
  void initState() {
    super.initState();
    _nameController = PatientNameController(initial: widget.signupData.name);
    _dobController.text = widget.signupData.dateOfBirth;
    _homeAddressController.text = widget.signupData.homeAddress;
    _emergencyNameController.text = widget.signupData.emergencyContactName;
    _emergencyNumberController.text = widget.signupData.emergencyContactNumber;
    // Values pre-filled from an earlier application may be free text; only
    // pre-select them when they match an option, otherwise ask again.
    final bloodType = widget.signupData.bloodType;
    if (bloodType.isNotEmpty) {
      _selectedBloodType = _bloodTypes.contains(bloodType) ? bloodType : null;
    }
    final stage = widget.signupData.ckdLevel;
    _selectedStage = _stages.contains(stage) ? stage : null;
    _selectedConditions.addAll(widget.signupData.conditions);
    _selectedInsurance.addAll(
      widget.signupData.insuranceOptions.where(_insuranceOptions.contains),
    );
    _applicationDrafts = widget.signupData.applicationDrafts;
    _selectedBarangay = widget.signupData.barangay.isNotEmpty
        ? widget.signupData.barangay
        : null;
    _selectedRelationship =
        widget.signupData.emergencyContactRelationship.isNotEmpty
        ? widget.signupData.emergencyContactRelationship
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _homeAddressController.dispose();
    _emergencyNameController.dispose();
    _emergencyNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final currentDate = DateTime.now();
    final firstDate = DateTime(1900);
    final lastDate = DateTime(
      currentDate.year - 16,
      currentDate.month,
      currentDate.day,
    );
    final enteredDate = DateTime.tryParse(_dobController.text);
    final initialDate =
        enteredDate != null &&
            !enteredDate.isBefore(firstDate) &&
            !enteredDate.isAfter(lastDate)
        ? enteredDate
        : DateTime(currentDate.year - 40, currentDate.month, currentDate.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF2C5F7D),
            onPrimary: Colors.white,
            onSurface: Color(0xFF2C5F7D),
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      _dobController.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  void _onAddressChanged(String value) {
    setState(() {
      _addressError = value.isEmpty
          ? null
          : Validators.validateAddress(value, fieldLabel: 'Home address');
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
      } else if (condition == 'None') {
        _selectedConditions
          ..clear()
          ..add(condition);
      } else {
        _selectedConditions
          ..remove('None')
          ..add(condition);
      }
    });
  }

  void _toggleInsurance(String option) {
    setState(() {
      if (_selectedInsurance.contains(option)) {
        _selectedInsurance.remove(option);
      } else if (option == 'None') {
        _selectedInsurance
          ..clear()
          ..add(option);
      } else {
        _selectedInsurance
          ..remove('None')
          ..add(option);
      }
    });
  }

  Future<void> _handleNext() async {
    setState(() {
      _errorMessage = null;
    });

    final nameError = _nameController.validate();
    final addressError = Validators.validateAddress(
      _homeAddressController.text,
      fieldLabel: 'Home address',
    );
    final contactNameError = Validators.validateName(
      _emergencyNameController.text,
      fieldLabel: 'Emergency contact name',
    );
    final contactNumberError = Validators.validatePhone(
      _emergencyNumberController.text,
    );
    setState(() {
      _addressError = addressError;
      _contactNameError = contactNameError;
      _contactNumberError = contactNumberError;
    });

    if (nameError != null) {
      setState(() => _errorMessage = nameError);
      return;
    }
    if (_dobController.text.isEmpty) {
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
    if (_selectedBloodType == null) {
      setState(() => _errorMessage = 'Please select your blood type.');
      return;
    }
    if (contactNameError != null) {
      setState(() => _errorMessage = contactNameError);
      return;
    }
    if (_selectedRelationship == null) {
      setState(
        () => _errorMessage =
            'Please select the emergency contact\'s relationship to the patient.',
      );
      return;
    }
    if (contactNumberError != null) {
      setState(() => _errorMessage = contactNumberError);
      return;
    }
    if (_selectedStage == null) {
      setState(() => _errorMessage = 'Please select the dialysis stage.');
      return;
    }

    final updated = widget.signupData.copyWith(
      name: _nameController.value,
      dateOfBirth: _dobController.text.trim(),
      homeAddress: _homeAddressController.text.trim(),
      barangay: _selectedBarangay,
      bloodType: _selectedBloodType,
      emergencyContactName: _emergencyNameController.text.trim(),
      emergencyContactNumber: _emergencyNumberController.text.trim(),
      emergencyContactRelationship: _selectedRelationship,
      ckdLevel: _selectedStage,
      conditions: _selectedConditions.isEmpty
          ? ['None']
          : List.of(_selectedConditions),
      insuranceOptions: _selectedInsurance.toList(),
      applicationDrafts: _applicationDrafts,
    );

    final result = await Navigator.of(
      context,
    ).pushNamed('/location', arguments: updated);

    // Step 2 hands back any applications already started, so coming
    // forward again to the same clinic reuses them.
    if (result is SignupData && mounted) {
      _applicationDrafts = result.applicationDrafts;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Existing patients applying to another clinic start here from Home and
    // need a way back; a brand-new account has nothing to go back to.
    final canGoBack = widget.signupData.password.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (canGoBack) ...[
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                          color: Color(0xFF2C5F7D),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Expanded(
                      child: Text(
                        'Patient Information',
                        style: TextStyle(
                          color: Color(0xFF173B4F),
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                const Text(
                  'Complete your personal, contact, and medical information to continue.',
                  style: TextStyle(
                    color: Color(0xFF6B7C86),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 26),

                Row(
                  children: [
                    const Text(
                      'Step 1 of 3',
                      style: TextStyle(
                        color: Color(0xFF2C5F7D),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '33%',
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
                    value: 1 / 3,
                    minHeight: 8,
                    color: Color(0xFF2C5F7D),
                    backgroundColor: Color(0xFFDDEAF0),
                  ),
                ),

                const SizedBox(height: 28),

                _buildSectionCard(
                  children: [
                    _buildSectionHeader(
                      'Patient Name',
                      "Enter the patient's name as it appears on a valid ID.",
                    ),

                    const SizedBox(height: 22),

                    PatientNameFields(
                      controller: _nameController,
                      decoration: (label, icon, errorText) =>
                          _setupInputDecoration(
                            label: label,
                            icon: icon,
                            errorText: errorText,
                          ),
                    ),

                    const SizedBox(height: 26),

                    const Divider(color: Color(0xFFE4EEF3), height: 1),

                    const SizedBox(height: 24),

                    _buildSectionHeader(
                      'Personal Information',
                      'Tell us more about the patient.',
                    ),

                    const SizedBox(height: 22),

                    TextField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: _pickDob,
                      decoration: _setupInputDecoration(
                        label: 'Date of Birth',
                        icon: Icons.calendar_month_outlined,
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: _homeAddressController,
                      maxLines: 2,
                      onChanged: _onAddressChanged,
                      decoration: _setupInputDecoration(
                        label: 'Street, House No. / Subdivision',
                        icon: Icons.home_outlined,
                        errorText: _addressError,
                      ),
                    ),

                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedBarangay,
                      decoration: _setupInputDecoration(
                        label: 'Barangay (Valenzuela City)',
                        icon: Icons.location_city_outlined,
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

                    DropdownButtonFormField<String>(
                      initialValue: _selectedBloodType,
                      decoration: _setupInputDecoration(
                        label: 'Blood Type',
                        icon: Icons.bloodtype_outlined,
                      ),
                      isExpanded: true,
                      hint: const Text('Select Blood Type'),
                      items: _bloodTypes.map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedBloodType = value;
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 26),

                    const Divider(color: Color(0xFFE4EEF3), height: 1),

                    const SizedBox(height: 24),

                    _buildSectionHeader(
                      'Emergency Contact',
                      'Add a contact person we can reach if needed.',
                    ),

                    const SizedBox(height: 22),

                    TextField(
                      controller: _emergencyNameController,
                      onChanged: _onContactNameChanged,
                      decoration: _setupInputDecoration(
                        label: 'Contact Name',
                        icon: Icons.person_outline,
                        errorText: _contactNameError,
                      ),
                    ),

                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedRelationship,
                      decoration: _setupInputDecoration(
                        label: 'Relationship to Patient',
                        icon: Icons.diversity_3_outlined,
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

                    TextField(
                      controller: _emergencyNumberController,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _onContactNumberChanged,
                      decoration: _setupInputDecoration(
                        label: 'Phone Number',
                        icon: Icons.phone_outlined,
                        showCounter: false,
                        errorText: _contactNumberError,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                _buildSectionCard(
                  children: [
                    _buildSectionHeader(
                      'Medical Information',
                      'Complete the patient medical profile.',
                    ),

                    const SizedBox(height: 22),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedStage,
                      decoration: _setupInputDecoration(
                        label: 'Dialysis Stage',
                        icon: Icons.monitor_heart_outlined,
                      ),
                      isExpanded: true,
                      hint: const Text('Select Dialysis Stage'),
                      items: _stages.map((stage) {
                        return DropdownMenuItem(
                          value: stage,
                          child: Text(stage),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedStage = value);
                        }
                      },
                    ),

                    const SizedBox(height: 22),

                    _buildChoiceLabel('Existing Conditions'),

                    const SizedBox(height: 10),

                    _buildChoiceChips(
                      options: _conditions,
                      isSelected: _selectedConditions.contains,
                      onTap: _toggleCondition,
                    ),

                    const SizedBox(height: 22),

                    _buildChoiceLabel('Insurance Coverage'),

                    const SizedBox(height: 4),

                    const Text(
                      'Select all that apply.',
                      style: TextStyle(color: Color(0xFF7A8A94), fontSize: 13),
                    ),

                    const SizedBox(height: 10),

                    _buildChoiceChips(
                      options: _insuranceOptions,
                      isSelected: _selectedInsurance.contains,
                      onTap: _toggleInsurance,
                    ),
                  ],
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.20)),
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
                    onPressed: _handleNext,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFF2C5F7D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'NEXT',
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
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
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
        children: children,
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF173B4F),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF7A8A94), fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildChoiceLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF173B4F),
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildChoiceChips({
    required List<String> options,
    required bool Function(String) isSelected,
    required ValueChanged<String> onTap,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((option) {
        final selected = isSelected(option);

        return GestureDetector(
          onTap: () => onTap(option),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              option,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF5B6D7D),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  InputDecoration _setupInputDecoration({
    required String label,
    required IconData icon,
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
