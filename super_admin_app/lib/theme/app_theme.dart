import 'package:flutter/material.dart';

/// Shared visual language for the CureNurture Super Admin portal.
///
/// Presentation only: colours, radii, elevation and layout breakpoints.
/// Nothing here holds state, data or behaviour.
class AppTheme {
  const AppTheme._();

  // ---------------------------------------------------------------- palette
  static const Color blue1 = Color(0xFF2A5F7E);
  static const Color blue2 = Color(0xFF245C78);
  static const Color blue3 = Color(0xFF17435C);
  static const Color blue4 = Color(0xFF26364A);
  static const Color blue5 = Color(0xFF1F2D3D);
  static const Color white = Color(0xFFFEFFFE);

  // --------------------------------------------------------------- surfaces
  /// Primary surface for cards, panels and the sidebar.
  static const Color surface = white;

  /// Page background: a very light blue tint derived from the palette.
  static const Color canvas = Color(0xFFF4F7FA);

  /// Inset blocks inside a surface (mini stats, detail rows).
  static const Color surfaceTint = Color(0xFFF4F8FA);

  /// Soft blue wash used for icon containers and hover states.
  static const Color accentSoft = Color(0xFFEDF3F8);

  /// Trailing stop of the very subtle header gradient.
  static const Color headerTint = Color(0xFFEFF5F9);

  // ------------------------------------------------------------------ lines
  static const Color border = Color(0xFFE4EBF1);
  static const Color borderStrong = Color(0xFFD6E0E8);

  // ------------------------------------------------------------------- text
  static const Color textPrimary = blue5;
  static const Color textSecondary = Color(0xFF4A5C70);
  static const Color textMuted = Color(0xFF7C8B9B);
  static const Color iconMuted = Color(0xFF7E93A6);

  // ----------------------------------------------------------------- accents
  // Muted, low-chroma companions to the blues. Each has one job, and they are
  // for icon containers, pills and small indicators only - never for large
  // background areas.
  //
  //   blue   -> general / system information
  //   teal   -> capacity and machines
  //   green  -> active, open, available, verified
  //   orange -> attention, distribution
  //   pink   -> donations
  static const Color accentBlue = blue1;
  static const Color accentBlueSoft = Color(0xFFEDF3F8);
  static const Color accentTeal = Color(0xFF2A7370);
  static const Color accentTealSoft = Color(0xFFE7F2F1);
  static const Color accentGreen = Color(0xFF2F7A55);
  static const Color accentGreenSoft = Color(0xFFE9F4EE);
  static const Color accentOrange = Color(0xFFB0662C);
  static const Color accentOrangeSoft = Color(0xFFFAF0E7);
  static const Color accentPink = Color(0xFF9B4370);
  static const Color accentPinkSoft = Color(0xFFF9EDF3);
  static const Color danger = Color(0xFFB3403D);
  static const Color dangerSoft = Color(0xFFFBEDED);

  /// Centre status colours. Presentation only - the status strings and the
  /// logic that produces them are untouched.
  static Color statusColor(String? status) {
    switch (status?.toLowerCase().trim()) {
      case 'open':
        return accentGreen;
      case 'busy':
        return accentOrange;
      case 'full':
        return danger;
      default:
        return blue1;
    }
  }

  static Color statusSoft(String? status) {
    switch (status?.toLowerCase().trim()) {
      case 'open':
        return accentGreenSoft;
      case 'busy':
        return accentOrangeSoft;
      case 'full':
        return dangerSoft;
      default:
        return accentBlueSoft;
    }
  }

  /// Blue scale for charting many series as one cohesive family, derived from
  /// the brand blues plus lighter tints of them.
  static const List<Color> chartBlues = [
    blue3,
    blue2,
    blue1,
    Color(0xFF3D7FA0),
    Color(0xFF5798B6),
    Color(0xFF76AFC8),
    Color(0xFF97C5D9),
  ];

  /// The bar colour for series [index], cycling through [chartBlues].
  static Color chartBlue(int index) =>
      chartBlues[index % chartBlues.length];

  // ----------------------------------------------------------------- radius
  static const double rSm = 8;
  static const double rMd = 10;
  static const double rLg = 14;
  static const double rXl = 16;

  // -------------------------------------------------------------- elevation
  /// Cards and panels: just enough lift to separate them from the canvas.
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x0A16324A), blurRadius: 10, offset: Offset(0, 2)),
  ];

  /// Reserved for overlays such as dialogs.
  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x1416324A), blurRadius: 28, offset: Offset(0, 12)),
  ];

  // ------------------------------------------------------------------ space
  static const double gapSm = 8;
  static const double gapMd = 16;
  static const double gapLg = 20;

  /// Keeps the dashboard readable instead of stretching on wide monitors.
  static const double maxContentWidth = 1720;

  // ------------------------------------------------------------ breakpoints
  /// Slightly narrower than the previous shell, and stable per desktop tier.
  static double sidebarWidth(double screenWidth) {
    if (screenWidth < 1280) return 224;
    if (screenWidth < 1700) return 238;
    return 250;
  }

  /// Outer page margin, kept proportional to the viewport.
  static double pagePadding(double screenWidth) {
    if (screenWidth < 1280) return 22;
    if (screenWidth < 1700) return 28;
    return 32;
  }

  /// Dialysis centre grid: three columns for every desktop width, then a
  /// natural fallback for narrower viewports.
  static int centerColumns(double screenWidth) {
    if (screenWidth >= 1150) return 3;
    if (screenWidth >= 760) return 2;
    return 1;
  }

  // ------------------------------------------------------------- components
  /// The standard panel: white surface, hairline border, barely-there lift.
  static BoxDecoration card({double radius = rXl}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
      boxShadow: shadowSm,
    );
  }

  /// A soft-tinted container for an icon, in one of the accent families.
  static BoxDecoration iconBox(Color soft, {double radius = rMd}) {
    return BoxDecoration(
      color: soft,
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// Shared field styling for text inputs and dropdown buttons, so a search
  /// box and a filter sit on the same baseline and share one visual weight.
  static InputDecoration field({
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool dense = false,
  }) {
    final radius = BorderRadius.circular(rMd);

    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: dense,
      filled: true,
      fillColor: surfaceTint,
      hintStyle: const TextStyle(
        color: textMuted,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: const TextStyle(
        color: textMuted,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: const TextStyle(
        color: blue1,
        fontWeight: FontWeight.w600,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: dense ? 12 : 15,
      ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: blue1, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Color(0xFFD48B8B)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: danger, width: 1.4),
      ),
      errorStyle: const TextStyle(
        color: danger,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// Text style for the value shown inside a field or dropdown button.
  static const TextStyle fieldTextStyle = TextStyle(
    color: textPrimary,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
  );

  /// Corner radius of a dropdown's popup, so it reads as an extension of the
  /// field that opened it.
  static const double menuRadius = rMd;
}

/// Restyles the popup menu of any dropdown beneath it.
///
/// Flutter paints a dropdown's currently-selected row with `focusColor`,
/// which defaults to a heavy grey block, and hovers with `hoverColor`. Both
/// are theme-level, so the only way to soften them is to override the theme
/// around the dropdown - this changes no behaviour, only those two colours.
/// Pair it with [AppTheme.menuBorderRadius] and `dropdownColor` on the
/// dropdown itself for the full treatment.
class AppMenuTheme extends StatelessWidget {
  final Widget child;

  const AppMenuTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);

    return Theme(
      data: base.copyWith(
        // The popup's surface colour, for dropdowns that don't set
        // `dropdownColor` themselves.
        canvasColor: AppTheme.surface,
        focusColor: AppTheme.accentBlueSoft,
        hoverColor: AppTheme.surfaceTint,
        splashColor: AppTheme.accentBlueSoft,
        highlightColor: Colors.transparent,
      ),
      child: child,
    );
  }
}

