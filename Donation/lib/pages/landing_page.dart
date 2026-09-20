import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/brand.dart';
import '../widgets/decor.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'donation_option_page.dart';
import 'login_page.dart';
import 'more_details_page.dart';
import 'signup_page.dart';

/// The public face of CureNurture.
///
/// The page is written as a single argument, in order: what dialysis costs
/// a patient, what a donation does about it, how giving actually works,
/// and why the process can be trusted - with the donate action never more
/// than a scroll away and permanently pinned in the navigation bar.
///
/// All of the auth handling, navigation targets and the verified-donation
/// stream below are the ones this page has always used; only how they are
/// presented has changed.
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

  final ScrollController _scrollController = ScrollController();

  // Anchors for the navigation bar's in-page links.
  final GlobalKey _whyKey = GlobalKey();
  final GlobalKey _helpsKey = GlobalKey();
  final GlobalKey _howKey = GlobalKey();
  final GlobalKey _trustKey = GlobalKey();

  /// Number of dialysis centres on record. Null until loaded, and left null
  /// if the read fails - the tile is then hidden rather than showing a
  /// figure that might be wrong.
  int? _centerCount;

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

    _loadCenterCount();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _controller.dispose();
    _scrollController.dispose();
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

  /// Reads the dialysis centre list purely to show how many there are.
  ///
  /// Same table and filter the donation form already uses, so it needs no
  /// access the site does not already have. A failure is swallowed on
  /// purpose: the statistics band simply drops that one tile.
  Future<void> _loadCenterCount() async {
    try {
      final response = await Supabase.instance.client
          .from('clinics')
          .select('id')
          .or('status.is.null,status.neq.closed');

      if (!mounted) return;
      setState(() => _centerCount = (response as List).length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _centerCount = null);
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

  /// Smooth-scrolls to one of the in-page anchors.
  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: Motion.reduced(this.context)
          ? Duration.zero
          : const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubic,
      alignment: 0.04,
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

  /// The same verified records, reduced to the two totals shown in the
  /// statistics band. Nothing is estimated or projected - it is a count and
  /// a sum of rows that exist.
  Stream<({int count, double total})> get _verifiedTotalsStream {
    return Supabase.instance.client
        .from('donations')
        .stream(primaryKey: ['id'])
        .eq('status', 'verified')
        .map((data) {
          double total = 0;

          for (final item in data) {
            total +=
                double.tryParse(item['amount']?.toString() ?? '0') ?? 0;
          }

          return (count: data.length, total: total);
        });
  }

  bool _isMobile(double width) => Brand.isMobile(width);

  // ------------------------------------------------------------------ nav

  Widget _navLink(String label, GlobalKey target) {
    return TextButton(
      onPressed: () => _scrollTo(target),
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Brand.brandDeep),
        overlayColor: const WidgetStatePropertyAll(Brand.sky),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        shape: WidgetStateProperty.resolveWith((states) {
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: states.contains(WidgetState.focused)
                ? const BorderSide(color: Brand.brand, width: 2)
                : BorderSide.none,
          );
        }),
      ),
      child: Text(label),
    );
  }

  Widget _brandMark() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 46,
          width: 46,
          padding: const EdgeInsets.all(5),
          decoration: Brand.iconBox(Brand.sky, radius: 15),
          child: Image.asset(
            'lib/assets/image/CureNurture_logo.png',
            fit: BoxFit.contain,
            semanticLabel: 'CureNurture logo',
          ),
        ),
        const SizedBox(width: 11),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Cure',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Brand.teal,
                height: 1,
              ),
            ),
            Text(
              'NURTURE',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Brand.brandDeep,
                letterSpacing: 1.8,
                height: 1.3,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Brand.white,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 76,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      // A hairline keeps the pinned bar separated from the content that
      // scrolls beneath it.
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Brand.border),
      ),
      title: LayoutBuilder(
        builder: (context, constraints) {
          final width = MediaQuery.of(context).size.width;
          final mobile = _isMobile(width);
          final compact = width < 1180;

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: Brand.gutter(width)),
            child: Row(
              children: [
                _brandMark(),
                const Spacer(),

                // In-page links disappear first when space runs short; the
                // donate action never does.
                if (!compact) ...[
                  _navLink('Why it matters', _whyKey),
                  _navLink('Your impact', _helpsKey),
                  _navLink('How it works', _howKey),
                  _navLink('Transparency', _trustKey),
                  const SizedBox(width: 10),
                ],

                if (mobile) ...[
                  DonateButton(
                    // Shortened on the narrowest phones so the brand mark,
                    // donate action and menu always fit on one line.
                    label: width < 430 ? 'Give' : 'Donate',
                    onPressed: () => _openDonation(context),
                    semanticLabel: 'Donate now',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.menu_rounded,
                      color: Brand.brandDeep,
                    ),
                    tooltip: 'Menu',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onSelected: (value) {
                      if (value == 'login') _openLogin(context);
                      if (value == 'signup') _openSignup(context);
                      if (value == 'donate') _openDonation(context);
                      if (value == 'logout') _logout(context);
                      if (value == 'why') _scrollTo(_whyKey);
                      if (value == 'helps') _scrollTo(_helpsKey);
                      if (value == 'how') _scrollTo(_howKey);
                      if (value == 'trust') _scrollTo(_trustKey);
                    },
                    itemBuilder: (_) {
                      final links = <PopupMenuEntry<String>>[
                        const PopupMenuItem(
                          value: 'why',
                          child: Text('Why it matters'),
                        ),
                        const PopupMenuItem(
                          value: 'helps',
                          child: Text('Your impact'),
                        ),
                        const PopupMenuItem(
                          value: 'how',
                          child: Text('How it works'),
                        ),
                        const PopupMenuItem(
                          value: 'trust',
                          child: Text('Transparency'),
                        ),
                        const PopupMenuDivider(),
                      ];

                      if (_displayName == null) {
                        return [
                          ...links,
                          const PopupMenuItem(
                            value: 'donate',
                            child: Text('Donate'),
                          ),
                          const PopupMenuItem(
                            value: 'login',
                            child: Text('Log In'),
                          ),
                          const PopupMenuItem(
                            value: 'signup',
                            child: Text('Sign Up'),
                          ),
                        ];
                      }

                      return [
                        ...links,
                        const PopupMenuItem(
                          value: 'donate',
                          child: Text('Donate'),
                        ),
                        const PopupMenuItem(
                          value: 'logout',
                          child: Text('Logout'),
                        ),
                      ];
                    },
                  ),
                ] else if (_displayName == null) ...[
                  TextButton(
                    onPressed: () => _openLogin(context),
                    style: const ButtonStyle(
                      foregroundColor: WidgetStatePropertyAll(
                        Brand.brandDeep,
                      ),
                      overlayColor: WidgetStatePropertyAll(Brand.sky),
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    child: const Text('Log In'),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => _openSignup(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.brandDeep,
                        side: BorderSide(
                          color: Brand.brand.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        textStyle: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Sign Up'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DonateButton(
                    label: 'Donate Now',
                    onPressed: () => _openDonation(context),
                  ),
                ] else ...[
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Brand.sky,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        'Welcome, $_displayName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Brand.label(14, color: Brand.brandDeep),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Logout',
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Brand.brandDeep,
                    ),
                    onPressed: () => _logout(context),
                  ),
                  const SizedBox(width: 10),
                  DonateButton(
                    label: 'Donate Now',
                    onPressed: () => _openDonation(context),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------------- hero

  Widget _buildHero() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = MediaQuery.of(context).size.width;
        final mobile = _isMobile(width);

        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: Brand.deepGradient),
          child: Stack(
            children: [
              const Positioned.fill(child: FlowBackdrop()),
              const Positioned.fill(
                child: DriftField(color: Colors.white, count: 6),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: mobile ? 56 : 84,
                  bottom: mobile ? 44 : 72,
                ),
                child: ContentColumn(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: mobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _heroText(mobile: true),
                                const SizedBox(height: 40),
                                _heroCard(),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(flex: 7, child: _heroText()),
                                const SizedBox(width: 56),
                                Expanded(flex: 5, child: _heroCard()),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PulseLine(height: mobile ? 30 : 42),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _heroText({bool mobile = false}) {
    return Column(
      crossAxisAlignment: mobile
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: mobile ? Alignment.centerLeft : Alignment.centerLeft,
          child: const Eyebrow('Compassion in action', light: true),
        ),
        const SizedBox(height: 26),
        Text(
          'Help keep hope flowing.',
          textAlign: TextAlign.left,
          style: Brand.display(mobile ? 40 : 62, color: Colors.white),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'Dialysis does not stop. For the people who depend on it, treatment '
            'is a part of every week — and so is the cost of getting there. '
            'CureNurture lets you send support straight to the dialysis centres '
            'that care for them.',
            style: Brand.body(
              mobile ? 15.5 : 17.5,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ),
        const SizedBox(height: 34),
        if (mobile) ...[
          DonateButton(
            label: 'Donate Now',
            onPressed: () => _openDonation(context),
            expand: true,
            large: true,
          ),
          const SizedBox(height: 12),
          GhostButton(
            label: 'Learn More',
            icon: Icons.arrow_forward_rounded,
            light: true,
            expand: true,
            onPressed: () => _openMoreDetails(context),
          ),
        ] else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              DonateButton(
                label: 'Donate Now',
                onPressed: () => _openDonation(context),
                large: true,
              ),
              GhostButton(
                label: 'Learn More',
                icon: Icons.arrow_forward_rounded,
                light: true,
                onPressed: () => _openMoreDetails(context),
              ),
            ],
          ),
        const SizedBox(height: 32),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            TrustPill(
              icon: Icons.tune_rounded,
              text: 'You choose where it goes',
              light: true,
            ),
            TrustPill(
              icon: Icons.verified_rounded,
              text: 'Every gift is recorded',
              light: true,
            ),
            TrustPill(
              icon: Icons.visibility_off_rounded,
              text: 'Give anonymously if you prefer',
              light: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _heroCard() {
    final card = Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Brand.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: Brand.shadowLift,
      ),
      child: Column(
        children: [
          const CareGlyph(size: 96),
          const SizedBox(height: 22),
          Text(
            'Your donation becomes care.',
            textAlign: TextAlign.center,
            style: Brand.heading(25),
          ),
          const SizedBox(height: 12),
          Text(
            'Every contribution helps ease the weight of ongoing treatment, and '
            'tells a patient that someone they have never met decided to help.',
            textAlign: TextAlign.center,
            style: Brand.body(14.5),
          ),
          const SizedBox(height: 24),
          DonateButton(
            label: 'Donate Now',
            onPressed: () => _openDonation(context),
            expand: true,
          ),
        ],
      ),
    );

    return Floating(
      amplitude: 7,
      seconds: 9,
      child: card,
    );
  }

  // ----------------------------------------------------------- statistics

  /// Live figures drawn from verified donation records.
  ///
  /// Only ever renders what the database actually returns. When there are
  /// no verified donations yet it says so plainly rather than displaying a
  /// row of zeroes dressed up as achievements.
  Widget _buildStats() {
    return Transform.translate(
      offset: const Offset(0, -34),
      child: ContentColumn(
        child: StreamBuilder<({int count, double total})>(
          stream: _verifiedTotalsStream,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final waiting =
                snapshot.connectionState == ConnectionState.waiting;

            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 30,
              ),
              decoration: BoxDecoration(
                color: Brand.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Brand.border),
                boxShadow: Brand.shadowCard,
              ),
              child: Column(
                children: [
                  if (waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(color: Brand.teal),
                    )
                  else if (data == null || data.count == 0)
                    _statsEmpty()
                  else
                    ResponsiveRow(
                      breakpoint: 760,
                      gap: 24,
                      children: [
                        _statTile(
                          icon: Icons.verified_rounded,
                          accent: Brand.mint,
                          accentSoft: Brand.mintSoft,
                          value: data.count,
                          label: 'Verified donations recorded',
                        ),
                        _statTile(
                          icon: Icons.favorite_rounded,
                          accent: Brand.coral,
                          accentSoft: Brand.coralSoft,
                          value: data.total,
                          prefix: '₱',
                          label: 'Total contributed by donors',
                        ),
                        if (_centerCount != null)
                          _statTile(
                            icon: Icons.local_hospital_rounded,
                            accent: Brand.brand,
                            accentSoft: Brand.sky,
                            value: _centerCount!,
                            label: 'Dialysis centres you can support',
                          ),
                      ],
                    ),
                  const SizedBox(height: 22),
                  Text(
                    'These figures come directly from verified donation '
                    'records in the CureNurture system, and update as new '
                    'donations are recorded.',
                    textAlign: TextAlign.center,
                    style: Brand.body(12.5, color: Brand.textMuted),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statsEmpty() {
    return Column(
      children: [
        Container(
          height: 56,
          width: 56,
          decoration: Brand.iconBox(Brand.coralSoft, radius: 18),
          child: const Icon(
            Icons.volunteer_activism_rounded,
            color: Brand.coral,
            size: 28,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'No verified donations have been recorded yet.',
          textAlign: TextAlign.center,
          style: Brand.heading(21),
        ),
        const SizedBox(height: 10),
        Text(
          'Yours could be the first. Every donation recorded here helps a '
          'dialysis centre support the patients in its care.',
          textAlign: TextAlign.center,
          style: Brand.body(14.5),
        ),
        const SizedBox(height: 20),
        DonateButton(
          label: 'Be the first to give',
          onPressed: () => _openDonation(context),
        ),
      ],
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color accent,
    required Color accentSoft,
    required num value,
    required String label,
    String prefix = '',
  }) {
    final width = MediaQuery.of(context).size.width;

    return Reveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 50,
            width: 50,
            decoration: Brand.iconBox(accentSoft, radius: 16),
            child: Icon(icon, color: accent, size: 25),
          ),
          const SizedBox(height: 14),
          CountUp(
            value: value,
            prefix: prefix,
            style: Brand.display(
              Brand.isMobile(width) ? 30 : 36,
              color: Brand.textStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Brand.body(13.5, color: Brand.textMuted),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- why it matters

  Widget _buildWhyItMatters() {
    final width = MediaQuery.of(context).size.width;
    final mobile = _isMobile(width);

    return Container(
      key: _whyKey,
      color: Brand.white,
      padding: EdgeInsets.symmetric(vertical: Brand.sectionGap(width)),
      child: ContentColumn(
        child: ResponsiveRow(
          breakpoint: 960,
          gap: 56,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Reveal(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Why your support matters'),
                  const SizedBox(height: 18),
                  Text(
                    'Dialysis is not a one-time treatment.',
                    style: Brand.display(mobile ? 28 : 38),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'For people living with kidney failure, dialysis is an '
                    'ongoing part of life — often several sessions every week, '
                    'continuing for years. It keeps them alive, and it keeps '
                    'going.',
                    style: Brand.body(mobile ? 15 : 16.5),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'That rhythm carries a weight that reaches well beyond the '
                    'treatment itself: the journeys to and from a centre, the '
                    'medicines in between, the working hours given up, the '
                    'strain carried by an entire family. For many households '
                    'those costs build up faster than they can be met.',
                    style: Brand.body(mobile ? 15 : 16.5),
                  ),
                  const SizedBox(height: 26),
                  _checkLine('Treatment that repeats, week after week'),
                  _checkLine('Costs that reach beyond the clinic door'),
                  _checkLine('Families carrying the load together'),
                  const SizedBox(height: 30),
                  GhostButton(
                    label: 'Read more about our mission',
                    icon: Icons.arrow_forward_rounded,
                    expand: mobile,
                    onPressed: () => _openMoreDetails(context),
                  ),
                ],
              ),
            ),
            Reveal(
              delayMs: 140,
              child: _whyVisual(mobile: mobile),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 24,
            width: 24,
            margin: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(
              color: Brand.mintSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, size: 15, color: Brand.mint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Brand.label(15, color: Brand.textBody)),
          ),
        ],
      ),
    );
  }

  /// A quiet illustrative panel, so the argument above has something to sit
  /// beside instead of running as an unbroken wall of text.
  Widget _whyVisual({required bool mobile}) {
    return Container(
      padding: EdgeInsets.all(mobile ? 26 : 34),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Brand.sky, Brand.tealSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Brand.teal.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Floating(
                amplitude: 6,
                seconds: 8,
                child: CareGlyph(size: 112),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const PulseLine(color: Brand.teal, height: 34),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Brand.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                Text(
                  '“Support does not have to be large to matter. It has to '
                  'arrive.”',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: mobile ? 17 : 19,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: Brand.brandDeep,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'CureNurture — Compassion in Action',
                  textAlign: TextAlign.center,
                  style: Brand.body(12.5, color: Brand.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------- how your donation helps

  Widget _buildHowItHelps() {
    final width = MediaQuery.of(context).size.width;

    return Container(
      key: _helpsKey,
      color: Brand.canvas,
      padding: EdgeInsets.symmetric(vertical: Brand.sectionGap(width)),
      child: ContentColumn(
        child: Column(
          children: [
            const SectionHeading(
              eyebrow: 'How your donation helps',
              title: 'Four ways your gift supports dialysis care.',
              subtitle:
                  'These are the areas CureNurture directs donor support '
                  'toward. Where a particular donation lands depends on the '
                  'dialysis centre you choose when you give.',
            ),
            const SizedBox(height: 48),
            const ResponsiveRow(
              breakpoint: 900,
              gap: 20,
              stagger: true,
              equalHeight: true,
              children: [
                InfoCard(
                  icon: Icons.medical_services_rounded,
                  title: 'Treatment Support',
                  text:
                      'Helping dialysis centres keep treatment available for '
                      'the patients who rely on them.',
                  accent: Brand.teal,
                  accentSoft: Brand.tealSoft,
                ),
                InfoCard(
                  icon: Icons.favorite_rounded,
                  title: 'Patient Assistance',
                  text:
                      'Easing the treatment-related needs that surround care, '
                      'from getting to a centre to what follows.',
                  accent: Brand.coral,
                  accentSoft: Brand.coralSoft,
                  filled: true,
                ),
                InfoCard(
                  icon: Icons.local_hospital_rounded,
                  title: 'Dialysis Centre Support',
                  text:
                      'Strengthening the centres themselves, so access to '
                      'dialysis care holds steady in the communities they serve.',
                  accent: Brand.brand,
                  accentSoft: Brand.sky,
                ),
                InfoCard(
                  icon: Icons.groups_rounded,
                  title: 'Community Care',
                  text:
                      'Standing alongside patients and their families, so no '
                      'one faces long-term treatment feeling alone.',
                  accent: Brand.lavender,
                  accentSoft: Brand.lavenderSoft,
                ),
              ],
            ),
            const SizedBox(height: 44),
            Reveal(
              child: _inlineCta(
                title: 'Ready to help someone keep going?',
                text:
                    'It takes a few minutes, and you decide exactly where your '
                    'donation goes.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A quieter mid-page prompt. Deliberately lighter than the closing
  /// banner so the page asks without nagging.
  Widget _inlineCta({required String title, required String text}) {
    final width = MediaQuery.of(context).size.width;
    final mobile = _isMobile(width);

    return Container(
      padding: EdgeInsets.all(mobile ? 26 : 32),
      decoration: BoxDecoration(
        color: Brand.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Brand.coral.withValues(alpha: 0.22)),
        boxShadow: Brand.shadowSoft,
      ),
      child: ResponsiveRow(
        breakpoint: 760,
        gap: 22,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Brand.heading(mobile ? 20 : 23)),
              const SizedBox(height: 8),
              Text(text, style: Brand.body(14.5)),
            ],
          ),
          Align(
            alignment: mobile ? Alignment.centerLeft : Alignment.centerRight,
            child: DonateButton(
              label: 'Donate Now',
              onPressed: () => _openDonation(context),
              expand: mobile,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------- how it works

  /// The four steps below describe the donation flow exactly as the site
  /// performs it: pick anonymous or signed-in, fill in amount and payment
  /// channel, choose the allocation, and the donation is written to the
  /// donation records.
  Widget _buildHowItWorks() {
    final width = MediaQuery.of(context).size.width;

    return Container(
      key: _howKey,
      decoration: const BoxDecoration(gradient: Brand.brandGradient),
      child: Stack(
        children: [
          const Positioned.fill(child: FlowBackdrop(opacity: 0.7)),
          Padding(
            padding: EdgeInsets.symmetric(vertical: Brand.sectionGap(width)),
            child: ContentColumn(
              child: Column(
                children: [
                  const SectionHeading(
                    eyebrow: 'How it works',
                    title: 'Giving takes four steps.',
                    subtitle:
                        'No account is required unless you want your donation '
                        'recorded under your name.',
                    light: true,
                  ),
                  const SizedBox(height: 48),
                  ResponsiveRow(
                    breakpoint: 980,
                    gap: 18,
                    equalHeight: true,
                    children: [
                      _stepCard(
                        number: '01',
                        icon: Icons.how_to_reg_rounded,
                        title: 'Choose how to give',
                        text:
                            'Donate anonymously, or sign in to your donor '
                            'account so the gift is recorded under your name.',
                        delay: 0,
                      ),
                      _stepCard(
                        number: '02',
                        icon: Icons.edit_note_rounded,
                        title: 'Enter your details',
                        text:
                            'Set the amount you would like to give and pick '
                            'your payment channel — GCash or bank transfer.',
                        delay: 90,
                      ),
                      _stepCard(
                        number: '03',
                        icon: Icons.alt_route_rounded,
                        title: 'Decide where it goes',
                        text:
                            'Send it to a specific dialysis centre, have one '
                            'assigned at random, or split it equally across '
                            'every centre.',
                        delay: 180,
                      ),
                      _stepCard(
                        number: '04',
                        icon: Icons.verified_rounded,
                        title: 'Your gift is recorded',
                        text:
                            'The donation is saved to CureNurture’s verified '
                            'records and routed to the centre or centres you '
                            'chose.',
                        delay: 270,
                      ),
                    ],
                  ),
                  const SizedBox(height: 44),
                  Reveal(
                    child: DonateButton(
                      label: 'Start your donation',
                      onPressed: () => _openDonation(context),
                      large: true,
                      expand: _isMobile(width),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCard({
    required String number,
    required IconData icon,
    required String title,
    required String text,
    required int delay,
  }) {
    return Reveal(
      delayMs: delay,
      child: HoverLift(
        lift: 8,
        builder: (context, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: hovered ? 1 : 0.96),
              borderRadius: BorderRadius.circular(24),
              boxShadow: hovered ? Brand.shadowLift : Brand.shadowSoft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 50,
                      width: 50,
                      decoration: Brand.iconBox(Brand.sky, radius: 16),
                      child: Icon(icon, color: Brand.brand, size: 25),
                    ),
                    const Spacer(),
                    Text(
                      number,
                      style: TextStyle(
                        fontFamily: Brand.displayFont,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Brand.brand.withValues(alpha: 0.28),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(title, style: Brand.heading(18)),
                const SizedBox(height: 9),
                Text(text, style: Brand.body(14)),
              ],
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------------- transparency

  Widget _buildTransparency() {
    final width = MediaQuery.of(context).size.width;

    return Container(
      key: _trustKey,
      color: Brand.white,
      padding: EdgeInsets.symmetric(vertical: Brand.sectionGap(width)),
      child: ContentColumn(
        child: Column(
          children: [
            const SectionHeading(
              eyebrow: 'Transparency',
              title: 'You should know what happens to your donation.',
              subtitle:
                  'Trust is not a claim a donation site gets to make about '
                  'itself. These are simply the things CureNurture does with '
                  'every gift it receives.',
            ),
            const SizedBox(height: 48),
            const ResponsiveRow(
              breakpoint: 900,
              gap: 20,
              stagger: true,
              equalHeight: true,
              children: [
                InfoCard(
                  icon: Icons.receipt_long_rounded,
                  title: 'Every donation is recorded',
                  text:
                      'Each gift is written to CureNurture’s donation records '
                      'with its amount, payment channel and date — and the '
                      'verified ones appear publicly further down this page.',
                  accent: Brand.mint,
                  accentSoft: Brand.mintSoft,
                ),
                InfoCard(
                  icon: Icons.alt_route_rounded,
                  title: 'You choose the destination',
                  text:
                      'Your donation is not pooled out of sight. You pick the '
                      'dialysis centre yourself, or knowingly hand that choice '
                      'to a random or equal split.',
                  accent: Brand.brand,
                  accentSoft: Brand.sky,
                ),
                InfoCard(
                  icon: Icons.pie_chart_rounded,
                  title: 'Equal splits are itemised',
                  text:
                      'When a donation is shared across every centre, each '
                      'centre’s exact share is recorded separately, so the '
                      'split is on the record and not just a promise.',
                  accent: Brand.teal,
                  accentSoft: Brand.tealSoft,
                ),
              ],
            ),
            const SizedBox(height: 32),
            Reveal(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Brand.canvas,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Brand.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: Brand.iconBox(Brand.sky, radius: 13),
                      child: const Icon(
                        Icons.privacy_tip_rounded,
                        color: Brand.brand,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Donating anonymously means exactly that: no name and '
                        'no email address is stored against the donation, and '
                        'it appears in the public list below as "Anonymous".',
                        style: Brand.body(14, color: Brand.textBody),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------- verified donations

  Widget _buildVerifiedDonations() {
    final width = MediaQuery.of(context).size.width;
    final mobile = _isMobile(width);

    return Container(
      color: Brand.canvas,
      padding: EdgeInsets.symmetric(vertical: Brand.sectionGap(width)),
      child: ContentColumn(
        child: ResponsiveRow(
          breakpoint: 960,
          gap: 44,
          children: [
            Reveal(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Live activity', color: Brand.mint),
                  const SizedBox(height: 18),
                  Text(
                    'Verified donation activity.',
                    style: Brand.display(mobile ? 28 : 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'These are real donations that have been verified in the '
                    'CureNurture system, newest first. The list updates on its '
                    'own as new gifts are recorded.',
                    style: Brand.body(mobile ? 15 : 16.5),
                  ),
                  const SizedBox(height: 28),
                  DonateButton(
                    label: 'Add your donation',
                    onPressed: () => _openDonation(context),
                    expand: mobile,
                  ),
                ],
              ),
            ),
            Reveal(delayMs: 120, child: _verifiedList()),
          ],
        ),
      ),
    );
  }

  Widget _verifiedList() {
    return StreamBuilder<List<Map<String, String>>>(
      stream: _verifiedDonationsStream,
      builder: (context, snapshot) {
        final donations = snapshot.data ?? [];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: Brand.card(radius: 28),
            child: const Center(
              child: CircularProgressIndicator(color: Brand.teal),
            ),
          );
        }

        if (donations.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(30),
            decoration: Brand.card(radius: 28),
            child: Column(
              children: [
                Container(
                  height: 50,
                  width: 50,
                  decoration: Brand.iconBox(Brand.sky, radius: 16),
                  child: const Icon(
                    Icons.inbox_rounded,
                    color: Brand.brand,
                    size: 25,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No verified donations yet.',
                  style: Brand.heading(18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Once donations are verified they will appear here '
                  'automatically.',
                  textAlign: TextAlign.center,
                  style: Brand.body(14),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: Brand.card(radius: 28, shadow: Brand.shadowCard),
          child: Column(
            children: [
              for (int i = 0; i < donations.take(5).length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _verifiedDonationCard(donations[i]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _verifiedDonationCard(Map<String, String> donation) {
    return HoverLift(
      lift: 3,
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hovered ? Brand.mintSoft : Brand.canvas,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hovered
                  ? Brand.mint.withValues(alpha: 0.35)
                  : Brand.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: Brand.iconBox(Brand.mintSoft, radius: 15),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Brand.mint,
                  size: 23,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      donation['name'] ?? 'Anonymous',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Brand.label(15.5, color: Brand.textStrong),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      donation['date'] ?? '',
                      style: Brand.body(12.5, color: Brand.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    donation['amount'] ?? '',
                    style: const TextStyle(
                      fontFamily: Brand.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Brand.textStrong,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Brand.mintSoft,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      donation['status'] ?? 'Verified',
                      style: const TextStyle(
                        color: Brand.mint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ final CTA

  Widget _buildFinalCta() {
    final width = MediaQuery.of(context).size.width;
    final mobile = _isMobile(width);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: Brand.deepGradient),
      child: Stack(
        children: [
          const Positioned.fill(child: FlowBackdrop()),
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: mobile ? 72 : 100,
            ),
            child: ContentColumn(
              maxWidth: 860,
              child: Reveal(
                child: Column(
                  children: [
                    Floating(
                      amplitude: 6,
                      seconds: 8,
                      child: Container(
                        height: 78,
                        width: 78,
                        decoration: BoxDecoration(
                          gradient: Brand.coralGradient,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: Brand.shadowCoral,
                        ),
                        child: const Icon(
                          Icons.volunteer_activism_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Your support can help make dialysis care more '
                      'accessible.',
                      textAlign: TextAlign.center,
                      style: Brand.display(
                        mobile ? 30 : 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Give once, give anonymously, or give to the centre '
                      'closest to your heart. However you choose to help, it '
                      'reaches someone for whom treatment is not optional.',
                      textAlign: TextAlign.center,
                      style: Brand.body(
                        mobile ? 15 : 17,
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                    const SizedBox(height: 34),
                    if (mobile) ...[
                      DonateButton(
                        label: 'Donate Now',
                        onPressed: () => _openDonation(context),
                        expand: true,
                        large: true,
                      ),
                      const SizedBox(height: 12),
                      GhostButton(
                        label: 'Learn More',
                        icon: Icons.arrow_forward_rounded,
                        light: true,
                        expand: true,
                        onPressed: () => _openMoreDetails(context),
                      ),
                    ] else
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        alignment: WrapAlignment.center,
                        children: [
                          DonateButton(
                            label: 'Donate Now',
                            onPressed: () => _openDonation(context),
                            large: true,
                          ),
                          GhostButton(
                            label: 'Learn More',
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
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- footer

  Widget _buildFooter() {
    final width = MediaQuery.of(context).size.width;
    final mobile = _isMobile(width);

    return Container(
      width: double.infinity,
      color: Brand.ink,
      padding: EdgeInsets.only(top: mobile ? 48 : 64, bottom: 28),
      child: ContentColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResponsiveRow(
              breakpoint: 760,
              gap: 40,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'lib/assets/image/CureNurture_logo.png',
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                          semanticLabel: 'CureNurture logo',
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'CureNurture',
                          style: TextStyle(
                            fontFamily: Brand.displayFont,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 21,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Text(
                        'Connecting donors with the dialysis centres caring '
                        'for patients who depend on ongoing treatment.',
                        style: Brand.body(
                          14,
                          color: Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explore',
                      style: Brand.label(14, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    _footerLink('Why it matters', () => _scrollTo(_whyKey)),
                    _footerLink('Your impact', () => _scrollTo(_helpsKey)),
                    _footerLink('How it works', () => _scrollTo(_howKey)),
                    _footerLink('Transparency', () => _scrollTo(_trustKey)),
                    _footerLink(
                      'About CureNurture',
                      () => _openMoreDetails(context),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to help?',
                      style: Brand.label(14, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your donation goes to the dialysis centre you choose.',
                      style: Brand.body(
                        13.5,
                        color: Colors.white.withValues(alpha: 0.70),
                      ),
                    ),
                    const SizedBox(height: 18),
                    DonateButton(
                      label: 'Donate Now',
                      onPressed: () => _openDonation(context),
                      expand: mobile,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 36),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 20),
            mobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CureNurture — Compassion in Action.',
                        style: Brand.body(
                          13,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '© ${DateTime.now().year} CureNurture',
                        style: Brand.body(
                          13,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Text(
                        'CureNurture — Compassion in Action.',
                        style: Brand.body(
                          13,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '© ${DateTime.now().year} CureNurture',
                        style: Brand.body(
                          13,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _footerLink(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TextButton(
        onPressed: onTap,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.hovered)
                ? Colors.white
                : Colors.white.withValues(alpha: 0.72);
          }),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.06),
          ),
          alignment: Alignment.centerLeft,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
          shape: WidgetStateProperty.resolveWith((states) {
            return RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: states.contains(WidgetState.focused)
                  ? const BorderSide(color: Colors.white, width: 1.6)
                  : BorderSide.none,
            );
          }),
        ),
        child: Text(label),
      ),
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      body: RevealScope(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(child: _buildHero()),
            SliverToBoxAdapter(child: _buildStats()),
            SliverToBoxAdapter(child: _buildWhyItMatters()),
            SliverToBoxAdapter(child: _buildHowItHelps()),
            SliverToBoxAdapter(child: _buildHowItWorks()),
            SliverToBoxAdapter(child: _buildTransparency()),
            SliverToBoxAdapter(child: _buildVerifiedDonations()),
            SliverToBoxAdapter(child: _buildFinalCta()),
            SliverToBoxAdapter(child: _buildFooter()),
          ],
        ),
      ),
    );
  }
}
