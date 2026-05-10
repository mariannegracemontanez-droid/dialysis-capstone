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
  return Supabase.instance.client
      .from('donations')
      .stream(primaryKey: ['id'])
      .eq('status', 'verified')
      .order('created_at', ascending: false)
      .map((data) {
        return data.map<Map<String, String>>((item) {
          return {
            'name': item['name'] ?? 'Anonymous',
            'date': item['created_at'] != null
                ? DateTime.parse(item['created_at'])
                    .toLocal()
                    .toString()
                    .split(' ')[0]
                : '',
            'amount': '₱ ${item['amount'] ?? 0}',
            'status': 'Verified',
          };
        }).toList();
      });
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
  borderRadius: BorderRadius.circular(20),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 10,
      offset: const Offset(0, 5),
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
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cure',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2F8F9D),
            ),
          ),
          Text(
            'NURTURE',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    ],
  ),

  actions: [
    const SizedBox(width: 16),

    if (_displayName == null) ...[
      Padding(
        padding: const EdgeInsets.only(right: 24),
        child: Row(
          children: [
            TextButton(
              onPressed: () => _openLogin(context),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF2F8F9D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Log In'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => _openSignup(context),
              style: TextButton.styleFrom(
                side: const BorderSide(color: Colors.white),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Sign Up'),
            ),
          ],
        ),
      ),
    ] else ...[
      Padding(
        padding: const EdgeInsets.only(right: 24),
        child: Row(
          children: [
            Text(
              'Welcome, $_displayName',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => _logout(context),
            ),
          ],
        ),
      ),
    ],
  ],
),
    

 body: SingleChildScrollView(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [

      // HERO
      Container(
        height: 320,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('lib/assets/image/gradient_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Together, we nurture healing.\nTogether, we save lives.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'CureNurture — Compassion in Action.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () => _openDonation(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F8F9D),
                      ),
                      child: const Text('Donate Now'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => _openMoreDetails(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Learn More'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),

      // DONATE STRIP

      // WHO WE ARE
      Container(
        padding: const EdgeInsets.all(24),
        color: const Color(0xFF1F5E7D),
        child: const Column(
        children: [
        Text(
            'Who We Are',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'CureNurture is a compassionate, community-centered platform dedicated to supporting dialysis patients who are struggling with the financial challenges of life-saving treatment. We connect generous donors with individuals and families in need, ensuring that no one faces kidney failure alone—or without the means to survive.\n\nAt CureNurture, we believe every person deserves access to consistent dialysis care, dignity, and hope. Our mission is to make that possible through an innovative and transparent donation system designed to uplift lives.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.6),
          ),
        ],
      ),
      ),

      const SizedBox(height: 40),

      // PURPOSE + WHY
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: Row(
    children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF38A6DB),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Our Purpose',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
              SizedBox(height: 10),
              Text(
                'CureNurture was created to bridge the gap between patients who urgently need financial assistance and donors who want to make a meaningful impact.\n\n• Dialysis treatment sessions\n• Medical supplies and medications\n• Transportation for hospital visits\n• Emergency procedures\n• Daily living essentials\n\nWe are committed to ensuring that every contribution goes directly to improving the health and well-being of the patients we serve.',
                style: TextStyle(color: Colors.white, height: 1.6),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF38A6DB),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Why We Do It',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
              SizedBox(height: 10),
              Text(
                'Kidney failure is not just a medical condition—it is a lifelong struggle.\n\nCureNurture exists to change that reality.\n\nYour generosity can:\n• Extend and improve a patient’s life\n• Reduce the burden on families\n• Bring comfort, stability, and hope\n• Create a ripple effect of compassion',
                style: TextStyle(color: Colors.white, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
),
    const SizedBox(height: 40),



     const SizedBox(height: 40),

      // VISION
      Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _sectionCard(
            title: 'Our Vision',
            content:
          'At CureNurture, we envision a world where every dialysis patient has access to essential care without financial barriers.',
      color: const Color(0xFFDBF3FF),
   ),
      ),

      const SizedBox(height: 16),

      // TRANSPARENCY
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _sectionCard(
          title: 'Our Commitment to Transparency',
          content:
              'Trust is the foundation of CureNurture. Every donation is processed with integrity, accountability, and patient well-being at the center.',
          color: const Color(0xFFDBF3FF),
    ),
      ),

      const SizedBox(height: 40),

      // VERIFIED DONATIONS
      Padding(
        padding: const EdgeInsets.all(16),
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
                final donations = snapshot.data ?? [];
                return Column(
                  children: donations.map(_verifiedDonationCard).toList(),
                );
              },
            ),
          ],
        ),
      ),
    Container(
  padding: const EdgeInsets.all(32),
  color: const Color(0xFFD9EEF2),
  child: Column(
    children: [
      const Text(
        'Join Us',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Your support can transform despair into hope and struggle into strength. '
        'By partnering with CureNurture, you become part of a life-changing mission—one that uplifts patients, strengthens families, and restores hope to those who need it most.',
        textAlign: TextAlign.center,
        style: TextStyle(height: 1.6),
      ),
      const SizedBox(height: 20),
      const Text(
        'Together, we nurture healing. Together, we save lives.\nCureNurture — Compassion in Action.',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 20),

      ElevatedButton(
        onPressed: () => _openDonation(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2F8F9D),
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text('Donate Now'),
      ),
    ],
  ),
),
    ],
  ),
),
  );
}
}