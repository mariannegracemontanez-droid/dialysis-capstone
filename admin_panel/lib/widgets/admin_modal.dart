import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_notice.dart';

/// The CureNurture Admin modal system.
///
/// Presentation only. Every dialog in the panel is built from [AdminModal]
/// so that width, padding, header, footer, corner radius and shadow are
/// decided in exactly one place, and [showAdminDialog] gives all of them
/// the same entrance and exit.
///
/// Nothing here decides *what* a dialog does - callers keep their own
/// actions, validation and navigation results.

/// Opens a dialog with the panel's shared barrier and transition.
///
/// A drop-in replacement for `showDialog`: the returned future still
/// completes with whatever the dialog is popped with, so an awaited
/// `showAdminDialog<bool>` behaves exactly like `showDialog<bool>`.
Future<T?> showAdminDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final duration = AppTheme.motion(context, AppTheme.normal);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x591F2D3D),
    transitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppTheme.ease,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// How wide a modal should be. The three sizes cover everything in the
/// panel, so no dialog invents its own width.
enum AdminModalSize {
  /// Confirmations and single-decision dialogs.
  small(420),

  /// Standard forms - a handful of fields.
  medium(540),

  /// Detail views and multi-column forms.
  large(720),

  /// Full patient records.
  xlarge(1000);

  final double width;
  const AdminModalSize(this.width);
}

/// The shared modal shell: header, scrollable body, pinned footer.
class AdminModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final Color accentSoft;
  final AdminModalSize size;

  /// Body content. Scrolls on its own when taller than the viewport
  /// allows, so the header and footer stay put.
  final Widget child;

  /// Buttons along the bottom edge. Laid out right-aligned on wide
  /// viewports and stacked when the modal has to narrow.
  final List<Widget> actions;

  /// An error or validation message shown between the body and the
  /// footer. Null hides the strip entirely.
  final String? errorText;

  /// Shown instead of the close button when the dialog is mid-save.
  final bool busy;

  /// Set false for a dialog that must be dismissed through its actions.
  final bool showCloseButton;

  final EdgeInsetsGeometry bodyPadding;

  const AdminModal({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.accent = AppTheme.blue1,
    this.accentSoft = AppTheme.accentBlueSoft,
    this.size = AdminModalSize.medium,
    this.actions = const [],
    this.errorText,
    this.busy = false,
    this.showCloseButton = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(24, 20, 24, 20),
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width - 48;
    final width = size.width > maxWidth ? maxWidth : size.width;

    // Leave the modal room to breathe rather than letting it grow to the
    // full height of a tall monitor.
    final maxHeight = media.size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rXl),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.shadowMd,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const Divider(height: 1, thickness: 1, color: AppTheme.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: bodyPadding,
                  child: child,
                ),
              ),
              if (errorText != null) _errorStrip(errorText!),
              if (actions.isNotEmpty) _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.surface, AppTheme.headerTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: AppTheme.iconBox(accentSoft, radius: AppTheme.rLg),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.blue3,
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (showCloseButton)
            IconButton(
              tooltip: 'Close',
              onPressed: busy ? null : () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, size: 19),
              color: AppTheme.iconMuted,
              hoverColor: AppTheme.accentSoft,
              splashRadius: 20,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Widget _errorStrip(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.dangerSoft,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: const Color(0xFFF0CFCF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppTheme.danger,
              size: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF8E3330),
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceTint,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow modals stack their buttons full-width rather than
          // squeezing them until the labels clip.
          if (constraints.maxWidth < 380) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  actions[actions.length - 1 - i],
                ],
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                actions[i],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A labelled form field wrapper, so every label in every modal sits at
/// the same size, weight and distance from its input.
class AdminField extends StatelessWidget {
  final String label;
  final String? helper;
  final bool required;
  final Widget child;

  const AdminField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppTheme.fieldLabel),
            if (required) ...[
              const SizedBox(width: 3),
              const Text(
                '*',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (helper != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  helper!,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// Standard vertical rhythm between fields inside a modal body.
class AdminFieldGap extends StatelessWidget {
  const AdminFieldGap({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 18);
}

/// A confirmation in the panel's own styling.
///
/// Kept as the panel's confirmation entry point -- every existing caller
/// still calls this and still gets a `Future<bool?>` back -- but it is now
/// a warning notice from [AdminNotice] rather than a dialog of its own.
/// That change is what makes a confirmation raised from *inside* an Admin
/// modal appear above that modal instead of behind it, and it stops an
/// outside click from silently answering a consequential question.
Future<bool?> showAdminConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  bool destructive = false,
  Widget? detail,
}) {
  return AdminNotice.confirm(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    destructive: destructive,
    detail: detail,
    icon: icon,
  );
}
