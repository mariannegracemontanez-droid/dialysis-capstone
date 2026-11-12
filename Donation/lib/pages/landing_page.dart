import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/public_donation_service.dart';
import '../theme/brand.dart';
import '../widgets/decor.dart';
import '../widgets/motion.dart';
import '../widgets/site_nav.dart';
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

    // Keeps the navigation's active link in step with scrolling.
    _scrollController.addListener(_updateActiveSection);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateActiveSection);
    _activeSection.dispose();
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

  /// The floating navigation capsule: its top margin and height. The hero
  /// starts underneath it, and in-page scrolling stops this far below the
  /// top so a section's heading is never hidden behind the bar.
  static const double _navReserve = SiteNav.reserve;

  /// Smooth-scrolls so the section starts just below the floating bar.
  void _scrollTo(GlobalKey key) {
    final target = key.currentContext?.findRenderObject();
    if (target == null || !_scrollController.hasClients) return;

    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport == null) return;

    final position = _scrollController.position;
    final offset =
        (viewport.getOffsetToReveal(target, 0).offset - _navReserve - 12)
            .clamp(position.minScrollExtent, position.maxScrollExtent);

    if (Motion.reduced(context)) {
      position.jumpTo(offset);
    } else {
      position.animateTo(
        offset,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  // ------------------------------------------------------ active section

  /// The in-page section the navigation marks as active: the one under a
  /// line a little below the floating bar. Null while the visitor is on the
  /// hero/statistics or below the last linked section. Kept in a notifier
  /// so scrolling only rebuilds the four links, not the page.
  final ValueNotifier<GlobalKey?> _activeSection = ValueNotifier(null);

  bool _activeCheckScheduled = false;

  /// Scroll listeners fire as soon as the offset changes - before the page
  /// is laid out again - so section positions read at that moment are from
  /// the previous frame (a long jump could leave the wrong link active).
  /// Measure once, after the frame's layout, instead.
  void _updateActiveSection() {
    if (_activeCheckScheduled) return;
    _activeCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeCheckScheduled = false;
      _measureActiveSection();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _measureActiveSection() {
    if (!mounted) return;
    const line = _navReserve + 120;

    GlobalKey? active;
    for (final key in [_whyKey, _helpsKey, _howKey, _trustKey]) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= line && top + box.size.height > line) active = key;
    }

    if (_activeSection.value != active) _activeSection.value = active;
  }

  /// The verified totals shown in the statistics band. Nothing is
  /// estimated or projected - it is a count and a sum of rows that exist.
  late final Stream<({int count, double total})> _verifiedTotalsStream =
      _pausedWhenUnused(PublicDonationService().totals());

  /// Shares one poller between rebuilds and stops polling while nothing on
  /// screen listens (e.g. after leaving the page).
  static Stream<T> _pausedWhenUnused<T>(Stream<T> source) {
    return source.asBroadcastStream(
      onCancel: (subscription) => subscription.pause(),
      onListen: (subscription) {
        if (subscription.isPaused) subscription.resume();
      },
    );
  }

  bool _isMobile(double width) => Brand.isMobile(width);

  // ------------------------------------------------------------------ nav

  /// Light turquoise accent, used for the footer's column rules.
  static const Color _navTurquoise = Color(0xFF7FD0D9);

  /// Sign Up and Donate Now share one compact size, proportionate to the
  /// 64px capsule.
  static const double _navActionWidth = 150;
  static const double _navActionHeight = 42;

  Widget _navLink(String label, GlobalKey target) {
    return ValueListenableBuilder<GlobalKey?>(
      valueListenable: _activeSection,
      builder: (context, active, _) => _NavLink(
        label: label,
        active: active == target,
        onPressed: () => _scrollTo(target),
      ),
    );
  }

  /// Sign Up keeps its outlined style, at the compact navigation size.
  Widget _signUpButton() {
    return SizedBox(
      width: _navActionWidth,
      height: _navActionHeight,
      child: OutlinedButton(
        onPressed: () => _openSignup(context),
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(Brand.brandDeep),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return Brand.border;
            if (states.contains(WidgetState.hovered)) return Brand.sky;
            return Colors.white.withValues(alpha: 0.6);
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: Brand.brandDeep, width: 2.2);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return BorderSide(
                color: Brand.brand.withValues(alpha: 0.85),
                width: 1.4,
              );
            }
            return BorderSide(
              color: Brand.brand.withValues(alpha: 0.45),
              width: 1.4,
            );
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
          animationDuration: const Duration(milliseconds: 180),
        ),
        child: const Text('Sign Up', maxLines: 1, softWrap: false),
      ),
    );
  }

  /// Menu for the in-page links on screens too narrow to show them, plus
  /// the account actions on phones.
  Widget _navMenu({required bool includeAccount}) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu_rounded, color: Brand.brandDeep),
      tooltip: 'Menu',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          const PopupMenuItem(value: 'why', child: Text('Why it matters')),
          const PopupMenuItem(value: 'helps', child: Text('Your impact')),
          const PopupMenuItem(value: 'how', child: Text('How it works')),
          const PopupMenuItem(value: 'trust', child: Text('Transparency')),
        ];

        // Tablet widths keep Sign Up and Donate Now in the bar, so their
        // menu adds only Log In (for signed-out visitors).
        if (!includeAccount) {
          if (_displayName != null) return links;
          return [
            ...links,
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'login', child: Text('Log In')),
          ];
        }

        if (_displayName == null) {
          return [
            ...links,
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'donate', child: Text('Donate')),
            const PopupMenuItem(value: 'login', child: Text('Log In')),
            const PopupMenuItem(value: 'signup', child: Text('Sign Up')),
          ];
        }

        return [
          ...links,
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'donate', child: Text('Donate')),
          const PopupMenuItem(value: 'logout', child: Text('Logout')),
        ];
      },
    );
  }


  /// The navigation bar: a frosted, soft-white capsule floating over the
  /// top of the page. It sits in a layer above the scroll view, so the
  /// hero's navy ground continues underneath it and content scrolls behind
  /// its glass - the same rounded shape at the top and while scrolling.
  Widget _buildNavBar() {
    // Section positions change with layout as well as with scrolling.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _measureActiveSection());

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = MediaQuery.of(context).size.width;
        final mobile = _isMobile(width);

        // From this width the in-page links sit in the bar itself; below it
        // they move into the menu. _NavBarLayout places them from measured
        // widths, so the bar cannot overflow whatever font is used.
        final showLinks = width >= 1180;

        final links = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _navLink('Why it matters', _whyKey),
            const SizedBox(width: 4),
            _navLink('Your impact', _helpsKey),
            const SizedBox(width: 4),
            _navLink('How it works', _howKey),
            const SizedBox(width: 4),
            _navLink('Transparency', _trustKey),
          ],
        );

        final Widget actions;
        if (mobile) {
          actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NavDonateButton(
                // Shortened on the narrowest phones so the brand mark,
                // donate action and menu always fit on one line.
                label: width < 430 ? 'Give' : 'Donate',
                width: width < 430 ? 96 : 120,
                height: _navActionHeight,
                onPressed: () => _openDonation(context),
              ),
              _navMenu(includeAccount: true),
            ],
          );
        } else if (_displayName == null) {
          actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _signUpButton(),
              const SizedBox(width: 10),
              NavDonateButton(
                label: 'Donate Now',
                width: _navActionWidth,
                height: _navActionHeight,
                onPressed: () => _openDonation(context),
              ),
              if (!showLinks) _navMenu(includeAccount: false),
            ],
          );
        } else {
          actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
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
              const SizedBox(width: 4),
              NavDonateButton(
                label: 'Donate Now',
                width: _navActionWidth,
                height: _navActionHeight,
                onPressed: () => _openDonation(context),
              ),
              if (!showLinks) _navMenu(includeAccount: false),
            ],
          );
        }

        final content = showLinks
            ? CustomMultiChildLayout(
                delegate: _NavBarLayout(),
                children: [
                  LayoutId(id: _NavSlot.brand, child: const BrandMark()),
                  LayoutId(
                    id: _NavSlot.links,
                    child: FittedBox(fit: BoxFit.scaleDown, child: links),
                  ),
                  LayoutId(id: _NavSlot.actions, child: actions),
                ],
              )
            : Row(
                children: [
                  const BrandMark(),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ),
                ],
              );

        return NavCapsule(child: content);
      },
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
              // Clipped so the backdrop's soft glow stays inside the hero
              // instead of tinting the statistics card below it.
              const Positioned.fill(child: ClipRect(child: FlowBackdrop())),
              const Positioned.fill(
                child: DriftField(color: Colors.white, count: 6),
              ),
              Padding(
                padding: EdgeInsets.only(
                  // The floating navigation sits over the top of the hero.
                  top: (mobile ? 56 : 84) + _navReserve,
                  bottom: mobile ? 44 : 72,
                ),
                child: ContentColumn(
                  // Slightly wider than the reading column, so the text sits
                  // nearer the left edge and the illustration nearer the
                  // right (the About page hero uses the same width).
                  maxWidth: Brand.maxContent + 80,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      // Side by side from 1000px; below that the text comes
                      // first and the Ongoing Care visual follows, aligned to
                      // the same left edge and capped so it scales in
                      // proportion.
                      child: width < 1000
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _heroText(mobile: mobile),
                                SizedBox(height: mobile ? 40 : 48),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 560,
                                    ),
                                    child: _heroCareVisual(compact: mobile),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              // Two equal columns with one fixed gap: a clear
                              // 50/50 partition. Both columns start at the
                              // same top edge, so their labels ("Compassion
                              // in action" and "Ongoing care") sit on one
                              // line. Centring them vertically put the two
                              // labels at different heights, because the
                              // columns differ in height.
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _heroText()),
                                const SizedBox(width: 64),
                                Expanded(
                                  child: _heroCareVisual(compact: false),
                                ),
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
    final width = MediaQuery.of(context).size.width;
    final tablet = Brand.isTablet(width);
    final headlineSize = mobile ? 40.0 : (tablet ? 50.0 : 60.0);

    return Column(
      crossAxisAlignment: mobile
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Eyebrow('Compassion in action', light: true),
        ),
        SizedBox(height: mobile ? 22 : 26),
        ConstrainedBox(
          // Keeps the headline to a balanced two lines on wide screens
          // instead of one long line with a stray word.
          constraints: const BoxConstraints(maxWidth: 600),
          child: Text(
            'Help keep hope flowing.',
            textAlign: TextAlign.left,
            style: Brand.display(headlineSize, color: Colors.white),
          ),
        ),
        SizedBox(height: mobile ? 18 : 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
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
        SizedBox(height: mobile ? 28 : 34),
        // Donate Now and Learn More side by side (both 54px tall, so they
        // align exactly); stacked full-width on phones. They wrap rather
        // than overflow on narrow tablets.
        if (mobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DonateButton(
                label: 'Donate Now',
                onPressed: () => _openDonation(context),
                expand: true,
              ),
              const SizedBox(height: 12),
              GhostButton(
                label: 'Learn More',
                icon: Icons.arrow_forward_rounded,
                light: true,
                expand: true,
                onPressed: () => _openMoreDetails(context),
              ),
            ],
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DonateButton(
                label: 'Donate Now',
                onPressed: () => _openDonation(context),
              ),
              GhostButton(
                label: 'Learn More',
                icon: Icons.arrow_forward_rounded,
                light: true,
                onPressed: () => _openMoreDetails(context),
              ),
            ],
          ),
        SizedBox(height: mobile ? 26 : 34),
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

  /// Right side of the hero: the Ongoing Care visual, with the hero's
  /// donation message as its caption, drawn straight onto the hero's
  /// navy-to-teal ground - no card, border or shadow. A soft teal glow
  /// gives the circuit depth; only the week schedule sits on a faint
  /// translucent panel, for readability; the quotation is set against a thin
  /// turquoise rule rather than in a box.
  Widget _heroCareVisual({required bool compact}) {
    const turquoise = Color(0xFF7FD0D9);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Teal glow behind the kidneys and circuit, fading into the hero.
        Positioned(
          left: -60,
          right: -60,
          top: -40,
          height: compact ? 300 : 380,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.55,
                  colors: [
                    Brand.teal.withValues(alpha: 0.34),
                    Brand.teal.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Eyebrow('Ongoing care', light: true),
            ),
            SizedBox(height: compact ? 6 : 10),
            SizedBox(
              height: compact ? 150 : 200,
              child: const CareCircuit(),
            ),
            SizedBox(height: compact ? 10 : 12),
            // The hero's donation message, set directly on the gradient as
            // the caption to the illustration - no card or box.
            Text(
              'Your donation becomes care.',
              style: Brand.heading(compact ? 22 : 25, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Every contribution helps ease the weight of ongoing treatment, and '
              'tells a patient that someone they have never met decided to help.',
              style: Brand.body(
                compact ? 14.5 : 15,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
            SizedBox(height: compact ? 18 : 22),
            _careWeek(turquoise: turquoise, mobile: compact),
            SizedBox(height: compact ? 20 : 26),
            Container(
              padding: const EdgeInsets.only(left: 18),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: turquoise.withValues(alpha: 0.55),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    color: Brand.coralBright,
                    size: 26,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Support does not have to be large to matter. '
                    'It has to arrive.',
                    style: TextStyle(
                      fontFamily: Brand.displayFont,
                      fontSize: compact ? 16 : 18,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'CureNurture — Compassion in Action',
                    style: Brand.body(
                      12.5,
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// An illustrative week: seven day markers with three treatment days
  /// highlighted, captioned as an illustration rather than a schedule.
  /// The one translucent panel in the hero visual, so the days stay legible
  /// over the gradient.
  Widget _careWeek({required Color turquoise, required bool mobile}) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const treatment = {0, 2, 4};
    final marker = mobile ? 30.0 : 34.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        mobile ? 14 : 18,
        16,
        mobile ? 14 : 18,
        14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < days.length; i++)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: marker,
                      width: marker,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: treatment.contains(i)
                            ? turquoise.withValues(alpha: 0.95)
                            : Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: treatment.contains(i)
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: treatment.contains(i)
                          ? const Icon(
                              Icons.water_drop_rounded,
                              size: 15,
                              color: Brand.brandDeep,
                            )
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      days[i],
                      style: TextStyle(
                        fontFamily: Brand.displayFont,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(
                          alpha: treatment.contains(i) ? 0.92 : 0.55,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 6,
            spacing: 12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 9,
                    width: 9,
                    decoration: BoxDecoration(
                      color: turquoise,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Treatment session',
                    style: Brand.body(
                      12.5,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
              Text(
                'An illustrative week of care',
                style: Brand.body(
                  12.5,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- statistics

  /// Live figures drawn from verified donation records.
  ///
  /// Only ever renders what the database actually returns. When there are
  /// no verified donations yet it says so plainly rather than displaying a
  /// row of zeroes dressed up as achievements.
  Widget _buildStats() {
    // Sits just below the hero. (It used to be pulled 34px up into the hero,
    // but the hero is painted above later slivers, so the card's top edge
    // was hidden behind it.)
    return Padding(
      padding: EdgeInsets.only(
        top: _isMobile(MediaQuery.of(context).size.width) ? 28 : 40,
      ),
      child: ContentColumn(
        child: StreamBuilder<({int count, double total})>(
          stream: _verifiedTotalsStream,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final waiting =
                snapshot.connectionState == ConnectionState.waiting;

            final mobile = _isMobile(MediaQuery.of(context).size.width);

            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: mobile ? 20 : 32,
                vertical: mobile ? 26 : 34,
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
                    _statsRow([
                      _statTile(
                        icon: Icons.verified_rounded,
                        accent: Brand.mint,
                        accentSoft: Brand.mintSoft,
                        value: data.count,
                        label: 'Verified donations recorded',
                      ),
                      _statTile(
                        icon: Icons.volunteer_activism_rounded,
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
                    ]),
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

  /// Lays the statistic tiles out side by side with hairline dividers on
  /// wider screens, and stacked with horizontal dividers on phones.
  Widget _statsRow(List<Widget> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Container(height: 1, color: Brand.borderSoft),
                  ),
                tiles[i],
              ],
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(width: 1, color: Brand.borderSoft),
                  ),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      },
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
          // One consistent icon treatment for every figure: a soft disc with
          // a fine ring in the figure's accent colour.
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: accentSoft,
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(height: 16),
          CountUp(
            value: value,
            prefix: prefix,
            style: Brand.display(
              Brand.isMobile(width) ? 32 : 40,
              color: Brand.brandDeep,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 3,
            width: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Brand.label(14, color: Brand.textMuted),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- why it matters

  /// "Why your support matters" - text only (its right-side visual moved to
  /// the hero). On wide screens it reads as an editorial two-column layout:
  /// label and heading on the left, the paragraphs, supporting statements
  /// and mission link on the right, in their original order. Stacked on
  /// narrower screens.
  Widget _buildWhyItMatters() {
    final width = MediaQuery.of(context).size.width;
    final mobile = _isMobile(width);

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Why your support matters'),
        const SizedBox(height: 18),
        Text(
          'Dialysis is not a one-time treatment.',
          style: Brand.display(mobile ? 28 : 40),
        ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
    );

    return Container(
      key: _whyKey,
      color: Brand.white,
      padding: EdgeInsets.symmetric(vertical: Brand.sectionGap(width)),
      child: ContentColumn(
        child: Reveal(
          child: width >= 960
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: heading),
                    const SizedBox(width: 64),
                    Expanded(
                      flex: 7,
                      child: Padding(
                        // Lines the first paragraph up with the heading.
                        padding: const EdgeInsets.only(top: 52),
                        child: body,
                      ),
                    ),
                  ],
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [heading, const SizedBox(height: 18), body],
                  ),
                ),
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

    // A message-only banner (its Donate Now button was removed): a coral
    // heart mark beside the heading and sentence, on a soft white-to-coral
    // wash with a coral accent edge, so it reads as a finished closing note
    // for the four cards above rather than an empty call-to-action.
    final icon = Container(
      height: 56,
      width: 56,
      decoration: BoxDecoration(
        color: Brand.coralSoft,
        shape: BoxShape.circle,
        border: Border.all(color: Brand.coral.withValues(alpha: 0.24)),
      ),
      child: const Icon(
        Icons.favorite_rounded,
        color: Brand.coral,
        size: 26,
      ),
    );

    final copy = Column(
      crossAxisAlignment:
          mobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: mobile ? TextAlign.center : TextAlign.start,
          style: Brand.heading(mobile ? 20 : 23),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: mobile ? TextAlign.center : TextAlign.start,
          style: Brand.body(mobile ? 14.5 : 15.5),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Brand.white, Brand.coralSoft.withValues(alpha: 0.85)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Brand.coral.withValues(alpha: 0.20)),
        boxShadow: Brand.shadowSoft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Brand.coral, width: 4)),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 24 : 36,
            vertical: mobile ? 26 : 30,
          ),
          child: mobile
              ? Column(children: [icon, const SizedBox(height: 16), copy])
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 22),
                    Expanded(child: copy),
                  ],
                ),
        ),
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
                            'Set the amount you would like to give. Pick and '
                            'pay securely with GCash.',
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
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: hovered ? 1 : 0.96),
              borderRadius: BorderRadius.circular(24),
              boxShadow: hovered ? Brand.shadowLift : Brand.shadowSoft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Slim teal accent that lengthens on hover - ties the four
                // steps together as one sequence.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  height: 3,
                  width: hovered ? 56 : 32,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Brand.teal.withValues(alpha: hovered ? 0.9 : 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Brand.sky,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Brand.brand.withValues(
                            alpha: hovered ? 0.40 : 0.22,
                          ),
                        ),
                      ),
                      child: Icon(icon, color: Brand.brand, size: 25),
                    ),
                    const Spacer(),
                    Text(
                      number,
                      style: TextStyle(
                        fontFamily: Brand.displayFont,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Brand.teal.withValues(
                          alpha: hovered ? 0.75 : 0.45,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(title, style: Brand.heading(18.5)),
                const SizedBox(height: 10),
                Text(text, style: Brand.body(14.2)),
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
                      // The clause about verified gifts appearing "further
                      // down this page" was removed with that section.
                      'Each gift is written to CureNurture’s donation records '
                      'with its amount, payment channel and date.',
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
                      decoration: BoxDecoration(
                        color: Brand.sky,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Brand.brand.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Icon(
                        Icons.privacy_tip_rounded,
                        color: Brand.brand,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        // The clause about appearing "in the public list
                        // below" was removed with that list.
                        'Donating anonymously means exactly that: no name and '
                        'no email address is stored against the donation.',
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
                    // One centred action (Learn More removed from this band).
                    Center(
                      child: DonateButton(
                        label: 'Donate Now',
                        onPressed: () => _openDonation(context),
                        expand: mobile,
                        large: true,
                      ),
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

    final brandColumn = Column(
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
    );

    final exploreColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerHeading('Explore'),
        const SizedBox(height: 10),
        _footerLink('Why it matters', () => _scrollTo(_whyKey)),
        _footerLink('Your impact', () => _scrollTo(_helpsKey)),
        _footerLink('How it works', () => _scrollTo(_howKey)),
        _footerLink('Transparency', () => _scrollTo(_trustKey)),
        _footerLink('About CureNurture', () => _openMoreDetails(context)),
      ],
    );

    // "Ready to help?" keeps its message; its Donate Now button was removed
    // as redundant (donate stays in the navigation bar, hero card and
    // closing banner directly above the footer).
    final readyColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerHeading('Ready to help?'),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.volunteer_activism_rounded,
                size: 18,
                color: Brand.coralBright.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  'Your donation goes to the dialysis centre you choose.',
                  style: Brand.body(
                    13.5,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      width: double.infinity,
      color: Brand.ink,
      padding: EdgeInsets.only(top: mobile ? 48 : 64, bottom: 28),
      child: ContentColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  brandColumn,
                  const SizedBox(height: 32),
                  exploreColumn,
                  const SizedBox(height: 28),
                  readyColumn,
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: brandColumn),
                  const SizedBox(width: 40),
                  Expanded(flex: 3, child: exploreColumn),
                  const SizedBox(width: 40),
                  Expanded(flex: 4, child: readyColumn),
                ],
              ),
            const SizedBox(height: 40),
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

  /// Column heading in the footer, with a short turquoise rule beneath it.
  Widget _footerHeading(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Brand.label(14.5, color: Colors.white)),
        const SizedBox(height: 8),
        Container(
          height: 2,
          width: 22,
          decoration: BoxDecoration(
            color: _navTurquoise.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
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
            // Montserrat ships at 400 and 700 only (see Brand.displayFont).
            TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
            ),
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
      body: Stack(
        children: [
          _buildPage(),
          // The navigation capsule floats above the page, so the hero runs
          // underneath it and content scrolls behind its frosted glass.
          Positioned(top: 0, left: 0, right: 0, child: _buildNavBar()),
        ],
      ),
    );
  }

  Widget _buildPage() {
    return RevealScope(
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(child: _buildStats()),
          SliverToBoxAdapter(child: _buildWhyItMatters()),
          SliverToBoxAdapter(child: _buildHowItHelps()),
          SliverToBoxAdapter(child: _buildHowItWorks()),
          SliverToBoxAdapter(child: _buildTransparency()),
          SliverToBoxAdapter(child: _buildFinalCta()),
          SliverToBoxAdapter(child: _buildFooter()),
        ],
      ),
    );
  }
}

enum _NavSlot { brand, links, actions }

/// Places the navigation bar's three groups.
///
/// The brand mark sits on the left and the actions on the right, and both
/// always get their natural size. The links are centred on the bar itself
/// when they fit there without touching either side; otherwise they are
/// centred in the space between the brand and the actions. They are given
/// only that space, and are wrapped in a scale-down FittedBox, so on an
/// unusually narrow window or wide font they shrink slightly rather than
/// overflow.
class _NavBarLayout extends MultiChildLayoutDelegate {
  static const double _gap = 24;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);

    final brand = layoutChild(_NavSlot.brand, loose);
    final actions = layoutChild(
      _NavSlot.actions,
      BoxConstraints.loose(
        Size(math.max(0, size.width - brand.width - _gap), size.height),
      ),
    );

    final left = brand.width + _gap;
    final right = size.width - actions.width - _gap;
    final space = math.max(0.0, right - left);

    final links = layoutChild(
      _NavSlot.links,
      BoxConstraints.loose(Size(space, size.height)),
    );

    double y(Size child) => (size.height - child.height) / 2;

    positionChild(_NavSlot.brand, Offset(0, y(brand)));
    positionChild(
      _NavSlot.actions,
      Offset(size.width - actions.width, y(actions)),
    );

    // True centre of the bar if the links fit there; otherwise the centre
    // of the free space between brand and actions.
    final centred = (size.width - links.width) / 2;
    final x = (centred >= left && centred + links.width <= right)
        ? centred
        : left + (space - links.width) / 2;
    positionChild(_NavSlot.links, Offset(x, y(links)));
  }

  @override
  bool shouldRelayout(covariant _NavBarLayout oldDelegate) => false;
}

/// An in-page link in the navigation capsule.
///
/// Three clearly different looks, cross-faded in 200 ms:
///   * normal  - body-blue label, no background;
///   * hover   - soft sky pill behind a deep-navy label;
///   * active  - (the section currently in view) a teal-tinted pill and a
///               deep-navy label - no underline or other mark. Hovering an
///               active link deepens the teal slightly.
/// Pressing scales the pill down slightly; keyboard focus draws a navy
/// ring. Reduced-motion settings remove the transitions.
class _NavLink extends StatefulWidget {
  const _NavLink({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    final duration =
        reduced ? Duration.zero : const Duration(milliseconds: 200);
    final active = widget.active;

    final Color background;
    if (active) {
      background = Brand.teal.withValues(alpha: _hovered ? 0.18 : 0.13);
    } else if (_hovered) {
      background = Brand.sky;
    } else {
      background = Brand.sky.withValues(alpha: 0);
    }

    // Hover comes straight from MouseRegion: FocusableActionDetector only
    // reports hover in the "traditional" highlight mode, which is not
    // guaranteed, so relying on it could leave the hover state invisible.
    return Semantics(
      button: true,
      selected: active,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: reduced ? Duration.zero : const Duration(milliseconds: 120),
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: _focused
                      ? Brand.brandDeep
                      : Brand.brandDeep.withValues(alpha: 0),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    style: TextStyle(
                      fontFamily: Brand.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: (active || _hovered)
                          ? Brand.brandDeep
                          : Brand.textBody,
                    ),
                    child: Text(widget.label, maxLines: 1, softWrap: false),
                  ),
                ],
              ),
            ),
        ),
          ),
        ),
      ),
    );
  }
}

