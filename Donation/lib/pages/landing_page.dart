import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import 'signup_page.dart';
import 'donation_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  String? _displayName;
  late final StreamSubscription _authSubscription;
  final Color _primaryColor = const Color(0xFF0D6EFD);
  final Color _secondaryColor = const Color(0xFF1C7ED6);

  @override
  void initState() {
    super.initState();
    _loadAuthState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (event) {
        _loadAuthState();
      },
    );
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadAuthState() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _displayName = null;
      });
      return;
    }

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      final name = profile?['full_name'] as String?;
      setState(() {
        _displayName = (name?.isNotEmpty == true) ? name : user.email;
      });
    } catch (_) {
      setState(() {
        _displayName = user.email;
      });
    }
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  void _openSignup(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignupPage()));
  }

  void _openDonation(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    if (user != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DonationPage()));
    } else {
      _openLogin(context);
    }
  }

  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    setState(() {
      _displayName = null;
    });
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  Widget _sectionCard({
    required String title,
    required String content,
    Color? color,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(content, style: const TextStyle(fontSize: 16, height: 1.5)),
        ],
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required String subtitle,
    required String description,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D6EFD);
    const bgColor = Color(0xFFF4F7FC);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Image.asset(
              'lib/assets/image/CureNurture_logo.png',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text(
              'Cure Nurture',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: _displayName == null
            ? [
                TextButton(
                  onPressed: () => _openLogin(context),
                  child: const Text('Log In'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _openSignup(context),
                  child: const Text('Sign Up'),
                ),
                const SizedBox(width: 8),
              ]
            : [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: Center(
                    child: Text(
                      'Hi, ${_displayName ?? 'Friend'} 👋',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _openDonation(context),
                  child: const Text('Donate'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _logout(context),
                  child: const Text('Logout'),
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
           Container(
  color: primaryColor,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Tagline moved to the top
      const Text(
        'Together, we nurture healing.',
        style: TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Helping our community access care and support through transparent donations and trusted partners.',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 16,
          height: 1.6,
        ),
      ),
      const SizedBox(height: 32),
      Row(
        children: [
          ElevatedButton(
            onPressed: () => _openDonation(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Donate Now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ],
  ),
),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _sectionCard(
                    title: 'Who We Are',
                    content:
                        'CureNurture is a compassionate community-driven platform that makes it easy for donors to support people in need. We connect caring supporters with meaningful causes and help ensure every contribution is secure and transparent.',
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _sectionCard(
                          title: 'Our Purpose',
                          content:
                              'We empower donors and recipients through clear communication, accountable giving, and support for families facing health challenges. Our goal is to make giving simple, trusted, and impactful.',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _sectionCard(
                          title: 'Why We Do It',
                          content:
                              'No one should face medical hardship alone. Through donations and volunteer support, we help people recover with dignity and build stronger communities together.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'More Details',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Log in before donating so we can keep your contribution secure and ensure every gift is correctly tracked for transparency and care.',
                          style: TextStyle(fontSize: 16, height: 1.7),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => _openDonation(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Start Your Donation Journey',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _infoCard(
                        title: 'Gift of Care by UNLV',
                        subtitle: 'Distribution Date: Mar 26, 2025',
                        description:
                            'Highlights care access and community support through education and donation transparency.',
                      ),
                      _infoCard(
                        title: 'Health Matters by Cora Loco',
                        subtitle: 'Distribution Date: Apr 14, 2025',
                        description:
                            'Providing focused health awareness and donations for families in need.',
                      ),
                      _infoCard(
                        title: 'Angel Baby',
                        subtitle: 'Distribution Date: May 22, 2025',
                        description:
                            'Supporting children and families during critical healthcare challenges.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Container(
              color: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Clinic Contact Information',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '1925 Enterprise Road • CURE Nurture, All Rights Reserved',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
