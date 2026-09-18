import 'package:flutter/material.dart';

/// The CureNurture donation site's visual language.
///
/// Presentation only. Nothing here touches donations, auth or Supabase - it
/// is colour, type, spacing and decoration for the public-facing pages.
///
/// The palette is built on the CureNurture blues, warmed with a single
/// coral accent reserved for one job: the Donate action. Because coral is
/// the only warm colour on an otherwise cool page, the donate button is
/// always the most visually urgent thing on screen without needing to be
/// the biggest.
class Brand {
  const Brand._();

  // ----------------------------------------------------------- brand blues
  /// Deepest ink. Headlines on light surfaces, and the footer ground.
  static const Color ink = Color(0xFF10293A);
  static const Color brandDeep = Color(0xFF17435C);
  static const Color brand = Color(0xFF2A5F7E);
  static const Color brandMid = Color(0xFF245C78);

  // -------------------------------------------------------------- accents
  /// Healthcare teal - icons, motifs, eyebrow labels.
  static const Color teal = Color(0xFF2F8F9D);
  static const Color tealSoft = Color(0xFFE8F5F7);

  /// The donate colour. 4.47:1 against white, so white button labels clear
  /// AA for large bold text with room to spare.
  static const Color coral = Color(0xFFD14836);
  static const Color coralBright = Color(0xFFE35D4F);
  static const Color coralSoft = Color(0xFFFCEDEA);

  /// Verification and confirmation.
  static const Color mint = Color(0xFF2E7D6B);
  static const Color mintSoft = Color(0xFFE6F4F0);

  /// A quiet fourth accent, used sparingly for community/people content.
  static const Color lavender = Color(0xFF6A6BA8);
  static const Color lavenderSoft = Color(0xFFEEEEF8);

  // ------------------------------------------------------------- surfaces
  static const Color white = Color(0xFFFEFFFE);
  static const Color canvas = Color(0xFFF7FAFC);
  static const Color sky = Color(0xFFEAF4FA);
  static const Color border = Color(0xFFE2ECF2);
  static const Color borderSoft = Color(0xFFEDF3F7);
  static const Color borderStrong = Color(0xFFCBDBE6);

  // ----------------------------------------------------------------- text
  /// 14.9:1 on canvas.
  static const Color textStrong = ink;

  /// 6.4:1 on canvas - comfortable for long-form body copy.
  static const Color textBody = Color(0xFF4A6275);

  /// 5.1:1 on canvas - still AA, for captions and metadata.
  static const Color textMuted = Color(0xFF5A7183);

  // -------------------------------------------------------------- display
  /// Montserrat ships with the app at 400 and 700 only, so display text
  /// sticks to those two weights - anything between would be synthesised
  /// and render as smeared fake-bold on the web canvas.
  static const String displayFont = 'Montserrat';

  // -------------------------------------------------------------- shadows
  static List<BoxShadow> get shadowSoft => [
    BoxShadow(
      color: ink.withValues(alpha: 0.05),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get shadowCard => [
    BoxShadow(
      color: ink.withValues(alpha: 0.07),
      blurRadius: 34,
      offset: const Offset(0, 18),
    ),
  ];

  static List<BoxShadow> get shadowLift => [
    BoxShadow(
      color: ink.withValues(alpha: 0.13),
      blurRadius: 44,
      offset: const Offset(0, 24),
    ),
  ];

  /// The donate button's own glow, so it reads as raised even on a busy
  /// gradient.
  static List<BoxShadow> get shadowCoral => [
    BoxShadow(
      color: coral.withValues(alpha: 0.34),
      blurRadius: 26,
      offset: const Offset(0, 12),
    ),
  ];

  // ------------------------------------------------------------ gradients
  /// The hero / major-section ground.
  static const LinearGradient deepGradient = LinearGradient(
    colors: [Color(0xFF10293A), brandDeep, Color(0xFF276C84)],
    stops: [0.0, 0.52, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient brandGradient = LinearGradient(
    colors: [brandDeep, brand],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient coralGradient = LinearGradient(
    colors: [coralBright, coral],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ---------------------------------------------------------- breakpoints
  static bool isMobile(double w) => w < 760;
  static bool isTablet(double w) => w >= 760 && w < 1080;
  static bool isDesktop(double w) => w >= 1080;

  /// Content column. Wide enough to breathe on a laptop, capped so text
  /// lines never grow past a comfortable measure on a large monitor.
  static const double maxContent = 1180;

  /// Outer page gutter. Never drops below 20 so text is never flush to a
  /// phone's edge.
  static double gutter(double w) {
    if (w < 480) return 20;
    if (w < 760) return 24;
    if (w < 1080) return 32;
    return 40;
  }

  /// Vertical rhythm between major sections, tightened on small screens so
  /// a phone visitor reaches the donate button sooner.
  static double sectionGap(double w) {
    if (w < 760) return 64;
    if (w < 1080) return 80;
    return 96;
  }

  // ------------------------------------------------------------- type set
  static TextStyle display(double size, {Color color = textStrong}) {
    return TextStyle(
      fontFamily: displayFont,
      color: color,
      fontSize: size,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: size > 40 ? -1.2 : -0.5,
    );
  }

  static TextStyle heading(double size, {Color color = textStrong}) {
    return TextStyle(
      fontFamily: displayFont,
      color: color,
      fontSize: size,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    );
  }

  static TextStyle body(double size, {Color color = textBody}) {
    return TextStyle(
      color: color,
      fontSize: size,
      height: 1.7,
      fontWeight: FontWeight.w400,
    );
  }

  static TextStyle label(double size, {Color color = textStrong}) {
    return TextStyle(
      color: color,
      fontSize: size,
      height: 1.35,
      fontWeight: FontWeight.w600,
    );
  }

  static TextStyle eyebrow({Color color = teal}) {
    return TextStyle(
      color: color,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
    );
  }

  // ----------------------------------------------------------- decoration
  /// The default card: white, hairline border, gentle lift.
  static BoxDecoration card({
    double radius = 24,
    Color color = white,
    Color? borderColor,
    List<BoxShadow>? shadow,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? border),
      boxShadow: shadow ?? shadowSoft,
    );
  }

  /// A tinted, borderless card - used to break up rows of white cards so
  /// they don't all read at the same weight.
  static BoxDecoration tintedCard({
    required Color tint,
    double radius = 24,
  }) {
    return BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// Translucent panel for use on top of the deep gradient.
  static BoxDecoration glass({double radius = 24, double opacity = 0.11}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    );
  }

  /// Soft square container behind an icon.
  static BoxDecoration iconBox(Color tint, {double radius = 16}) {
    return BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(radius),
    );
  }
}
