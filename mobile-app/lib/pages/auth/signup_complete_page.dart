import 'package:flutter/material.dart';

class SignupCompletePage extends StatelessWidget {
  const SignupCompletePage({super.key});

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
              const SizedBox(height: 8),
              const Text(
                'Thank you!',
                style: TextStyle(
                  color: Color(0xFF2C5F7D),
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your information has been successfully submitted.',
                style: TextStyle(color: Color(0xFF546D7A), fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const [
                        Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF2C5F7D),
                          size: 72,
                        ),
                        SizedBox(height: 24),
                        Text(
                          'Next Steps',
                          style: TextStyle(
                            color: Color(0xFF2C5F7D),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Please visit your selected clinic to submit your physical medical documents to the clinic admin.',
                          style: TextStyle(
                            color: Color(0xFF526A74),
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Your account will remain pending until the clinic admin reviews and approves your application. Once approved, you can log in and use the app normally.',
                          style: TextStyle(
                            color: Color(0xFF526A74),
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'You may now return to the login page and wait for approval from the clinic administrator.',
                          style: TextStyle(
                            color: Color(0xFF526A74),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/login_page');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C5F7D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Ok, go to Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
