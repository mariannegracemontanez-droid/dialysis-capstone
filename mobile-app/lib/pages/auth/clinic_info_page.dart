import 'package:flutter/material.dart';
import '../../models/signup_data.dart';

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
  String? _errorMessage;

  List<String> get _clinicRequirements {
    final requirements = widget.arguments.clinic['requirements'];
    if (requirements is List) {
      return requirements.cast<String>();
    }
    if (requirements != null && requirements.toString().isNotEmpty) {
      return [requirements.toString()];
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

  void _handleNext() {
    if (_dateOfBirthController.text.trim().isEmpty ||
        _homeAddressController.text.trim().isEmpty ||
        _bloodTypeController.text.trim().isEmpty ||
        _emergencyContactNameController.text.trim().isEmpty ||
        _emergencyContactNumberController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please complete all fields before continuing.';
      });
      return;
    }

    final updated = widget.arguments.signupData.copyWith(
      dateOfBirth: _dateOfBirthController.text.trim(),
      homeAddress: _homeAddressController.text.trim(),
      bloodType: _bloodTypeController.text.trim(),
      emergencyContactName: _emergencyContactNameController.text.trim(),
      emergencyContactNumber: _emergencyContactNumberController.text.trim(),
      ckdLevel: _selectedStage,
      conditions: _selectedConditions.isEmpty
          ? ['None']
          : List.from(_selectedConditions),
      clinicRequirements: _clinicRequirements,
    );

    Navigator.of(context).pushNamed('/medical-documents', arguments: updated);
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
      backgroundColor: const Color(0xFFF4F9FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C5F7D),
        title: const Text('Clinic Information'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 56,
                            width: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C5F7D),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.local_hospital,
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
                                  clinic['name']?.toString() ??
                                      'Selected Clinic',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (clinic['address'] != null)
                                  Text(
                                    clinic['address'].toString(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (clinic['operating_hours'] != null ||
                          clinic['contact_number'] != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Operating Hours',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (clinic['operating_hours'] != null)
                                    Text(
                                      clinic['operating_hours'].toString(),
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                ],
                              ),
                            ),
                            if (clinic['contact_number'] != null)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Contact',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      clinic['contact_number'].toString(),
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 18),
                      const Text(
                        'Required documents',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._clinicRequirements.map(
                        (requirement) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: Color(0xFF2C5F7D),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  requirement,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Dialysis stage',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF6FAFF),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Existing conditions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._conditions.map(
                        (condition) => CheckboxListTile(
                          value: _selectedConditions.contains(condition),
                          title: Text(condition),
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFF2C5F7D),
                          onChanged: (_) => _toggleCondition(condition),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Date of birth',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickBirthDate,
                        child: AbsorbPointer(
                          child: TextField(
                            controller: _dateOfBirthController,
                            decoration: InputDecoration(
                              hintText: 'YYYY-MM-DD',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              suffixIcon: const Icon(Icons.calendar_today),
                              filled: true,
                              fillColor: const Color(0xFFF6FAFF),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildTextField('Home address', _homeAddressController),
                      const SizedBox(height: 18),
                      _buildTextField(
                        'Blood type',
                        _bloodTypeController,
                        hint: 'e.g., O+, A-, B+',
                      ),
                      const SizedBox(height: 18),
                      _buildTextField(
                        'Emergency contact name',
                        _emergencyContactNameController,
                      ),
                      const SizedBox(height: 18),
                      _buildTextField(
                        'Emergency contact number',
                        _emergencyContactNumberController,
                        keyboardType: TextInputType.phone,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _handleNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C5F7D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Continue to documents',
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint ?? 'Enter $label',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            filled: true,
            fillColor: const Color(0xFFF6FAFF),
          ),
        ),
      ],
    );
  }
}
