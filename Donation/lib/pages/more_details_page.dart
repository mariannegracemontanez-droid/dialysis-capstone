import 'package:flutter/material.dart';

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

  final Color _darkTeal = const Color(0xFF163B56);
  final Color _primaryTeal = const Color(0xFF3B97A2);
  final Color _accentBlue = const Color(0xFF38A6DB);
  final Color _surface = const Color(0xFFF7FBFD);
  final Color _softBlue = const Color(0xFFEAF7FB);

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
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
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

  PreferredSizeWidget _buildHeader() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 74,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: _darkTeal),
        onPressed: () => Navigator.of(context).pop(),
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
            style: TextStyle(color: _darkTeal, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _animatedEntry({required Widget child, int delay = 0}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 550 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 58),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkTeal, _primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mobile = constraints.maxWidth < 850;

              final text = Column(
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
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: const Text(
                      'ABOUT THE MISSION',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'More than a donation platform — a bridge to continued care.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'CureNurture helps connect compassionate donors with dialysis patients who need support for treatment, medication, transportation, and other essential care needs.',
                    textAlign: mobile ? TextAlign.center : TextAlign.left,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: 16,
                      height: 1.7,
                    ),
                  ),
                ],
              );

              final highlights = Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Column(
                  children: [
                    _heroPoint(
                      icon: Icons.health_and_safety_rounded,
                      title: 'Patient-centered',
                      text:
                          'Built around dialysis patients and their families.',
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
                      text:
                          'Donation activity is verified for donor confidence.',
                    ),
                  ],
                ),
              );

              if (mobile) {
                return Column(
                  children: [text, const SizedBox(height: 28), highlights],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 6, child: text),
                  const SizedBox(width: 44),
                  Expanded(flex: 4, child: highlights),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _heroPoint({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Row(
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: Colors.white),
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
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIntro() {
    return Column(
      children: [
        Text(
          'Why CureNurture Exists',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _darkTeal,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            'Dialysis is not a one-time treatment. It is a continuous need that can become financially exhausting. CureNurture was created to make support easier, clearer, and more accessible for patients who need help to continue care.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey.shade600,
              fontSize: 15.5,
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }

  Widget _missionCard({
    required IconData icon,
    required String title,
    required String body,
    List<String>? bullets,
  }) {
    return _animatedEntry(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFE3EEF4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.045),
              blurRadius: 28,
              offset: const Offset(0, 18),
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
              child: Icon(icon, color: _primaryTeal, size: 30),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: TextStyle(
                color: _darkTeal,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontSize: 15,
                height: 1.7,
              ),
            ),
            if (bullets != null && bullets.isNotEmpty) ...[
              const SizedBox(height: 18),
              ...bullets.map((item) => _bulletItem(item)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, color: _primaryTeal, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImpactSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFFD8EAF0)),
      ),
      child: Column(
        children: [
          Text(
            'What Your Support Can Provide',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _darkTeal,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Every contribution can help reduce the burden carried by patients and their families.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey.shade600, height: 1.6),
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final mobile = constraints.maxWidth < 760;

              final items = [
                _impactItem(
                  icon: Icons.medical_services_rounded,
                  title: 'Dialysis Sessions',
                  text: 'Assistance for regular treatment sessions.',
                ),
                _impactItem(
                  icon: Icons.medication_rounded,
                  title: 'Medication',
                  text: 'Support for prescribed medicine and supplies.',
                ),
                _impactItem(
                  icon: Icons.directions_car_rounded,
                  title: 'Transportation',
                  text: 'Help with travel to clinics or hospitals.',
                ),
                _impactItem(
                  icon: Icons.favorite_rounded,
                  title: 'Daily Stability',
                  text: 'Relief for families managing ongoing care.',
                ),
              ];

              if (mobile) {
                return Column(
                  children: items
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: item,
                        ),
                      )
                      .toList(),
                );
              }

              return Row(
                children: [
                  Expanded(child: items[0]),
                  const SizedBox(width: 14),
                  Expanded(child: items[1]),
                  const SizedBox(width: 14),
                  Expanded(child: items[2]),
                  const SizedBox(width: 14),
                  Expanded(child: items[3]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _impactItem({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3EEF4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: _primaryTeal, size: 34),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _darkTeal,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey.shade600,
              fontSize: 12.8,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessSection() {
    return Column(
      children: [
        Text(
          'How the Donation Flow Works',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _darkTeal,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'CureNurture keeps the giving process clear from donor submission to verification.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.blueGrey.shade600, height: 1.6),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            final mobile = constraints.maxWidth < 800;

            final steps = [
              _processStep(
                number: '1',
                icon: Icons.edit_note_rounded,
                title: 'Submit Donation Details',
                text:
                    'Donors provide their information, amount, and payment method.',
              ),
              _processStep(
                number: '2',
                icon: Icons.receipt_long_rounded,
                title: 'Upload Proof',
                text: 'A receipt or screenshot is submitted after payment.',
              ),
              _processStep(
                number: '3',
                icon: Icons.verified_rounded,
                title: 'Admin Verification',
                text:
                    'Donation proof is reviewed before being marked verified.',
              ),
            ];

            if (mobile) {
              return Column(
                children: steps
                    .map(
                      (step) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: step,
                      ),
                    )
                    .toList(),
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: steps[0]),
                const SizedBox(width: 16),
                Expanded(child: steps[1]),
                const SizedBox(width: 16),
                Expanded(child: steps[2]),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _processStep({
    required String number,
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE3EEF4)),
      ),
      child: Column(
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(color: _softBlue, shape: BoxShape.circle),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: _primaryTeal,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Icon(icon, color: _primaryTeal, size: 32),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _darkTeal,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey.shade600,
              height: 1.55,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCta() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkTeal, _primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(34),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.volunteer_activism_rounded,
            color: Colors.white,
            size: 44,
          ),
          const SizedBox(height: 18),
          const Text(
            'Every act of giving can become life-sustaining care.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 1.18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Together, we nurture healing. Together, we save lives.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: _buildHeader(),
      body: SingleChildScrollView(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                _buildHero(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 46,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        children: [
                          _buildIntro(),
                          const SizedBox(height: 32),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final mobile = constraints.maxWidth < 850;

                              if (mobile) {
                                return Column(
                                  children: [
                                    _missionCard(
                                      icon: Icons.flag_rounded,
                                      title: 'Our Purpose',
                                      body:
                                          'CureNurture was created to bridge the gap between patients who urgently need financial assistance and donors who want their generosity to create real impact.',
                                      bullets: const [
                                        'Financial support for dialysis sessions',
                                        'Help with medical supplies and medication',
                                        'Transportation assistance for clinic visits',
                                        'Emergency support for urgent care needs',
                                      ],
                                    ),
                                    const SizedBox(height: 32),
                                    _missionCard(
                                      icon: Icons.favorite_rounded,
                                      title: 'Why We Do It',
                                      body:
                                          'Kidney failure is a life-altering reality. Patients often need ongoing dialysis, and the repeated cost of treatment can deeply affect families. CureNurture exists to bring relief, hope, and dignity.',
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _missionCard(
                                      icon: Icons.flag_rounded,
                                      title: 'Our Purpose',
                                      body:
                                          'CureNurture was created to bridge the gap between patients who urgently need financial assistance and donors who want their generosity to create real impact.',
                                      bullets: const [
                                        'Financial support for dialysis sessions',
                                        'Help with medical supplies and medication',
                                        'Transportation assistance for clinic visits',
                                        'Emergency support for urgent care needs',
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 22),
                                  Expanded(
                                    child: _missionCard(
                                      icon: Icons.favorite_rounded,
                                      title: 'Why We Do It',
                                      body:
                                          'Kidney failure is a life-altering reality. Patients often need ongoing dialysis, and the repeated cost of treatment can deeply affect families. CureNurture exists to bring relief, hope, and dignity.',
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 26),
                          _buildImpactSection(),
                          const SizedBox(height: 34),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final mobile = constraints.maxWidth < 850;

                              if (mobile) {
                                return Column(
                                  children: [
                                    _missionCard(
                                      icon: Icons.visibility_rounded,
                                      title: 'Our Vision',
                                      body:
                                          'We envision a community where no dialysis patient loses access to essential treatment because of financial limitations.',
                                    ),
                                    const SizedBox(height: 20),
                                    _missionCard(
                                      icon: Icons.shield_rounded,
                                      title: 'Transparency & Trust',
                                      body:
                                          'Trust is at the center of CureNurture. Donation records go through verification so donors can feel confident that their support is handled responsibly.',
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _missionCard(
                                      icon: Icons.visibility_rounded,
                                      title: 'Our Vision',
                                      body:
                                          'We envision a community where no dialysis patient loses access to essential treatment because of financial limitations.',
                                    ),
                                  ),
                                  const SizedBox(width: 22),
                                  Expanded(
                                    child: _missionCard(
                                      icon: Icons.shield_rounded,
                                      title: 'Transparency & Trust',
                                      body:
                                          'Trust is at the center of CureNurture. Donation records go through verification so donors can feel confident that their support is handled responsibly.',
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 34),
                          _buildProcessSection(),
                          const SizedBox(height: 34),
                          _buildCta(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
