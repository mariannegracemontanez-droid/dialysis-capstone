import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'donation_page.dart';
import 'login_page.dart';
import 'more_details_page.dart';
import 'signup_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  String? _displayName;
  late final StreamSubscription _authSubscription;
  final Color _brandBlue = const Color(0xFF0D6EFD);
  final Color _darkTeal = const Color(0xFF1F5E7D);
  final Color _surface = const Color(0xFFF4F7FC);

  @override
  void initState() {
    super.initState();
    _loadAuthState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      _loadAuthState();
    });
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

  void _openMoreDetails(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoreDetailsPage()));
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

  Stream<List<Map<String, String>>> get _verifiedDonationsStream {
    final sampleDonations = <Map<String, String>>[
      {
        'name': 'Gift of Care by UNLV',
        'date': 'March 26, 2025',
        'amount': '₦ 2,500',
        'status': 'Verified',
      },
      {
        'name': 'Health Matters by Cora Loco',
        'date': 'April 14, 2025',
        'amount': '₦ 4,100',
        'status': 'Verified',
      },
      {
        'name': 'Angel Baby Support',
        'date': 'May 22, 2025',
        'amount': '₦ 3,800',
        'status': 'Verified',
      },
    ];
    return Stream.value(sampleDonations);
  }
  
  get GoogleFonts => null;

  Widget _heroStatCard(String value, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1F5E7D),
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1F5E7D),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
          Text(content, style: const TextStyle(fontSize: 16, height: 1.6)),
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
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verifiedDonationCard(Map<String, String> donation) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: _brandBlue.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.verified, color: Color(0xFF0D6EFD)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      donation['name'] ?? '',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      donation['date'] ?? '',
                      style: const TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _brandBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  donation['status'] ?? '',
                  style: const TextStyle(color: Color(0xFF0D6EFD), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            donation['amount'] ?? '',
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ],
      ),
    );
  }

 @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: _surface,

    appBar: AppBar(
      backgroundColor: _darkTeal,
      elevation: 0,
      title: Row(
        children: [
          Image.asset(
            'lib/assets/image/CureNurture_logo.png',
            width: 36,
            height: 36,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cure',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2F8F9D),
                  shadows: [
                    Shadow(
                      offset: Offset(1.5, 1.5),
                      blurRadius: 3,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
              Text(
                'NURTURE',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  letterSpacing: 1.5,
                  shadows: [
                    Shadow(
                      offset: Offset(1, 1),
                      blurRadius: 2,
                      color: Colors.black12,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      // ✅ Desktop → styled buttons, Mobile → hamburger menu
      actions: [
        if (MediaQuery.of(context).size.width > 600) ...[
          TextButton(
            onPressed: () => _openLogin(context),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF2F8F9D), // teal background
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Log In',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _openSignup(context),
            style: TextButton.styleFrom(
              side: const BorderSide(color: Colors.white), // outlined style
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Sign Up',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ] else ...[
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ]
      ],
    ),

    // ✅ Drawer for mobile
    drawer: Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: _darkTeal),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'CureNurture',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Compassion in Action',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('Log In'),
            onTap: () => _openLogin(context),
          ),
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Sign Up'),
            onTap: () => _openSignup(context),
          ),
        ],
      ),
    ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
  width: double.infinity,
  height: MediaQuery.of(context).size.height * 0.8,
  decoration: BoxDecoration(
    image: const DecorationImage(
      image: AssetImage('lib/assets/image/gradient_background.png'),
      fit: BoxFit.cover,
      colorFilter: ColorFilter.mode(
        Colors.black54, // 70% dark overlay
        BlendMode.darken,
      ),
    ),
  ),
  child: Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive font sizes based on width
          double headlineSize = constraints.maxWidth < 600 ? 22 : 32;
          double taglineSize = constraints.maxWidth < 600 ? 16 : 22;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Headline (bold, large, responsive)
              Text(
                'Together, we nurture healing.\nTogether, we save lives.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white,
                  fontSize: headlineSize,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  shadows: const [
                    Shadow(
                      offset: Offset(2, 2),
                      blurRadius: 4,
                      color: Colors.black45,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Subheadline (normal, italic, responsive)
              Text(
                'CureNurture — Compassion in Action.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white,
                  fontSize: taglineSize,
                  fontWeight: FontWeight.w400, // normal
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                  shadows: const [
                    Shadow(
                      offset: Offset(1.5, 1.5),
                      blurRadius: 3,
                      color: Colors.black38,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Buttons
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  ElevatedButton(
                    onPressed: () => _openDonation(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2F8F9D), // teal primary
                      foregroundColor: Colors.white,
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
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _openMoreDetails(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white70),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Learn More',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
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
                          'Verified Donation Activity',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        StreamBuilder<List<Map<String, String>>>(
                          stream: _verifiedDonationsStream,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final donations = snapshot.data ?? [];
                            return Column(
                              children: donations.map(_verifiedDonationCard).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Verified gifts show the latest trusted donations processed by CureNurture.',
                          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.6),
                        ),
                      ],
                    ),
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
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Log in before donating so we can keep your contribution secure and ensure every gift is correctly tracked for transparency and care.',
                          style: TextStyle(fontSize: 16, height: 1.7),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => _openMoreDetails(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Explore More Details', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoCard(
                        title: 'Gift of Care by UNLV',
                        subtitle: 'Distribution Date: Mar 26, 2025',
                        description: 'Highlights care access and community support through education and donation transparency.',
                      ),
                      _infoCard(
                        title: 'Health Matters by Cora Loco',
                        subtitle: 'Distribution Date: Apr 14, 2025',
                        description: 'Providing focused health awareness and donations for families in need.',
                      ),
                      _infoCard(
                        title: 'Angel Baby',
                        subtitle: 'Distribution Date: May 22, 2025',
                        description: 'Supporting children and families during critical healthcare challenges.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Container(
              color: _brandBlue,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clinic Contact Information',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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
