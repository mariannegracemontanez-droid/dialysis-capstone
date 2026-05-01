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
  String _selectedClinicType = 'Public Hospital';

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
                    'About Your Financial',
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
                value: 0.92,
                color: const Color(0xFF2C5F7D),
                backgroundColor: const Color(0xFFE7F0F3),
                minHeight: 8,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 4,
                        shadowColor: Colors.black.withOpacity(0.08),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'About Your Financial',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '(Select all that apply)',
                                style: TextStyle(
                                  color: Color(0xFF65768F),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ..._insuranceOptions.map((option) {
                                final selected = _selectedInsurance.contains(
                                  option,
                                );
                                return CheckboxListTile(
                                  title: Text(option),
                                  value: selected,
                                  activeColor: const Color(0xFF2C5F7D),
                                  onChanged: (_) => _toggleInsurance(option),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 4,
                        shadowColor: Colors.black.withOpacity(0.08),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Budget Range',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ..._budgetOptions.map((option) {
                                return RadioListTile<String>(
                                  title: Text(option),
                                  value: option,
                                  groupValue: _selectedBudget,
                                  activeColor: const Color(0xFF2C5F7D),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedBudget = value;
                                      });
                                    }
                                  },
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 4,
                        shadowColor: Colors.black.withOpacity(0.08),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Preferred Clinic Type',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ..._clinicOptions.map((option) {
                                return RadioListTile<String>(
                                  title: Text(option),
                                  value: option,
                                  groupValue: _selectedClinicType,
                                  activeColor: const Color(0xFF2C5F7D),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedClinicType = value;
                                      });
                                    }
                                  },
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],
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
}
