import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../widgets/decor.dart';
import '../widgets/motion.dart';
import '../widgets/site_nav.dart';
import '../widgets/ui.dart';
import 'donation_option_page.dart';

/// "About CureNurture" - the page behind the landing page's Learn More.
///
/// Presentation only. It is built from the same design system as the
/// landing page (Brand tokens, ContentColumn, SectionHeading, InfoCard,
/// the donate button) so the two read as one site. Navigation is
/// unchanged: back returns to the landing page, Donate Now opens the
/// existing donation flow.
class MoreDetailsPage extends StatefulWidget {
  const MoreDetailsPage({super.key});

  @override
  State<MoreDetailsPage> createState() => _MoreDetailsPageState();
}

class _MoreDetailsPageState extends State<MoreDetailsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  static const Color _turquoise = Color(0xFF7FD0D9);

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _openDonation() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DonationOptionPage()),
    );
  }

  // ---------------------------------------------------------------- header

  /// The same floating capsule as the landing page: back button and logo on
  /// the left, the compact Donate Now on the right.
  Widget _buildNavBar(double width) {
    final mobile = Brand.isMobile(width);

    return NavCapsule(
      child: Row(
        children: [
          NavBackButton(onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 12),
          const BrandMark(),
          const Spacer(),
          NavDonateButton(
            label: mobile ? (width < 430 ? 'Give' : 'Donate') : 'Donate Now',
            width: mobile ? (width < 430 ? 96 : 120) : 150,
            height: 42,
            onPressed: _openDonation,
          ),
          if (mobile) const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ hero

  Widget _buildHero(double width) {
    final mobile = Brand.isMobile(width);
    final stacked = width < 1000;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('About CureNurture', light: true),
        SizedBox(height: mobile ? 20 : 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Text(
            'Care That Goes Beyond Every Treatment.',
            style: Brand.display(
              mobile ? 34 : (Brand.isTablet(width) ? 44 : 52),
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(height: mobile ? 16 : 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Text(
            'CureNurture connects compassionate donors with dialysis patients '
            'who need support for treatment, medication, transportation, and '
            'other essential care needs.',
            style: Brand.body(
              mobile ? 15.5 : 17,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ),
      ],
    );

    // The page's three existing highlights are the right column's visual:
    // three translucent cards on the gradient, evenly spaced.
    final highlights = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _heroPoint(
          icon: Icons.health_and_safety_rounded,
          title: 'Patient-centered',
          text: 'Built around dialysis patients and their families.',
        ),
        const SizedBox(height: 14),
        _heroPoint(
          icon: Icons.volunteer_activism_rounded,
          title: 'Community-powered',
          text: 'Driven by donors who want to create real impact.',
        ),
        const SizedBox(height: 14),
        _heroPoint(
          icon: Icons.verified_rounded,
          title: 'Transparent giving',
          text: 'Donation activity is verified for donor confidence.',
        ),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: Brand.deepGradient),
      child: Stack(
        children: [
          const Positioned.fill(child: ClipRect(child: FlowBackdrop())),
          Padding(
            padding: EdgeInsets.only(
              // The floating navigation sits over the top of the hero.
              top: (mobile ? 52 : 80) + SiteNav.reserve,
              bottom: mobile ? 52 : 80,
            ),
            child: ContentColumn(
              // Same hero width as the landing page.
              maxWidth: Brand.maxContent + 80,
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        text,
                        SizedBox(height: mobile ? 32 : 40),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: highlights,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      // Two equal columns with one fixed gap, centred
                      // vertically - the same 50/50 partition as the landing
                      // page hero.
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: text),
                        const SizedBox(width: 64),
                        Expanded(child: highlights),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPoint({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return HoverLift(
      lift: 3,
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: hovered ? 0.13 : 0.09),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: hovered ? 0.30 : 0.16),
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                  border: Border.all(color: _turquoise.withValues(alpha: 0.50)),
                ),
                child: Icon(icon, color: _turquoise, size: 25),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Brand.heading(17, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: Brand.body(
                        14,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- shared

  /// A section band: full-width background, standard vertical rhythm, the
  /// site's content column.
  Widget _section({
    required double width,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.symmetric(vertical: Brand.sectionGap(width)),
      child: ContentColumn(child: child),
    );
  }

  /// White card with a ringed icon, title, body and optional checklist -
  /// the same treatment as the landing page's cards.
  Widget _missionCard({
    required IconData icon,
    required Color accent,
    required Color accentSoft,
    required String title,
    required String body,
    List<String>? bullets,
  }) {
    return HoverLift(
      lift: 6,
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Brand.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: hovered ? accent.withValues(alpha: 0.40) : Brand.border,
            ),
            boxShadow: hovered ? Brand.shadowCard : Brand.shadowSoft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  color: accentSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(height: 20),
              Text(title, style: Brand.heading(21)),
              const SizedBox(height: 10),
              Text(body, style: Brand.body(15)),
              if (bullets != null && bullets.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final item in bullets) _bulletItem(item),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _bulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 22,
            width: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: Brand.mintSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, size: 14, color: Brand.mint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Brand.label(14.5, color: Brand.textBody)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------- why it exists

  Widget _buildWhy(double width) {
    return _section(
      width: width,
      color: Brand.white,
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'Our mission',
            title: 'Why CureNurture Exists',
            subtitle:
                'Dialysis is not a one-time treatment. It is a continuous need '
                'that can become financially exhausting. CureNurture was '
                'created to make support easier, clearer, and more accessible '
                'for patients who need help to continue care.',
          ),
          const SizedBox(height: 44),
          ResponsiveRow(
            breakpoint: 860,
            gap: 22,
            stagger: true,
            equalHeight: true,
            children: [
              _missionCard(
                icon: Icons.flag_rounded,
                accent: Brand.teal,
                accentSoft: Brand.tealSoft,
                title: 'Our Purpose',
                body:
                    'CureNurture was created to bridge the gap between patients '
                    'who urgently need financial assistance and donors who want '
                    'their generosity to create real impact.',
                bullets: const [
                  'Financial support for dialysis sessions',
                  'Help with medical supplies and medication',
                  'Transportation assistance for clinic visits',
                  'Emergency support for urgent care needs',
                ],
              ),
              _missionCard(
                icon: Icons.favorite_rounded,
                accent: Brand.coral,
                accentSoft: Brand.coralSoft,
                title: 'Why We Do It',
                body:
                    'Kidney failure is a life-altering reality. Patients often '
                    'need ongoing dialysis, and the repeated cost of treatment '
                    'can deeply affect families. CureNurture exists to bring '
                    'relief, hope, and dignity.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- what it provides

  Widget _buildProvides(double width) {
    return _section(
      width: width,
      color: Brand.canvas,
      child: const Column(
        children: [
          SectionHeading(
            eyebrow: 'Where it helps',
            title: 'What Your Support Can Provide',
            subtitle:
                'Every contribution can help reduce the burden carried by '
                'patients and their families.',
          ),
          SizedBox(height: 44),
          ResponsiveRow(
            breakpoint: 900,
            gap: 20,
            stagger: true,
            equalHeight: true,
            children: [
              InfoCard(
                icon: Icons.medical_services_rounded,
                title: 'Dialysis Sessions',
                text: 'Assistance for regular treatment sessions.',
                accent: Brand.teal,
                accentSoft: Brand.tealSoft,
              ),
              InfoCard(
                icon: Icons.medication_rounded,
                title: 'Medication',
                text: 'Support for prescribed medicine and supplies.',
                accent: Brand.coral,
                accentSoft: Brand.coralSoft,
              ),
              InfoCard(
                icon: Icons.directions_car_rounded,
                title: 'Transportation',
                text: 'Help with travel to clinics or hospitals.',
                accent: Brand.brand,
                accentSoft: Brand.sky,
              ),
              InfoCard(
                icon: Icons.favorite_rounded,
                title: 'Daily Stability',
                text: 'Relief for families managing ongoing care.',
                accent: Brand.lavender,
                accentSoft: Brand.lavenderSoft,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------- vision and trust

  Widget _buildVisionTrust(double width) {
    return _section(
      width: width,
      color: Brand.white,
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'What guides us',
            title: 'Our Vision and Commitment',
          ),
          const SizedBox(height: 44),
          ResponsiveRow(
            breakpoint: 860,
            gap: 22,
            stagger: true,
            equalHeight: true,
            children: [
              _missionCard(
                icon: Icons.visibility_rounded,
                accent: Brand.brand,
                accentSoft: Brand.sky,
                title: 'Our Vision',
                body:
                    'We envision a community where no dialysis patient loses '
                    'access to essential treatment because of financial '
                    'limitations.',
              ),
              _missionCard(
                icon: Icons.shield_rounded,
                accent: Brand.mint,
                accentSoft: Brand.mintSoft,
                title: 'Transparency & Trust',
                body:
                    'Trust is at the center of CureNurture. Donation records go '
                    'through verification so donors can feel confident that '
                    'their support is handled responsibly.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ the flow

  Widget _buildProcess(double width) {
    const steps = [
      (
        number: '1',
        icon: Icons.edit_note_rounded,
        title: 'Submit Donation Details',
        text: 'Donors provide their information, amount, and payment method.',
      ),
      (
        number: '2',
        icon: Icons.receipt_long_rounded,
        title: 'Upload Proof',
        text: 'A receipt or screenshot is submitted after payment.',
      ),
      (
        number: '3',
        icon: Icons.verified_rounded,
        title: 'Admin Verification',
        text: 'Donation proof is reviewed before being marked verified.',
      ),
    ];

    final horizontal = width >= 860;

    Widget stepCard(int i) {
      final s = steps[i];
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
        decoration: Brand.card(),
        child: Column(
          crossAxisAlignment: horizontal
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Icon(s.icon, color: Brand.teal, size: 30),
            const SizedBox(height: 14),
            Text(
              s.title,
              textAlign: horizontal ? TextAlign.center : TextAlign.start,
              style: Brand.heading(18),
            ),
            const SizedBox(height: 8),
            Text(
              s.text,
              textAlign: horizontal ? TextAlign.center : TextAlign.start,
              style: Brand.body(14.5),
            ),
          ],
        ),
      );
    }

    Widget numberBadge(int i) => Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            gradient: Brand.brandGradient,
            shape: BoxShape.circle,
            boxShadow: Brand.shadowSoft,
          ),
          child: Center(
            child: Text(
              steps[i].number,
              style: const TextStyle(
                fontFamily: Brand.displayFont,
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );

    final connector = Container(
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Brand.teal.withValues(alpha: 0.15),
            Brand.teal.withValues(alpha: 0.55),
            Brand.teal.withValues(alpha: 0.15),
          ],
        ),
      ),
    );

    final Widget body;
    if (horizontal) {
      // Number badges on one line joined by subtle connectors, with each
      // step's card directly beneath its badge.
      body = Column(
        children: [
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: i == 0 ? const SizedBox() : connector),
                      numberBadge(i),
                      Expanded(
                        child: i == steps.length - 1
                            ? const SizedBox()
                            : connector,
                      ),
                    ],
                  ),
                ),
                if (i < steps.length - 1) const SizedBox(width: 20),
              ],
            ],
          ),
          const SizedBox(height: 22),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  Expanded(child: Reveal(delayMs: i * 90, child: stepCard(i))),
                  if (i < steps.length - 1) const SizedBox(width: 20),
                ],
              ],
            ),
          ),
        ],
      );
    } else {
      // Vertical timeline: badge and a connecting line on the left.
      body = Column(
        children: [
          for (int i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      numberBadge(i),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            color: Brand.teal.withValues(alpha: 0.30),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: i < steps.length - 1 ? 18 : 0,
                      ),
                      child: Reveal(delayMs: i * 90, child: stepCard(i)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return _section(
      width: width,
      color: Brand.canvas,
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'How it works',
            title: 'How the Donation Flow Works',
            subtitle:
                'CureNurture keeps the giving process clear from donor '
                'submission to verification.',
          ),
          const SizedBox(height: 44),
          body,
        ],
      ),
    );
  }

  // ------------------------------------------------------------ final CTA

  Widget _buildCta(double width) {
    final mobile = Brand.isMobile(width);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: Brand.deepGradient),
      child: Stack(
        children: [
          const Positioned.fill(child: ClipRect(child: FlowBackdrop())),
          Padding(
            padding: EdgeInsets.symmetric(vertical: mobile ? 64 : 92),
            child: ContentColumn(
              maxWidth: 820,
              child: Reveal(
                child: Column(
                  children: [
                    Container(
                      height: 72,
                      width: 72,
                      decoration: BoxDecoration(
                        gradient: Brand.coralGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: Brand.shadowCoral,
                      ),
                      child: const Icon(
                        Icons.volunteer_activism_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Every act of giving can become life-sustaining care.',
                      textAlign: TextAlign.center,
                      style: Brand.display(
                        mobile ? 28 : 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Together, we nurture healing. Together, we save lives.',
                      textAlign: TextAlign.center,
                      style: Brand.body(
                        mobile ? 15 : 17,
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Opens the same donation flow as the landing page.
                    Center(
                      child: DonateButton(
                        label: 'Donate Now',
                        large: true,
                        expand: mobile,
                        onPressed: _openDonation,
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

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Brand.canvas,
      // The navigation capsule floats above the page, as on the landing
      // page, so the hero runs underneath it.
      body: Stack(
        children: [
          RevealScope(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: _buildHero(width),
                    ),
                  ),
                  _buildWhy(width),
                  _buildProvides(width),
                  _buildVisionTrust(width),
                  _buildProcess(width),
                  _buildCta(width),
                ],
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildNavBar(width)),
        ],
      ),
    );
  }
}
