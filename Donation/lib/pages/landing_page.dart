import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'donation_page.dart';
import 'donation_option_page.dart';
import 'login_page.dart';
import 'more_details_page.dart';
import 'signup_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  String? _displayName;
  late final StreamSubscription _authSubscription;

  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  final Color _brandBlue = const Color(0xFF0D6EFD);
  final Color _darkTeal = const Color(0xFF164D66);
  final Color _midTeal = const Color(0xFF1F6F8B);
  final Color _accentTeal = const Color(0xFF2F8F9D);
  final Color _softBlue = const Color(0xFFEAF7FB);
  final Color _surface = const Color(0xFFF6FAFD);
  final Color _ink = const Color(0xFF17324D);

  @override
  void initState() {
    super.initState();

    _loadAuthState();

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      event,
    ) {
      _loadAuthState();
    });

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAuthState() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => _displayName = null);
      return;
    }

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      final name = profile?['full_name'] as String?;

      if (!mounted) return;
      setState(() {
        _displayName = (name?.isNotEmpty == true) ? name : user.email;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _displayName = user.email);
    }
  }

  void _openLogin(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  void _openSignup(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SignupPage()));
  }

  void _openDonation(BuildContext context) {
  Navigator.of(
    context,
  ).push(
    MaterialPageRoute(
      builder: (_) => const DonationOptionPage(),
    ),
  );
}
  void _openMoreDetails(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MoreDetailsPage()));
  }

  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    setState(() => _displayName = null);

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
                  ? DateTime.parse(
                      item['created_at'],
                    ).toLocal().toString().split(' ')[0]
                  : '',
              'amount': '₱ ${item['amount'] ?? 0}',
              'status': 'Verified',
            };
          }).toList();
        });
  }

  bool _isMobile(double width) => width < 760;
  bool _isTablet(double width) => width >= 760 && width < 1050;

  Widget _fadeSlide({required Widget child, int delay = 0}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 650 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _maxWidth({required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: child,
      ),
    );
  }

  Widget _sectionPadding({
    required Widget child,
    Color? color,
    EdgeInsets? padding,
  }) {
    return Container(
      width: double.infinity,
      color: color,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 28, vertical: 86),
      child: _maxWidth(child: child),
    );
  }

  Widget _sectionHeader({
    required String eyebrow,
    required String title,
    required String subtitle,
    bool light = false,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withOpacity(0.14)
                : _accentTeal.withOpacity(0.10),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: light
                  ? Colors.white.withOpacity(0.18)
                  : _accentTeal.withOpacity(0.16),
            ),
          ),
          child: Text(
            eyebrow.toUpperCase(),
            style: TextStyle(
              color: light ? Colors.white : _accentTeal,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: light ? Colors.white : _ink,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: light
                  ? Colors.white.withOpacity(0.80)
                  : Colors.blueGrey.shade700,
              fontSize: 16,
              height: 1.75,
            ),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String text,
    required VoidCallback onPressed,
    IconData icon = Icons.favorite_rounded,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? _accentTeal,
        foregroundColor: foregroundColor ?? Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      ),
    );
  }

  Widget _secondaryButton({
    required String text,
    required VoidCallback onPressed,
    IconData icon = Icons.info_outline_rounded,
    bool light = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(text),
      style: OutlinedButton.styleFrom(
        foregroundColor: light ? Colors.white : _darkTeal,
        side: BorderSide(
          color: light ? Colors.white.withOpacity(0.7) : _darkTeal,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      ),
    );
  }

  Widget _glassBadge({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.74),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      elevation: 0,
      backgroundColor: Colors.white.withOpacity(0.98),
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 78,
      titleSpacing: 24,
      title: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.asset(
              'lib/assets/image/CureNurture_logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cure',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _accentTeal,
                  height: 1,
                ),
              ),
              Text(
                'NURTURE',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _darkTeal,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Builder(
          builder: (context) {
            final width = MediaQuery.of(context).size.width;

            if (_isMobile(width)) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.menu_rounded, color: _darkTeal),
                  onSelected: (value) {
                    if (value == 'login') _openLogin(context);
                    if (value == 'signup') _openSignup(context);
                    if (value == 'donate') _openDonation(context);
                    if (value == 'logout') _logout(context);
                  },
                  itemBuilder: (_) {
                    if (_displayName == null) {
                      return const [
                        PopupMenuItem(value: 'donate', child: Text('Donate')),
                        PopupMenuItem(value: 'login', child: Text('Log In')),
                        PopupMenuItem(value: 'signup', child: Text('Sign Up')),
                      ];
                    }

                    return const [
                      PopupMenuItem(value: 'donate', child: Text('Donate')),
                      PopupMenuItem(value: 'logout', child: Text('Logout')),
                    ];
                  },
                ),
              );
            }

            if (_displayName == null) {
              return Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => _openLogin(context),
                      style: TextButton.styleFrom(
                        foregroundColor: _darkTeal,
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      child: const Text('Log In'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _openSignup(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _darkTeal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _primaryButton(
                      text: 'Donate',
                      icon: Icons.favorite_rounded,
                      onPressed: () => _openDonation(context),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _softBlue,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Welcome, $_displayName',
                      style: TextStyle(
                        color: _darkTeal,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Logout',
                    icon: Icon(Icons.logout_rounded, color: _darkTeal),
                    onPressed: () => _logout(context),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHero() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = _isMobile(constraints.maxWidth);

        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('lib/assets/image/gradient_background.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: mobile ? 22 : 28,
              vertical: mobile ? 62 : 88,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _darkTeal.withOpacity(0.96),
                  _midTeal.withOpacity(0.86),
                  _accentTeal.withOpacity(0.62),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: _maxWidth(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: mobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _heroText(mobile: true),
                            const SizedBox(height: 32),
                            _heroCard(),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(flex: 6, child: _heroText()),
                            const SizedBox(width: 48),
                            Expanded(flex: 4, child: _heroCard()),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _heroText({bool mobile = false}) {
    return Column(
      crossAxisAlignment: mobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: Colors.white.withOpacity(0.22)),
          ),
          child: const Text(
            'Compassion in Action',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Help dialysis patients continue their fight for life.',
          textAlign: mobile ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.white,
            fontSize: mobile ? 38 : 58,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'CureNurture connects generous donors with patients who need urgent support for dialysis treatment, medicines, transportation, and essential care.',
          textAlign: mobile ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.white.withOpacity(0.86),
            fontSize: mobile ? 16 : 18,
            height: 1.75,
          ),
        ),
        const SizedBox(height: 34),
        Wrap(
          alignment: mobile ? WrapAlignment.center : WrapAlignment.start,
          spacing: 14,
          runSpacing: 14,
          children: [
            _primaryButton(
              text: 'Donate Now',
              icon: Icons.volunteer_activism_rounded,
              onPressed: () => _openDonation(context),
              backgroundColor: Colors.white,
              foregroundColor: _darkTeal,
            ),
            _secondaryButton(
              text: 'Learn More',
              icon: Icons.arrow_forward_rounded,
              light: true,
              onPressed: () => _openMoreDetails(context),
            ),
          ],
        ),
        const SizedBox(height: 34),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _trustPill(Icons.verified_rounded, 'Verified donations'),
            _trustPill(Icons.lock_rounded, 'Secure giving'),
            _trustPill(Icons.favorite_rounded, 'Patient-centered'),
          ],
        ),
      ],
    );
  }

  Widget _trustPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return _fadeSlide(
      delay: 180,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Colors.white.withOpacity(0.20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 36,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: _softBlue,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      Icons.health_and_safety_rounded,
                      color: _accentTeal,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Your donation becomes care.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Every contribution helps ease the financial burden of treatment and reminds patients that they are not alone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      height: 1.65,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _glassBadge(
              icon: Icons.receipt_long_rounded,
              title: 'Transparent activity',
              subtitle: 'Verified donation records are shown below.',
            ),
            const SizedBox(height: 12),
            _glassBadge(
              icon: Icons.groups_rounded,
              title: 'Community-powered',
              subtitle: 'Support comes from people who choose to care.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImpactStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 36),
      child: _maxWidth(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mobile = _isMobile(constraints.maxWidth);

              final cards = [
                _impactMini(
                  Icons.medical_services_rounded,
                  'Treatment Support',
                  'Helping patients continue dialysis care.',
                ),
                _impactMini(
                  Icons.directions_car_rounded,
                  'Transport Assistance',
                  'Supporting hospital and clinic visits.',
                ),
                _impactMini(
                  Icons.medication_rounded,
                  'Medicine & Supplies',
                  'Reducing the pressure of daily expenses.',
                ),
                _impactMini(
                  Icons.favorite_rounded,
                  'Hope & Dignity',
                  'Reminding families that they are not alone.',
                ),
              ];

              return mobile
                  ? Column(
                      children: cards
                          .map(
                            (card) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: card,
                            ),
                          )
                          .toList(),
                    )
                  : Row(
                      children: cards
                          .map((card) => Expanded(child: card))
                          .toList(),
                    );
            },
          ),
        ),
      ),
    );
  }

  Widget _impactMini(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: _accentTeal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    height: 1.35,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhoWeAre() {
    return _sectionPadding(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 42, 28, 90),
      child: Column(
        children: [
          _sectionHeader(
            eyebrow: 'Who We Are',
            title: 'A donation platform designed around compassion and trust.',
            subtitle:
                'CureNurture supports dialysis patients facing the financial challenges of life-saving treatment by connecting them with donors who want to create meaningful impact.',
          ),
          const SizedBox(height: 46),
          LayoutBuilder(
            builder: (context, constraints) {
              final mobile = _isMobile(constraints.maxWidth);

              final cards = [
                _featureCard(
                  icon: Icons.health_and_safety_rounded,
                  title: 'Patient-centered support',
                  text:
                      'The platform focuses on helping patients access care, comfort, and dignity while facing kidney failure.',
                ),
                _featureCard(
                  icon: Icons.volunteer_activism_rounded,
                  title: 'Meaningful giving',
                  text:
                      'Donors can contribute to a mission where every act of generosity helps reduce real-life treatment burdens.',
                ),
                _featureCard(
                  icon: Icons.verified_user_rounded,
                  title: 'Trust-driven experience',
                  text:
                      'Verified donation activity builds confidence and helps show that support is active and transparent.',
                ),
              ];

              return mobile
                  ? Column(
                      children: cards
                          .map(
                            (card) => Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: card,
                            ),
                          )
                          .toList(),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 18),
                        Expanded(child: cards[1]),
                        const SizedBox(width: 18),
                        Expanded(child: cards[2]),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return _fadeSlide(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFE5EEF3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.045),
              blurRadius: 26,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 58,
              width: 58,
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: _accentTeal, size: 30),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: TextStyle(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              text,
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                height: 1.7,
                fontSize: 14.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurpose() {
    return _sectionPadding(
      color: _surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = _isMobile(constraints.maxWidth);

          final left = Container(
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_darkTeal, _midTeal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(34),
              boxShadow: [
                BoxShadow(
                  color: _darkTeal.withOpacity(0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: mobile
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  height: 62,
                  width: 62,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Why CureNurture exists',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Kidney failure is not only a medical condition. It is a continuous emotional, physical, and financial struggle. CureNurture was created to make support more accessible for patients and families who need help the most.',
                  textAlign: mobile ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    height: 1.75,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 26),
                _secondaryButton(
                  text: 'Understand the Mission',
                  icon: Icons.arrow_forward_rounded,
                  light: true,
                  onPressed: () => _openMoreDetails(context),
                ),
              ],
            ),
          );

          final right = Container(
            padding: const EdgeInsets.all(34),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: const Color(0xFFE3EEF4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 26,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your generosity can help with:',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 22),
                _checkItem('Dialysis treatment sessions'),
                _checkItem('Medical supplies and medications'),
                _checkItem('Transportation for hospital visits'),
                _checkItem('Emergency procedures'),
                _checkItem('Daily living essentials'),
                _checkItem('Family stability and hope'),
              ],
            ),
          );

          return mobile
              ? Column(children: [left, const SizedBox(height: 20), right])
              : Row(
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 24),
                    Expanded(child: right),
                  ],
                );
        },
      ),
    );
  }

  Widget _checkItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Container(
            height: 28,
            width: 28,
            decoration: BoxDecoration(
              color: _accentTeal.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, color: _accentTeal, size: 18),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.blueGrey.shade800,
                fontWeight: FontWeight.w800,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 90),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkTeal, _midTeal, _accentTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: _maxWidth(
        child: Column(
          children: [
            _sectionHeader(
              eyebrow: 'How It Works',
              title: 'A simple journey from compassion to real support.',
              subtitle:
                  'The landing page guides visitors from awareness to action, making the donation experience feel trustworthy, purposeful, and emotionally clear.',
              light: true,
            ),
            const SizedBox(height: 46),
            LayoutBuilder(
              builder: (context, constraints) {
                final mobile = _isMobile(constraints.maxWidth);

                final steps = [
                  _stepCard(
                    number: '01',
                    icon: Icons.search_rounded,
                    title: 'Learn the cause',
                    text:
                        'Visitors understand the challenges dialysis patients face and why support matters.',
                  ),
                  _stepCard(
                    number: '02',
                    icon: Icons.favorite_rounded,
                    title: 'Choose to donate',
                    text:
                        'A clear call-to-action encourages donors to take the next meaningful step.',
                  ),
                  _stepCard(
                    number: '03',
                    icon: Icons.verified_rounded,
                    title: 'Donation is verified',
                    text:
                        'Verified activity increases confidence and strengthens transparency.',
                  ),
                  _stepCard(
                    number: '04',
                    icon: Icons.health_and_safety_rounded,
                    title: 'Patients receive hope',
                    text:
                        'Support helps reduce financial pressure and restores dignity to families.',
                  ),
                ];

                return mobile
                    ? Column(
                        children: steps
                            .map(
                              (step) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: step,
                              ),
                            )
                            .toList(),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: steps[0]),
                          const SizedBox(width: 16),
                          Expanded(child: steps[1]),
                          const SizedBox(width: 16),
                          Expanded(child: steps[2]),
                          const SizedBox(width: 16),
                          Expanded(child: steps[3]),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepCard({
    required String number,
    required IconData icon,
    required String title,
    required String text,
  }) {
    return _fadeSlide(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              number,
              style: TextStyle(
                color: _accentTeal.withOpacity(0.55),
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: _accentTeal, size: 28),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: _ink,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                height: 1.65,
                fontSize: 13.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransparency() {
    return _sectionPadding(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = _isMobile(constraints.maxWidth);

          final cards = [
            _statementCard(
              icon: Icons.visibility_rounded,
              title: 'Our Vision',
              text:
                  'We envision a world where every dialysis patient has access to essential care without financial barriers.',
            ),
            _statementCard(
              icon: Icons.shield_rounded,
              title: 'Transparency',
              text:
                  'Trust is the foundation of CureNurture. Verified donation activity helps donors feel confident and informed.',
            ),
            _statementCard(
              icon: Icons.handshake_rounded,
              title: 'Community Care',
              text:
                  'Every act of giving creates a ripple of compassion for patients, families, and the community around them.',
            ),
          ];

          return Column(
            children: [
              _sectionHeader(
                eyebrow: 'Commitment',
                title: 'Designed to feel credible, warm, and reassuring.',
                subtitle:
                    'A persuasive donation site should not only look beautiful. It should make visitors feel safe, informed, and ready to help.',
              ),
              const SizedBox(height: 46),
              mobile
                  ? Column(
                      children: cards
                          .map(
                            (card) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: card,
                            ),
                          )
                          .toList(),
                    )
                  : Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 18),
                        Expanded(child: cards[1]),
                        const SizedBox(width: 18),
                        Expanded(child: cards[2]),
                      ],
                    ),
            ],
          );
        },
      ),
    );
  }

  Widget _statementCard({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFD8EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _accentTeal, size: 38),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              color: _ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              color: Colors.blueGrey.shade700,
              height: 1.7,
              fontSize: 14.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedDonations() {
    return _sectionPadding(
      color: _surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = _isMobile(constraints.maxWidth);

          final intro = Column(
            crossAxisAlignment: mobile
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _brandBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'LIVE TRUST SIGNAL',
                  style: TextStyle(
                    color: _brandBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Verified Donation Activity',
                textAlign: mobile ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: _ink,
                  fontSize: 34,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Showing verified donations makes the page feel active and credible. It reassures visitors that others are already contributing to the mission.',
                textAlign: mobile ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  height: 1.75,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 26),
              _primaryButton(
                text: 'Become a Donor',
                icon: Icons.volunteer_activism_rounded,
                onPressed: () => _openDonation(context),
              ),
            ],
          );

          final streamList = StreamBuilder<List<Map<String, String>>>(
            stream: _verifiedDonationsStream,
            builder: (context, snapshot) {
              final donations = snapshot.data ?? [];

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  padding: const EdgeInsets.all(36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFFE4EEF3)),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(color: _accentTeal),
                  ),
                );
              }

              if (donations.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFFE4EEF3)),
                  ),
                  child: Text(
                    'No verified donations yet. Once donations are verified, they will appear here.',
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      height: 1.6,
                    ),
                  ),
                );
              }

              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFE4EEF3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.045),
                      blurRadius: 26,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  children: donations
                      .take(5)
                      .map((donation) => _verifiedDonationCard(donation))
                      .toList(),
                ),
              );
            },
          );

          return mobile
              ? Column(
                  children: [intro, const SizedBox(height: 30), streamList],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: intro),
                    const SizedBox(width: 36),
                    Expanded(child: streamList),
                  ],
                );
        },
      ),
    );
  }

  Widget _verifiedDonationCard(Map<String, String> donation) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3EEF4)),
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: _brandBlue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.verified_rounded, color: _brandBlue),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  donation['name'] ?? 'Anonymous',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  donation['date'] ?? '',
                  style: TextStyle(
                    color: Colors.blueGrey.shade500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                donation['amount'] ?? '',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _brandBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  donation['status'] ?? 'Verified',
                  style: TextStyle(
                    color: _brandBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinalCta() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 94),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkTeal, _midTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: _maxWidth(
        child: Container(
          padding: const EdgeInsets.all(42),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Column(
            children: [
              Container(
                height: 78,
                width: 78,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Turn compassion into life-changing support.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(
                  'Your support can transform despair into hope and struggle into strength. Together, we nurture healing. Together, we save lives.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    height: 1.75,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: [
                  _primaryButton(
                    text: 'Donate Now',
                    icon: Icons.favorite_rounded,
                    onPressed: () => _openDonation(context),
                    backgroundColor: Colors.white,
                    foregroundColor: _darkTeal,
                  ),
                  _secondaryButton(
                    text: 'Learn More',
                    icon: Icons.arrow_forward_rounded,
                    light: true,
                    onPressed: () => _openMoreDetails(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0F3548),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
      child: _maxWidth(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mobile = _isMobile(constraints.maxWidth);

            return mobile
                ? Column(
                    children: [
                      _footerBrand(),
                      const SizedBox(height: 18),
                      Text(
                        'CureNurture — Compassion in Action.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.72)),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _footerBrand(),
                      const Spacer(),
                      Text(
                        'CureNurture — Compassion in Action.',
                        style: TextStyle(color: Colors.white.withOpacity(0.72)),
                      ),
                    ],
                  );
          },
        ),
      ),
    );
  }

  Widget _footerBrand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'lib/assets/image/CureNurture_logo.png',
          width: 36,
          height: 36,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        const Text(
          'CureNurture',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(child: _buildImpactStrip()),
          SliverToBoxAdapter(child: _buildWhoWeAre()),
          SliverToBoxAdapter(child: _buildPurpose()),
          SliverToBoxAdapter(child: _buildHowItWorks()),
          SliverToBoxAdapter(child: _buildTransparency()),
          SliverToBoxAdapter(child: _buildVerifiedDonations()),
          SliverToBoxAdapter(child: _buildFinalCta()),
          SliverToBoxAdapter(child: _buildFooter()),
        ],
      ),
    );
  }
}
