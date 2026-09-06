import 'package:flutter/material.dart';

/// Controls the Dark/Light appearance of the login and signup screens only.
/// The rest of the app is unaffected — this exists purely so those two
/// screens can offer a lighter alternative to their default dark,
/// photo-background look.
///
/// This is intentionally a simple in-memory singleton (not persisted across
/// app restarts) rather than wiring a full app-wide ThemeData/ThemeMode,
/// since the requirement is scoped to just these two screens.
class AuthThemeController {
  AuthThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  static bool get isDark => mode.value == ThemeMode.dark;

  static void toggle() {
    mode.value = isDark ? ThemeMode.light : ThemeMode.dark;
  }
}

/// Color tokens for the login/signup screens, resolved once per build
/// based on the current [AuthThemeController] mode.
class AuthColors {
  final bool isDark;

  const AuthColors(this.isDark);

  // Background
  bool get useImageBackground => isDark;
  Color get backgroundSolid => const Color(0xFFF3F7FA);
  Color get overlay =>
      isDark ? Colors.black.withOpacity(0.28) : Colors.transparent;

  // Headline text
  Color get title => isDark ? Colors.white : const Color(0xFF173B4F);
  Color get subtitle =>
      isDark ? Colors.white.withOpacity(0.72) : const Color(0xFF6B7C86);

  // Card behind the form
  Color get cardFill => isDark
      ? const Color(0xFF26333D).withOpacity(0.88)
      : const Color(0xFFE8F1F5);
  Color get cardBorder =>
      isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFD3E4ED);

  // Tint used by signup's glass cards (frosted look in dark mode over the
  // photo background; a flat light blue tint once there's no photo).
  Color get glassTint => isDark ? Colors.white : const Color(0xFFE8F1F5);

  // Text fields
  Color get fieldText => isDark ? Colors.white : const Color(0xFF173B4F);
  Color get fieldHint =>
      isDark ? Colors.white.withOpacity(0.55) : const Color(0xFF6F7F89);
  Color get fieldIcon =>
      isDark ? Colors.white.withOpacity(0.65) : const Color(0xFF5F7280);
  Color get fieldFill =>
      isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF4F8FA);
  Color get fieldBorder =>
      isDark ? Colors.white.withOpacity(0.10) : const Color(0xFFE3EDF2);
  Color get fieldFocusedBorder =>
      isDark ? Colors.white.withOpacity(0.28) : const Color(0xFF2C5F7D);
  Color get errorText =>
      isDark ? const Color(0xFFFFC1C1) : const Color(0xFFB3261E);

  // Accents / buttons
  Color get primaryButton =>
      isDark ? const Color(0xFF2B7897) : const Color(0xFF2C5F7D);
  Color get link =>
      isDark ? const Color.fromRGBO(54, 173, 242, 1) : const Color(0xFF2C5F7D);
  Color get mutedText =>
      isDark ? Colors.white.withOpacity(0.72) : const Color(0xFF6B7C86);

  // Toggle button itself (sits on top of the background)
  Color get toggleIconColor => isDark ? Colors.white : const Color(0xFF2C5F7D);
  Color get toggleBg =>
      isDark ? Colors.white.withOpacity(0.14) : const Color(0xFFE8F1F5);
}

/// A small sun/moon button that flips [AuthThemeController.mode]. Place it
/// near the top of the login/signup screens.
class AuthThemeToggleButton extends StatelessWidget {
  final AuthColors colors;

  const AuthThemeToggleButton({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.toggleBg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: AuthThemeController.toggle,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            colors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            color: colors.toggleIconColor,
            size: 20,
          ),
        ),
      ),
    );
  }
}
