import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/brand.dart';
import '../widgets/decor.dart';
import '../widgets/donation_steps.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'donation_page.dart';
import 'login_page.dart';

/// Step one of the donation journey: give anonymously, or give as a
/// registered donor.
///
/// The two options, the values behind them and where each one leads are
/// unchanged - this page only presents that choice more clearly.
class DonationOptionPage extends StatefulWidget {
  const DonationOptionPage({super.key});

  @override
  State<DonationOptionPage> createState() => _DonationOptionPageState();
}

class _DonationOptionPageState extends State<DonationOptionPage> {
  String? _selectedOption;

  void _continue() {
    if (_selectedOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please select a donation option to continue.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Brand.coral,
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
    } else if (_selectedOption == 'registered') {
      // Only ask for a login when there isn't one already. Signing up or
      // logging in from the navigation bar leaves a live Supabase session,
      // and sending that donor back through the login form would make them
      // authenticate a second time for no reason.
      //
      // This deliberately reads the same thing DonationPage itself checks
      // on arrival (a null currentUser is what makes it show "Please log in
      // to donate"), so the two can never disagree about whether a login
      // step is still needed.
      final isAuthenticated =
          Supabase.instance.client.auth.currentUser != null;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => isAuthenticated
              // Registered donation on the account already signed in.
              ? const DonationPage()
              : const LoginPage(
                  fromDonation: true,
                ),
        ),
      );
    }
  }

  PreferredSizeWidget _buildHeader() {
    return AppBar(
      backgroundColor: Brand.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 74,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Brand.brandDeep),
        tooltip: 'Back',
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Image.asset(
            'lib/assets/image/CureNurture_logo.png',
            width: 36,
            height: 36,
            semanticLabel: 'CureNurture logo',
          ),
          const SizedBox(width: 10),
          const Text(
            'CureNurture',
            style: TextStyle(
              fontFamily: Brand.displayFont,
              color: Brand.brandDeep,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Brand.border),
      ),
    );
  }

  /// A selectable card. Still a plain tap target that sets
  /// [_selectedOption] - the accent colour, hover lift and radio glyph are
  /// all it gained.
  Widget _optionCard({
    required String value,
    required IconData icon,
    required String title,
    required String description,
    required Color accent,
    required Color accentSoft,
    required List<String> points,
  }) {
    final selected = _selectedOption == value;

    return HoverLift(
      lift: 4,
      builder: (context, hovered) {
        return Semantics(
          inMutuallyExclusiveGroup: true,
          selected: selected,
          button: true,
          label: title,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            focusColor: accent.withValues(alpha: 0.10),
            hoverColor: Colors.transparent,
            onTap: () {
              setState(() {
                _selectedOption = value;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: selected ? accentSoft : Brand.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: selected
                      ? accent
                      : (hovered
                            ? accent.withValues(alpha: 0.42)
                            : Brand.border),
                  width: selected ? 2 : 1.2,
                ),
                boxShadow: selected || hovered
                    ? Brand.shadowCard
                    : Brand.shadowSoft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 54,
                        width: 54,
                        decoration: Brand.iconBox(
                          selected
                              ? Colors.white.withValues(alpha: 0.8)
                              : accentSoft,
                          radius: 17,
                        ),
                        child: Icon(icon, color: accent, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: Brand.heading(18)),
                            const SizedBox(height: 6),
                            Text(description, style: Brand.body(14)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 26,
                        width: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? accent : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? accent
                                : Brand.border,
                            width: 2,
                          ),
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    height: 1,
                    color: selected
                        ? accent.withValues(alpha: 0.18)
                        : Brand.borderSoft,
                  ),
                  const SizedBox(height: 16),
                  for (final point in points)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: accent.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              point,
                              style: Brand.body(13.5, color: Brand.textBody),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mobile = Brand.isMobile(width);

    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: _buildHeader(),
      body: RevealScope(
        child: SingleChildScrollView(
        child: Column(
          children: [
            // A short banded header, so the choice page still feels part of
            // the same site as the landing page rather than a bare form.
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: Brand.brandGradient),
              child: Stack(
                children: [
                  const Positioned.fill(child: FlowBackdrop(opacity: 0.8)),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: mobile ? 40 : 54,
                    ),
                    child: ContentColumn(
                      maxWidth: 860,
                      child: Column(
                        children: [
                          const Eyebrow('Step 1 of 3', light: true),
                          const SizedBox(height: 20),
                          Text(
                            'How would you like to give?',
                            textAlign: TextAlign.center,
                            style: Brand.display(
                              mobile ? 30 : 40,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Both options reach the same dialysis centres. The '
                            'only difference is whether your donation is '
                            'recorded under your name.',
                            textAlign: TextAlign.center,
                            style: Brand.body(
                              mobile ? 14.5 : 16,
                              color: Colors.white.withValues(alpha: 0.84),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: EdgeInsets.symmetric(vertical: mobile ? 32 : 46),
              child: ContentColumn(
                maxWidth: 860,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: Brand.card(radius: 22),
                      child: const DonationSteps(current: 0),
                    ),

                    const SizedBox(height: 30),

                    Reveal(
                      child: _optionCard(
                        value: 'anonymous',
                        icon: Icons.visibility_off_rounded,
                        title: 'Donate Anonymously',
                        description:
                            'Continue straight to the donation form without '
                            'using a registered account.',
                        accent: Brand.teal,
                        accentSoft: Brand.tealSoft,
                        points: const [
                          'No name or email is stored with your donation',
                          'Appears in the public list as “Anonymous”',
                          'You still choose which centre it supports',
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    Reveal(
                      delayMs: 90,
                      child: _optionCard(
                        value: 'registered',
                        icon: Icons.account_circle_rounded,
                        title: 'Donate Using a Registered Account',
                        description:
                            'Log in to your donor account before continuing '
                            'with your donation.',
                        accent: Brand.brand,
                        accentSoft: Brand.sky,
                        points: const [
                          'Your donation is recorded under your name',
                          'Your gift appears in the public verified list',
                          'You still choose which centre it supports',
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    DonateButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _continue,
                      expand: true,
                      large: true,
                    ),

                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_rounded,
                          size: 15,
                          color: Brand.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'You can change your mind at any point before '
                            'submitting your donation.',
                            textAlign: TextAlign.center,
                            style: Brand.body(13, color: Brand.textMuted),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
