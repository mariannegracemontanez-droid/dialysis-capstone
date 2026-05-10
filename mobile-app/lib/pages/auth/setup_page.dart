import 'package:flutter/material.dart';
import '../../models/signup_data.dart';

class SetupPage extends StatefulWidget {
  final SignupData signupData;

  const SetupPage({super.key, required this.signupData});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
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
  String _selectedBloodType = 'O+';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _dobController.text = widget.signupData.dateOfBirth;
    _homeAddressController.text = widget.signupData.homeAddress;
    _emergencyNameController.text = widget.signupData.emergencyContactName;
    _emergencyNumberController.text = widget.signupData.emergencyContactNumber;
    _selectedBloodType = widget.signupData.bloodType.isNotEmpty
        ? widget.signupData.bloodType
        : _selectedBloodType;
  }

  @override
  void dispose() {
    _dobController.dispose();
    _homeAddressController.dispose();
    _emergencyNameController.dispose();
    _emergencyNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final currentDate = DateTime.now();
    final initialDate = DateTime(
      currentDate.year - 40,
      currentDate.month,
      currentDate.day,
    );
    final firstDate = DateTime(1900);
    final lastDate = DateTime(
      currentDate.year - 16,
      currentDate.month,
      currentDate.day,
    );

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

  void _handleNext() {
    setState(() {
      _errorMessage = null;
    });

    if (_dobController.text.isEmpty) {
      setState(() => _errorMessage = 'Date of birth is required.');
      return;
    }
    if (_homeAddressController.text.isEmpty) {
      setState(() => _errorMessage = 'Home address is required.');
      return;
    }
    if (_emergencyNameController.text.isEmpty) {
      setState(() => _errorMessage = 'Emergency contact name is required.');
      return;
    }
    if (_emergencyNumberController.text.isEmpty) {
      setState(() => _errorMessage = 'Emergency contact number is required.');
      return;
    }

    final updated = widget.signupData.copyWith(
      dateOfBirth: _dobController.text.trim(),
      homeAddress: _homeAddressController.text.trim(),
      bloodType: _selectedBloodType,
      emergencyContactName: _emergencyNameController.text.trim(),
      emergencyContactNumber: _emergencyNumberController.text.trim(),
    );

    Navigator.of(context).pushNamed('/location', arguments: updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF2F9),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF2C5F7D),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Set Up',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Provide your basic medical and contact information so we can recommend the right clinics for you.',
                      style: TextStyle(color: Color(0xFFDBE9F2), fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: 0.33,
                      color: const Color(0xFF2C5F7D),
                      backgroundColor: const Color(0xFFD9EAF1),
                      minHeight: 9,
                    ),
                    const SizedBox(height: 24),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.09),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Personal Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _dobController,
                              readOnly: true,
                              onTap: _pickDob,
                              decoration: InputDecoration(
                                labelText: 'Date of Birth',
                                suffixIcon: const Icon(Icons.calendar_month),
                                filled: true,
                                fillColor: const Color(0xFFF1F7FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _homeAddressController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Home Address',
                                prefixIcon: const Icon(Icons.home),
                                filled: true,
                                fillColor: const Color(0xFFF1F7FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedBloodType,
                              decoration: InputDecoration(
                                labelText: 'Blood Type',
                                filled: true,
                                fillColor: const Color(0xFFF1F7FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items: _bloodTypes.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedBloodType = value;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 16),
                            const Text(
                              'Emergency Contact',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _emergencyNameController,
                              decoration: InputDecoration(
                                labelText: 'Name',
                                prefixIcon: const Icon(Icons.person_outline),
                                filled: true,
                                fillColor: const Color(0xFFF1F7FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _emergencyNumberController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                prefixIcon: const Icon(Icons.phone_android),
                                filled: true,
                                fillColor: const Color(0xFFF1F7FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
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
                        child: const Text(
                          'Next',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
