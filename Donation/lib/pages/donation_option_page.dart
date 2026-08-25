import 'package:flutter/material.dart';

import 'donation_page.dart';
import 'login_page.dart';

class DonationOptionPage extends StatefulWidget {
  const DonationOptionPage({super.key});

  @override
  State<DonationOptionPage> createState() => _DonationOptionPageState();
}

class _DonationOptionPageState extends State<DonationOptionPage> {
  String? _selectedOption;

  final Color _darkTeal = const Color(0xFF163B56);
  final Color _primaryTeal = const Color(0xFF3B97A2);
  final Color _accentBlue = const Color(0xFF38A6DB);
  final Color _surface = const Color(0xFFF7FBFD);
  final Color _softBlue = const Color(0xFFEAF7FB);

  void _continue() {
    if (_selectedOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please select a donation option to continue.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
      return;
    }

   if (_selectedOption == 'anonymous') {
  Navigator.of(context).push(
    MaterialPageRoute(
     builder: (_) => const DonationPage(
  isAnonymous: true,
  ),
    ),
  );
}else if (_selectedOption == 'registered') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LoginPage(
        fromDonation: true,
      ),
        ),
      );
    }
  }

  Widget _optionCard({
    required String value,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final selected = _selectedOption == value;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        setState(() {
          _selectedOption = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? _softBlue : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? _primaryTeal
                : const Color(0xFFE3EEF4),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: _primaryTeal,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _darkTeal,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.blueGrey.shade600,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? _primaryTeal
                  : Colors.blueGrey.shade300,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,

        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: _darkTeal,
          ),
          onPressed: () => Navigator.pop(context),
        ),

        titleSpacing: 0,

        title: Row(
          children: [
            Image.asset(
              'lib/assets/image/CureNurture_logo.png',
              width: 36,
              height: 36,
            ),
            const SizedBox(width: 10),
            Text(
              'Cure Nurture',
              style: TextStyle(
                color: _darkTeal,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 760,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 30),

                Text(
                  'Choose How You Want to Donate',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _darkTeal,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Please select an option before continuing with your donation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 30),

                _optionCard(
                  value: 'anonymous',
                  icon: Icons.person_off_outlined,
                  title: 'Donate Anonymously',
                  description:
                      'Continue to the donation form without using a registered account.',
                ),

                const SizedBox(height: 16),

                _optionCard(
                  value: 'registered',
                  icon: Icons.person_outline_rounded,
                  title: 'Donate Using a Registered Account',
                  description:
                      'Log in to your registered donor account before continuing.',
                ),

                const SizedBox(height: 26),

                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'CONTINUE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}