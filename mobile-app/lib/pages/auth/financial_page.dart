import 'package:flutter/material.dart';
import '../../models/signup_data.dart';

class FinancialPage extends StatefulWidget {
  final SignupData signupData;

  const FinancialPage({super.key, required this.signupData});

  @override
  State<FinancialPage> createState() => _FinancialPageState();
}

class _FinancialPageState extends State<FinancialPage> {
  final List<String> _insuranceOptions = [
    'PhilHealth',
    'HMO',
    'Health Insurance',
    'None',
  ];
  final List<String> _budgetOptions = [
    'Low-cost / Government-supported',
    'Mid-range',
    'Private / Premium',
  ];
  final List<String> _clinicOptions = [
    'Public Hospital',
    'Private Clinic',
    'Dialysis Center',
  ];

  final Set<String> _selectedInsurance = {};
  String _selectedBudget = 'Low-cost / Government-supported';
  final String _selectedClinicType = 'Public Hospital';

  void _toggleInsurance(String option) {
    setState(() {
      if (option == 'None') {
        _selectedInsurance.clear();
        _selectedInsurance.add('None');
        return;
      }
      _selectedInsurance.remove('None');
      if (_selectedInsurance.contains(option)) {
        _selectedInsurance.remove(option);
      } else {
        _selectedInsurance.add(option);
      }
    });
  }

  void _handleNext() {
    final updated = widget.signupData.copyWith(
      insuranceOptions: _selectedInsurance.toList(),
      budgetRange: _selectedBudget,
      preferredClinicType: _selectedClinicType,
    );
    Navigator.of(context).pushNamed('/confirm-info', arguments: updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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

                  const Expanded(
                    child: Text(
                      'Financial Information',
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
                'Help us recommend clinics that match your financial preferences and healthcare support.',
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
                    'Final Step',
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
                      color: const Color.fromARGB(255, 24, 138, 28).withOpacity(0.45),
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
                  color: Color.fromARGB(255, 56, 224, 58),
                  backgroundColor: Color(0xFFDDEAF0),
                ),
              ),

              const SizedBox(height: 24),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildSectionContainer(
                        title: 'Insurance Coverage',
                        subtitle: 'Select all that apply.',
                        child: Column(
                          children: _insuranceOptions.map((option) {
                            final selected = _selectedInsurance.contains(
                              option,
                            );

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GestureDetector(
                                onTap: () => _toggleInsurance(option),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.all(16),
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
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: selected
                                            ? Colors.white
                                            : const Color(0xFF7A8A94),
                                      ),

                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Text(
                                          option,
                                          style: TextStyle(
                                            color: selected
                                                ? Colors.white
                                                : const Color(0xFF173B4F),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 20),

                      _buildSectionContainer(
                        title: 'Budget Range',
                        subtitle: 'Choose your preferred healthcare budget.',
                        child: Column(
                          children: _budgetOptions.map((option) {
                            final selected = _selectedBudget == option;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedBudget = option;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.all(16),
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
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off_outlined,
                                        color: selected
                                            ? Colors.white
                                            : const Color(0xFF7A8A94),
                                      ),

                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Text(
                                          option,
                                          style: TextStyle(
                                            color: selected
                                                ? Colors.white
                                                : const Color(0xFF173B4F),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

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
                    'CONTINUE',
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
    );
  }

  Widget _buildSectionContainer({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
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

          const SizedBox(height: 20),

          child,
        ],
      ),
    );
  }
}
