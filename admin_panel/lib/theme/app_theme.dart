import 'package:flutter/material.dart';

/// Shared visual language for the CureNurture Center Admin panel.
///
/// Deliberately a mirror of the Super Admin portal's `AppTheme`, so the two
/// halves of the product read as one system. Presentation only: colours,
/// radii, elevation, motion and layout breakpoints. Nothing here holds
/// state, data or behaviour.
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

  /// Inset blocks inside a surface (mini stats, detail rows, inputs).
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

  // ---------------------------------------------------------------- accents
  // Muted, low-chroma companions to the blues. Each has one job, and they
  // are for icon containers, pills and small indicators only - never for
  // large background areas.
  //
  //   blue   -> general / system information
  //   teal   -> shifts, capacity, machines
  //   green  -> active, scheduled, available, success
  //   orange -> reminders, attention, pending
  //   purple -> administrative / financial information
  //   pink   -> donations
  static const Color accentBlue = blue1;
  static const Color accentBlueSoft = Color(0xFFEDF3F8);
  static const Color accentTeal = Color(0xFF2A7370);
  static const Color accentTealSoft = Color(0xFFE7F2F1);
  static const Color accentGreen = Color(0xFF2F7A55);
  static const Color accentGreenSoft = Color(0xFFE9F4EE);
  static const Color accentOrange = Color(0xFFB0662C);
  static const Color accentOrangeSoft = Color(0xFFFAF0E7);
  static const Color accentPurple = Color(0xFF6B4E8F);
  static const Color accentPurpleSoft = Color(0xFFF1EDF7);
  static const Color accentPink = Color(0xFF9B4370);
  static const Color accentPinkSoft = Color(0xFFF9EDF3);
  static const Color danger = Color(0xFFB3403D);
  static const Color dangerSoft = Color(0xFFFBEDED);

  /// Blue scale for charting many series as one cohesive family.
  static const List<Color> chartBlues = [
    blue3,
    blue2,
    blue1,
    Color(0xFF3D7FA0),
    Color(0xFF5798B6),
    Color(0xFF76AFC8),
    Color(0xFF97C5D9),
  ];

  static Color chartBlue(int index) => chartBlues[index % chartBlues.length];

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

  /// A card that is being hovered.
  static const List<BoxShadow> shadowHover = [
    BoxShadow(color: Color(0x1416324A), blurRadius: 18, offset: Offset(0, 6)),
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

  // ----------------------------------------------------------------- motion
  /// One vocabulary of durations, so nothing in the panel animates at a
  /// speed the rest of it doesn't use.
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve ease = Curves.easeOutCubic;

  /// Honours the OS "reduce motion" setting: returns [Duration.zero] when
  /// the user has asked for less animation, so every transition below
  /// degrades to an instant state change rather than being ignored.
  static Duration motion(BuildContext context, Duration duration) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? Duration.zero
        : duration;
  }

  // ------------------------------------------------------------ breakpoints
  /// Slightly narrower than the previous shell, and stable per desktop tier.
  static double sidebarWidth(double screenWidth) {
    if (screenWidth < 1280) return 224;
    if (screenWidth < 1700) return 238;
    return 250;
  }

  /// Outer page margin, kept proportional to the viewport.
  static double pagePadding(double screenWidth) {
    if (screenWidth < 1100) return 18;
    if (screenWidth < 1280) return 22;
    if (screenWidth < 1700) return 28;
    return 32;
  }

  /// Below this the dashboard's two-column body stacks instead of forcing
  /// a desktop layout into a narrow window.
  static const double stackBreakpoint = 1180;

  /// Below this a row of summary cards wraps into a grid.
  static const double cardRowBreakpoint = 820;

  // ------------------------------------------------------------- components
  /// The standard panel: white surface, hairline border, barely-there lift.
  static BoxDecoration card({double radius = rXl, bool hovered = false}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: hovered ? borderStrong : border),
      boxShadow: hovered ? shadowHover : shadowSm,
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
    String? prefixText,
    bool dense = false,
  }) {
    final radius = BorderRadius.circular(rMd);

    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        color: textPrimary,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
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

  /// Label that sits above a field in a form.
  static const TextStyle fieldLabel = TextStyle(
    color: textSecondary,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Corner radius of a dropdown's popup, so it reads as an extension of
  /// the field that opened it.
  static const double menuRadius = rMd;

  // -------------------------------------------------------------- typography
  static const TextStyle pageTitle = TextStyle(
    color: blue3,
    fontSize: 23,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const TextStyle sectionTitle = TextStyle(
    color: textPrimary,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
  );

  static const TextStyle sectionSubtitle = TextStyle(
    color: textMuted,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle eyebrow = TextStyle(
    color: textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.7,
  );

  // ----------------------------------------------------------------- buttons
  static ButtonStyle primaryButton({EdgeInsetsGeometry? padding}) {
    return ElevatedButton.styleFrom(
      backgroundColor: blue1,
      foregroundColor: white,
      disabledBackgroundColor: const Color(0xFFA9C0CE),
      disabledForegroundColor: white,
      elevation: 0,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    );
  }

  static ButtonStyle secondaryButton({EdgeInsetsGeometry? padding}) {
    return OutlinedButton.styleFrom(
      backgroundColor: surface,
      foregroundColor: blue3,
      side: const BorderSide(color: borderStrong),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    );
  }

  static ButtonStyle dangerButton({EdgeInsetsGeometry? padding}) {
    return ElevatedButton.styleFrom(
      backgroundColor: danger,
      foregroundColor: white,
      elevation: 0,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    );
  }
}

/// Restyles the popup menu of any dropdown beneath it.
///
/// Flutter paints a dropdown's currently-selected row with `focusColor`,
/// which defaults to a heavy grey block, and hovers with `hoverColor`. Both
/// are theme-level, so the only way to soften them is to override the theme
/// around the dropdown - this changes no behaviour, only those colours.
/// Pair it with `AppTheme.menuRadius` and `dropdownColor` on the dropdown
/// itself for the full treatment.
class AppMenuTheme extends StatelessWidget {
  final Widget child;

  const AppMenuTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);

    return Theme(
      data: base.copyWith(
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

/// The standard panel used for every dashboard / patients section.
///
/// Purely a container: it renders a header (tinted icon box, title,
/// optional subtitle and trailing widget) above whatever [child] is given.
class AdminSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  /// Foreground colour of the header icon.
  final Color accent;

  /// Background of the header icon container.
  final Color accentSoft;

  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AdminSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.accent = AppTheme.blue1,
    this.accentSoft = AppTheme.accentBlueSoft,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: AppTheme.iconBox(accentSoft),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.sectionTitle),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: AppTheme.sectionSubtitle),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

/// A small pill used for counts and statuses inside section headers.
class AdminPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  const AdminPill({
    super.key,
    required this.label,
    this.color = AppTheme.blue1,
    this.background = AppTheme.accentBlueSoft,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A shimmering placeholder block, used while real data is in flight.
///
/// Never renders text or numbers - only neutral shapes - so a loading
/// state can't be mistaken for data that has arrived.
class AdminSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const AdminSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppTheme.rSm,
  });

  @override
  State<AdminSkeleton> createState() => _AdminSkeletonState();
}

class _AdminSkeletonState extends State<AdminSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppTheme.surfaceTint,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              AppTheme.surfaceTint,
              AppTheme.accentSoft,
              _controller.value,
            ),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Lifts a card slightly while the pointer is over it.
class AdminHoverCard extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;

  const AdminHoverCard({super.key, required this.builder, this.onTap});

  @override
  State<AdminHoverCard> createState() => _AdminHoverCardState();
}

class _AdminHoverCardState extends State<AdminHoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final child = MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        duration: AppTheme.motion(context, AppTheme.fast),
        curve: AppTheme.ease,
        offset: _hovered ? const Offset(0, -0.008) : Offset.zero,
        child: widget.builder(context, _hovered),
      ),
    );

    if (widget.onTap == null) return child;

    return GestureDetector(onTap: widget.onTap, child: child);
  }
}
