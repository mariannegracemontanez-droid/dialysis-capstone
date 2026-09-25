import 'package:flutter/material.dart';

/// The colours and radii one portal lends to the notice system.
///
/// Presentation only, and deliberately small: it carries just the tokens the
/// notice card actually paints with, so a portal can adopt the notice system
/// without exporting its whole `AppTheme`. Every field is `const`-able, and
/// the Admin panel and the Super Admin portal currently pass identical
/// values -- but they stay two separate instances, so if one portal's palette
/// ever moves, its notices move with it instead of silently keeping the
/// other's colours.
///
/// Nothing here decides *behaviour*. Auto-dismiss windows, barrier rules and
/// button layout live in the notice itself, which is the whole point of
/// sharing it.
@immutable
class NoticeTheme {
  // -------------------------------------------------------------- surfaces
  /// The card itself.
  final Color surface;

  /// The footer strip the action buttons sit on.
  final Color surfaceTint;

  /// Hairline around the card.
  final Color border;

  /// The slightly stronger line used for the outlined (Cancel) button.
  final Color borderStrong;

  /// What is painted over the page -- and over any open modal -- while a
  /// notice is up. Semi-transparent by design: the modal underneath should
  /// stay recognisable, just plainly out of reach.
  final Color barrier;

  // ------------------------------------------------------------------ text
  /// The notice title.
  final Color titleText;

  /// The message body.
  final Color bodyText;

  /// The close (X) glyph.
  final Color iconMuted;

  /// Hover wash behind the close button.
  final Color hoverTint;

  // --------------------------------------------------------------- buttons
  /// Fill of the confirming button (OK / Continue) when it is not
  /// destructive.
  final Color primary;

  /// Label colour on [primary] and on the destructive fill.
  final Color onPrimary;

  /// Fill of [primary] while the button is disabled. The notice never
  /// disables its own buttons today; it is here so the style matches the
  /// portals' other buttons exactly.
  final Color primaryDisabled;

  // ---------------------------------------------------- one pair per type
  // Strong colour for the icon and the countdown bar, soft colour for the
  // circle behind the icon and the bar's track.
  final Color success;
  final Color successSoft;
  final Color error;
  final Color errorSoft;
  final Color info;
  final Color infoSoft;
  final Color warning;
  final Color warningSoft;

  // -------------------------------------------------------- shape & motion
  /// Corner radius of the card.
  final double cardRadius;

  /// Corner radius of the action buttons.
  final double buttonRadius;

  /// Lift under the card.
  final List<BoxShadow> shadow;

  /// Entrance curve. The exit is always its mirror, so a portal cannot set
  /// the two out of step.
  final Curve enterCurve;

  const NoticeTheme({
    required this.surface,
    required this.surfaceTint,
    required this.border,
    required this.borderStrong,
    required this.barrier,
    required this.titleText,
    required this.bodyText,
    required this.iconMuted,
    required this.hoverTint,
    required this.primary,
    required this.onPrimary,
    required this.primaryDisabled,
    required this.success,
    required this.successSoft,
    required this.error,
    required this.errorSoft,
    required this.info,
    required this.infoSoft,
    required this.warning,
    required this.warningSoft,
    required this.cardRadius,
    required this.buttonRadius,
    required this.shadow,
    this.enterCurve = Curves.easeOutCubic,
  });

  // --------------------------------------------------------- button styles
  // Built here rather than taken from a portal, so the two portals cannot
  // drift apart on the one control the notice owns. These reproduce the
  // Admin panel's existing primary/secondary/danger buttons exactly.

  /// OK, and a non-destructive Continue.
  ButtonStyle get confirmButton => ElevatedButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: onPrimary,
    disabledBackgroundColor: primaryDisabled,
    disabledForegroundColor: onPrimary,
    elevation: 0,
    padding: _buttonPadding,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(buttonRadius),
    ),
    textStyle: _buttonTextStyle,
  );

  /// A Continue that deletes, declines or otherwise cannot be undone, and
  /// the OK on an error.
  ButtonStyle get destructiveButton => ElevatedButton.styleFrom(
    backgroundColor: error,
    foregroundColor: onPrimary,
    elevation: 0,
    padding: _buttonPadding,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(buttonRadius),
    ),
    textStyle: _buttonTextStyle,
  );

  /// Cancel.
  ButtonStyle get cancelButton => OutlinedButton.styleFrom(
    backgroundColor: surface,
    foregroundColor: titleText,
    side: BorderSide(color: borderStrong),
    padding: _buttonPadding,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(buttonRadius),
    ),
    textStyle: _buttonTextStyle,
  );

  static const EdgeInsets _buttonPadding = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 14,
  );

  static const TextStyle _buttonTextStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );
}
