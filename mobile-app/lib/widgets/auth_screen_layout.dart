import 'package:flutter/material.dart';

/// Full-screen layout for the Login, Create Account and Forgot Password
/// screens.
///
/// The background is painted *behind* a transparent [Scaffold] rather than
/// inside its body. A Scaffold shrinks its body when the keyboard opens;
/// a `BoxFit.cover` image inside that body was re-scaled and re-cropped to
/// the shorter area, so the blue background visibly jumped. Out here it is
/// always laid out at the full screen size and never moves.
///
/// Only the form is resized by the keyboard (`resizeToAvoidBottomInset`
/// stays on), so the scroll view can still bring the focused field, its
/// error message and the primary button into view above the keyboard.
class AuthScreenLayout extends StatelessWidget {
  final Color backgroundColor;
  final bool showBackgroundImage;
  final Color overlayColor;
  final EdgeInsets padding;
  final Widget child;

  const AuthScreenLayout({
    super.key,
    required this.backgroundColor,
    required this.showBackgroundImage,
    required this.overlayColor,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: backgroundColor),
        if (showBackgroundImage)
          Image.asset(
            'lib/asset/Image/image 4.png',
            fit: BoxFit.cover,
            // Decorative; keeps screen readers on the form.
            excludeFromSemantics: true,
          ),
        ColoredBox(color: overlayColor),
        Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          body: GestureDetector(
            // Tapping outside a field closes the keyboard.
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: padding,
                child: Center(
                  // Keeps the form a readable width on tablets/landscape.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Don't have an account? Create Account"-style footer. Wraps onto two
/// lines on narrow screens or with large text instead of overflowing, and
/// gives the link a full 48px tap target.
class AuthPromptLink extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onPressed;
  final Color promptColor;
  final Color linkColor;

  const AuthPromptLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onPressed,
    required this.promptColor,
    required this.linkColor,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prompt, style: TextStyle(color: promptColor, fontSize: 13)),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: linkColor,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          child: Text(
            action,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
