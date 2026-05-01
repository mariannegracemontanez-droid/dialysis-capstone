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
                      'Answer a few questions so we can recommend clinics and centers that match your medical condition and preferences.',
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
                              'CKD Level',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedLevel,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF1F7FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items:
                                  [
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _conditions.map((condition) {
                                final selected = _selectedConditions.contains(
                                  condition,
                                );
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
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF2C5F7D),
                                  ),
                                  backgroundColor: const Color(0xFFF5FBFF),
                                );
                              }).toList(),
                            ),
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
                        child: const Text('Next'),
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
