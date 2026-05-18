import 'package:flutter/material.dart';

class ApplicationCompletePage extends StatelessWidget {
  const ApplicationCompletePage({super.key});

  void _handleContinue(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/main_navigation', (route) => false);
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
              const SizedBox(height: 10),

              Center(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F6EF),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFCBE9D8),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF2A9D65),
                    size: 62,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'Application Submitted',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF173B4F),
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Your clinic application has been successfully submitted for review.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7C86),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 26),

              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
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
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.assignment_turned_in_outlined,
                              color: Color(0xFF2C5F7D),
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Next Steps',
                              style: TextStyle(
                                color: Color(0xFF173B4F),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 22),

                        _buildStepCard(
                          icon: Icons.local_hospital_outlined,
                          title: 'Visit Your Selected Clinic',
                          description:
                              'Please proceed to your selected clinic and submit your physical medical documents to the clinic administrator.',
                        ),

                        const SizedBox(height: 14),

                        _buildStepCard(
                          icon: Icons.pending_actions_outlined,
                          title: 'Wait for Account Approval',
                          description:
                              'Your application will remain pending until the clinic administrator reviews and approves it.',
                        ),

                        const SizedBox(height: 14),

                        _buildStepCard(
                          icon: Icons.home_rounded,
                          title: 'Go to Waiting Page',
                          description:
                              'You will be redirected to your home page where you can monitor your pending clinic application.',
                        ),

                        const SizedBox(height: 24),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F8FA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE3EDF2)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFF2C5F7D),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'You may now return to your waiting approval page.',
                                  style: TextStyle(
                                    color: Color(0xFF5B6D7D),
                                    fontSize: 13,
                                    height: 1.4,
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
              ),

              const SizedBox(height: 22),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: () => _handleContinue(context),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF2C5F7D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'BACK TO HOME',
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

  Widget _buildStepCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EDF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2C5F7D), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF5B6D7D),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
