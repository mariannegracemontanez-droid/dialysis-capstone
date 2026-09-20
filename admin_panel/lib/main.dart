import 'package:flutter/material.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/login_page.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://emnpezpkrrrilrcxnuwe.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVtbnBlenBrcnJyaWxyY3hudXdlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0MTkwNzcsImV4cCI6MjA4Nzk5NTA3N30.ow7VCTizP-Q6j-0FD4gtKWiok3kVUZFCxag5UWg9weM',
  );
  runApp(const ProviderScope(child: MyApp()));
}

Future<void> main2() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? dotenvError;
  try {
    await dotenv.load();
  } catch (e) {
    dotenvError = 'Failed to load .env file: $e';
  }

  final url = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (dotenvError != null || url == null || anonKey == null) {
    // Shows a helpful message instead of crashing.
    final message = dotenvError != null
        ? '$dotenvError\n\nMake sure you have a .env file in the project root.'
        : 'Missing .env values.\nMake sure .env contains SUPABASE_URL and SUPABASE_ANNON_KEY.';

    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text(message, textAlign: TextAlign.center)),
        ),
      ),
    );
    return;
  }

  await Supabase.initialize(url: url, anonKey: anonKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // The fallback shown before any page sets its own title, and the
      // name the OS task switcher uses. Each page refines it with
      // [AdminTitle].
      title: 'CureNurture | Admin',
      debugShowCheckedModeBanner: false,
      theme: _adminTheme(),
      home: const LoginPage(),
    );
  }
}

/// The panel-wide Material theme.
///
/// Presentation only. It sets the defaults every page and dialog inherits
/// - surfaces, dialog shape, dropdown popups, inputs, buttons, scrollbars,
/// date pickers - so the Admin matches the Super Admin portal without each
/// screen restating the same values. No routing, data or behaviour here.
ThemeData _adminTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppTheme.blue1,
      primary: AppTheme.blue1,
      onPrimary: AppTheme.white,
      surface: AppTheme.surface,
      onSurface: AppTheme.textPrimary,
      error: AppTheme.danger,
      brightness: Brightness.light,
    ),
  );

  final radiusMd = BorderRadius.circular(AppTheme.rMd);

  return base.copyWith(
    scaffoldBackgroundColor: AppTheme.canvas,
    canvasColor: AppTheme.surface,
    dividerColor: AppTheme.border,
    splashColor: AppTheme.accentBlueSoft,
    highlightColor: Colors.transparent,
    hoverColor: AppTheme.surfaceTint,
    focusColor: AppTheme.accentBlueSoft,

    dividerTheme: const DividerThemeData(
      color: AppTheme.border,
      thickness: 1,
      space: 1,
    ),

    // Every AlertDialog in the panel picks this up, so the ones that are a
    // plain question look like the purpose-built modals around them.
    dialogTheme: DialogThemeData(
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: const Color(0x1416324A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        side: const BorderSide(color: AppTheme.border),
      ),
      titleTextStyle: const TextStyle(
        color: AppTheme.blue3,
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      contentTextStyle: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 13.5,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    ),

    // Dropdown popups: a light surface with a soft edge, reading as an
    // extension of the field that opened them.
    popupMenuTheme: PopupMenuThemeData(
      color: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: const Color(0x1416324A),
      shape: RoundedRectangleBorder(
        borderRadius: radiusMd,
        side: const BorderSide(color: AppTheme.border),
      ),
      textStyle: AppTheme.fieldTextStyle,
    ),

    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: AppTheme.fieldTextStyle,
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppTheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: radiusMd,
            side: const BorderSide(color: AppTheme.border),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
      ),
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppTheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: radiusMd,
            side: const BorderSide(color: AppTheme.border),
          ),
        ),
      ),
    ),

    inputDecorationTheme: AppTheme.field().toInputDecorationTheme(),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: AppTheme.primaryButton(),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: AppTheme.secondaryButton(),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.blue1,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),

    // Scrollbars sit at the edge of whatever is actually scrolling, thin
    // and quiet until the pointer is near them.
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.dragged)) {
          return AppTheme.borderStrong;
        }
        return const Color(0x33A8BCC9);
      }),
      thickness: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.hovered) ? 9 : 7;
      }),
      radius: const Radius.circular(8),
      crossAxisMargin: 2,
      interactive: true,
    ),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: AppTheme.blue1,
      headerForegroundColor: AppTheme.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.rXl),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppTheme.blue3,
      contentTextStyle: const TextStyle(
        color: AppTheme.white,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radiusMd),
      insetPadding: const EdgeInsets.all(18),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppTheme.blue5,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      textStyle: const TextStyle(
        color: AppTheme.white,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      waitDuration: const Duration(milliseconds: 400),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppTheme.blue1,
      linearTrackColor: AppTheme.surfaceTint,
      circularTrackColor: AppTheme.surfaceTint,
    ),

    // Page transitions: a short, even fade on every platform rather than
    // the platform-default slide.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// Turns the shared [AppTheme.field] decoration into the theme-level
/// default, so a bare `TextField()` anywhere in the panel already looks
/// right without repeating the decoration.
extension on InputDecoration {
  InputDecorationThemeData toInputDecorationTheme() {
    return InputDecorationThemeData(
      filled: filled ?? false,
      fillColor: fillColor,
      hintStyle: hintStyle,
      labelStyle: labelStyle,
      floatingLabelStyle: floatingLabelStyle,
      errorStyle: errorStyle,
      contentPadding: contentPadding,
      border: border,
      enabledBorder: enabledBorder,
      disabledBorder: disabledBorder,
      focusedBorder: focusedBorder,
      errorBorder: errorBorder,
      focusedErrorBorder: focusedErrorBorder,
    );
  }
}
