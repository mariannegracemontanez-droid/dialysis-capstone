import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'motion.dart';

/// Shared pieces of the site's floating navigation bar, used by the landing
/// page and the About page so both carry exactly the same bar.
///
/// Presentation only: every button here simply calls the callback it is
/// given.
class SiteNav {
  const SiteNav._();

  /// Gap above the capsule and the capsule's height. Pages start their first
  /// section this far down so nothing hides behind the bar.
  static const double topMargin = 12;
  static const double height = 64;
  static const double reserve = topMargin + height;

  /// Side margin of the capsule for a given window width.
  static double side(double width) => Brand.isMobile(width)
      ? 12.0
      : (Brand.gutter(width) - 12).clamp(16.0, double.infinity);
}

/// The frosted, soft-white floating capsule that holds the navigation.
class NavCapsule extends StatelessWidget {
  const NavCapsule({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mobile = Brand.isMobile(width);
    const radius = BorderRadius.all(Radius.circular(SiteNav.height / 2));
    final side = SiteNav.side(width);

    return Padding(
      padding: EdgeInsets.fromLTRB(side, SiteNav.topMargin, side, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Brand.maxContent + 56),
          child: DecoratedBox(
            // The shadow sits outside the clip so the capsule reads as gently
            // raised over both the navy hero and light sections.
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Brand.ink.withValues(alpha: 0.10),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: SiteNav.height,
                  padding: EdgeInsets.only(
                    left: mobile ? 10 : 12,
                    right: mobile ? 4 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.80),
                    borderRadius: radius,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.70),
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The CureNurture logo and wordmark as shown in the navigation bar.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 40,
          width: 40,
          padding: const EdgeInsets.all(4),
          decoration: Brand.iconBox(Brand.sky, radius: 13),
          child: Image.asset(
            'lib/assets/image/CureNurture_logo.png',
            fit: BoxFit.contain,
            semanticLabel: 'CureNurture logo',
          ),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Cure',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Brand.teal,
                height: 1,
              ),
            ),
            Text(
              'NURTURE',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 9.5,
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
}

/// A round back button for the navigation capsule: a soft sky disc with a
/// navy arrow; hover deepens the disc and adds a teal ring, pressing dims
/// it, and keyboard focus draws a navy ring.
class NavBackButton extends StatefulWidget {
  const NavBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<NavBackButton> createState() => _NavBackButtonState();
}

class _NavBackButtonState extends State<NavBackButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    final Color ring = _focused
        ? Brand.brandDeep
        : (_hovered ? Brand.teal.withValues(alpha: 0.55) : Brand.border);

    return Tooltip(
      message: 'Back',
      child: Semantics(
        button: true,
        label: 'Back',
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
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onPressed,
              child: AnimatedContainer(
                duration: duration,
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pressed
                      ? Brand.border
                      : (_hovered ? Brand.sky : Brand.white),
                  border: Border.all(color: ring, width: _focused ? 2 : 1.2),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: Brand.brandDeep,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Donate Now at the navigation bar's compact size.
///
/// The site's existing coral primary style - coral fill, white bold label,
/// coral glow - with hover (brighter coral, lifted), pressed (deeper coral,
/// settled) and focus (navy ring) states. The shared DonateButton is not
/// used here because its fixed height and padding are sized for page
/// sections, not a 64px bar; that widget is left unchanged.
class NavDonateButton extends StatefulWidget {
  const NavDonateButton({
    super.key,
    required this.label,
    required this.width,
    required this.height,
    required this.onPressed,
  });

  final String label;
  final double width;
  final double height;
  final VoidCallback onPressed;

  @override
  State<NavDonateButton> createState() => _NavDonateButtonState();
}

class _NavDonateButtonState extends State<NavDonateButton> {
  bool _hovered = false;

  /// A deeper shade of the brand coral for the pressed state.
  static const Color _coralPressed = Color(0xFFB83E2E);

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);

    return AnimatedContainer(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
      width: widget.width,
      height: widget.height,
      transform: Matrix4.translationValues(0, _hovered && !reduced ? -1.5 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: _hovered
            ? [
                BoxShadow(
                  color: Brand.coral.withValues(alpha: 0.40),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Brand.coral.withValues(alpha: 0.26),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Semantics(
        button: true,
        label: 'Donate now',
        excludeSemantics: true,
        child: ElevatedButton.icon(
          onPressed: widget.onPressed,
          onHover: (v) => setState(() => _hovered = v),
          icon: const Icon(Icons.volunteer_activism_rounded, size: 17),
          label: Text(widget.label, maxLines: 1, softWrap: false),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) return _coralPressed;
              if (states.contains(WidgetState.hovered)) {
                return Brand.coralBright;
              }
              return Brand.coral;
            }),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12),
            ),
            iconSize: const WidgetStatePropertyAll(17),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            animationDuration: const Duration(milliseconds: 180),
            shape: WidgetStateProperty.resolveWith((states) {
              final focused = states.contains(WidgetState.focused);
              return RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: focused
                    ? const BorderSide(color: Brand.brandDeep, width: 2.2)
                    : BorderSide.none,
              );
            }),
          ),
        ),
      ),
    );
  }
}
