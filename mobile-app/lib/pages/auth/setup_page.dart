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
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Set Up',
                  style: TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Complete your medical and contact information to continue.',
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
                      'Step 1 of 5',
                      style: TextStyle(
                        color: Color(0xFF2C5F7D),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '20%',
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
                  child: LinearProgressIndicator(
                    value: 0.2,
                    minHeight: 8,
                    color: const Color(0xFF2C5F7D),
                    backgroundColor: const Color(0xFFDDEAF0),
                  ),
                ),

                const SizedBox(height: 28),

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
                        'Personal Information',
                        style: TextStyle(
                          color: Color(0xFF173B4F),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Tell us more about the patient.',
                        style: TextStyle(
                          color: Color(0xFF7A8A94),
                          fontSize: 13,
                        ),
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
                        decoration: _setupInputDecoration(
                          label: 'Home Address',
                          icon: Icons.home_outlined,
                        ),
                      ),

                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        initialValue: _selectedBloodType,
                        decoration: _setupInputDecoration(
                          label: 'Blood Type',
                          icon: Icons.bloodtype_outlined,
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

                      const SizedBox(height: 26),

                      const Divider(color: Color(0xFFE4EEF3), height: 1),

                      const SizedBox(height: 24),

                      const Text(
                        'Emergency Contact',
                        style: TextStyle(
                          color: Color(0xFF173B4F),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Add a contact person we can reach if needed.',
                        style: TextStyle(
                          color: Color(0xFF7A8A94),
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 22),

                      TextField(
                        controller: _emergencyNameController,
                        decoration: _setupInputDecoration(
                          label: 'Contact Name',
                          icon: Icons.person_outline,
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _emergencyNumberController,
                        keyboardType: TextInputType.phone,
                        decoration: _setupInputDecoration(
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                        ),
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
                    ],
                  ),
                ),

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

  InputDecoration _setupInputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF6F7F89),
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF5F7280)),
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
