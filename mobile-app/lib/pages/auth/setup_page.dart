import 'package:flutter/material.dart';
import '../../models/signup_data.dart';

class SetupPage extends StatefulWidget {
  final SignupData signupData;

  const SetupPage({super.key, required this.signupData});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final List<String> _conditions = [
    'Diabetes',
    'Hypertension',
    'Heart Disease',
    'None',
  ];
  final Set<String> _selectedConditions = {};
  String _selectedLevel = 'Stage 3';

  void _handleNext() {
    final updated = widget.signupData.copyWith(
      ckdLevel: _selectedLevel,
      conditions: _selectedConditions.toList(),
    );

    Navigator.of(context).pushNamed('/location', arguments: updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDAE7EE),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFDAE7EE),
        iconTheme: const IconThemeData(color: Color(0xFF2C5F7D)),
        title: const Text(
          'Set Up',
          style: TextStyle(color: Color(0xFF2C5F7D)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: 0.33,
                color: const Color(0xFF2C5F7D),
                backgroundColor: const Color(0xFFE7F0F3),
                minHeight: 8,
              ),
              const SizedBox(height: 24),
              const Text(
                'Answer a few questions so we can recommend clinics and centers that match your medical condition and preferences.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F4A5B),
                ),
              ),
              const SizedBox(height: 28),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'CKD Level',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedLevel,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF1F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: [
                          'Stage 2',
                          'Stage 3',
                          'Stage 4',
                          'Stage 5',
                        ].map((level) {
                          return DropdownMenuItem(
                            value: level,
                            child: Text(level),
                          );
                        }).toList(),
                        onChanged: (text) {
                          if (text != null) {
                            setState(() {
                              _selectedLevel = text;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Other Conditions',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _conditions.map((condition) {
                          final selected = _selectedConditions.contains(condition);
                          return FilterChip(
                            label: Text(condition),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  _selectedConditions.add(condition);
                                } else {
                                  _selectedConditions.remove(condition);
                                }
                              });
                            },
                            selectedColor: const Color(0xFF2C5F7D),
                            checkmarkColor: Colors.white,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
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
