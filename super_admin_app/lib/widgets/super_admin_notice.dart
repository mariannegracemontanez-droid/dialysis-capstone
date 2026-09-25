import 'package:curenurture_notice/curenurture_notice.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

export 'package:curenurture_notice/curenurture_notice.dart' show NoticeType;

/// The Super Admin portal's name for the shared notice system.
///
/// ## Why this replaced the portal's snack bars
///
/// A `SnackBar` is hosted by the `ScaffoldMessenger` *inside* the page, so a
/// dialog -- which is a route in the Navigator's overlay, painted above the
/// whole page -- covers it. Messages raised while a Super Admin modal was
/// open (a failed center save, a failed admin delete) were landing at the
/// bottom of the screen underneath that modal, unread.
///
/// A notice is inserted straight into the **root overlay** instead: the same
/// overlay the Navigator paints its dialog routes into, so it goes on top of
/// whatever is already there. That is ordinary Flutter layering, not a
/// hand-picked z-index, and it keeps working however many modals are
/// stacked. The layer under the card is a real barrier, so the modal behind
/// it cannot be clicked while a notice is up, and removing the notice
/// restores that modal exactly as it was.
///
///   Super Admin page -> Super Admin modal -> notice barrier -> notice card
///
/// ## The four types
///
/// | type      | auto-closes | outside click | buttons        |
/// |-----------|-------------|---------------|----------------|
/// | success   | 4s          | dismisses     | X              |
/// | info      | 5s          | dismisses     | X              |
/// | error     | never       | ignored       | X + OK         |
/// | warning   | never       | ignored       | Cancel/Continue|
///
/// None of that is implemented here. It all lives in
/// `package:curenurture_notice`, which the Admin panel uses through its own
/// `AdminNotice` facade -- one implementation, so the two portals cannot
/// drift apart on how an outcome is reported. All this file decides is what
/// the portal looks like, in [_theme] below.
class SuperAdminNotice {
  const SuperAdminNotice._();

  /// The portal's palette, handed to the shared notice. Only colours and
  /// radii -- nothing here changes behaviour.
  static final NoticeTheme _theme = NoticeTheme(
    surface: AppTheme.surface,
    surfaceTint: AppTheme.surfaceTint,
    border: AppTheme.border,
    borderStrong: AppTheme.borderStrong,
    barrier: const Color(0x4D1F2D3D),
    titleText: AppTheme.blue3,
    bodyText: AppTheme.textSecondary,
    iconMuted: AppTheme.iconMuted,
    hoverTint: AppTheme.accentSoft,
    primary: AppTheme.blue1,
    onPrimary: AppTheme.white,
    primaryDisabled: const Color(0xFFA9C0CE),
    success: AppTheme.accentGreen,
    successSoft: AppTheme.accentGreenSoft,
    error: AppTheme.danger,
    errorSoft: AppTheme.dangerSoft,
    info: AppTheme.blue1,
    infoSoft: AppTheme.accentBlueSoft,
    warning: AppTheme.accentOrange,
    warningSoft: AppTheme.accentOrangeSoft,
    cardRadius: AppTheme.rXl,
    buttonRadius: AppTheme.rMd,
    shadow: AppTheme.shadowMd,
    enterCurve: Curves.easeOutCubic,
  );

  /// How long a self-closing notice stays up.
  static const Duration successDuration = AppNotice.successDuration;
  static const Duration infoDuration = AppNotice.infoDuration;

  /// True while at least one notice is up. Useful in tests.
  static bool get isShowing => AppNotice.isShowing;

  /// An action finished. Closes itself after [successDuration].
  static Future<void> success(
    BuildContext context,
    String message, {
    String? title,
  }) {
    return AppNotice.success(context, message, theme: _theme, title: title);
  }

  /// Something worth knowing that is not a failure. Closes itself after
  /// [infoDuration].
  static Future<void> info(
    BuildContext context,
    String message, {
    String? title,
  }) {
    return AppNotice.info(context, message, theme: _theme, title: title);
  }

  /// An operation failed. Stays up until the super admin acknowledges it,
  /// so a failed save can never be mistaken for a successful one.
  static Future<void> error(
    BuildContext context,
    String message, {
    String? title,
    String okLabel = 'OK',
  }) {
    return AppNotice.error(
      context,
      message,
      theme: _theme,
      title: title,
      okLabel: okLabel,
    );
  }

  /// A decision the super admin has to make before something consequential
  /// happens. Never closes on its own and never on an outside click.
  ///
  /// Completes true when confirmed, false when cancelled or dismissed --
  /// so `if (await SuperAdminNotice.confirm(...))` reads naturally and a
  /// dismissal is always the safe answer.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Continue',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    Widget? detail,
    IconData? icon,
  }) {
    return AppNotice.confirm(
      context,
      theme: _theme,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      detail: detail,
      icon: icon,
    );
  }

  /// Closes every notice that is currently up.
  static void dismissAll() => AppNotice.dismissAll();
}
