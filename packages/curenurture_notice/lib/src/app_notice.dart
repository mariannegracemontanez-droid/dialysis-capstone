import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'notice_theme.dart';

/// The four kinds of message a portal can raise.
enum NoticeType { success, error, info, warning }

/// The one place a CureNurture portal reports the outcome of an action.
///
/// ## Why it is an overlay entry and not a SnackBar or a Dialog
///
/// A `SnackBar` is hosted by the `ScaffoldMessenger` inside the page, so a
/// dialog -- which is a route in the Navigator's overlay, painted above
/// the whole page -- covers it. Every "save failed" message raised from
/// inside a modal was landing underneath that modal, unread.
///
/// A notice is therefore inserted straight into the **root overlay**: the
/// same overlay the Navigator paints its dialog routes into. An entry
/// inserted there goes on top of the entries already in it, so it sits
/// above any open modal by construction. That is ordinary Flutter
/// layering, not a hand-picked z-index, and it keeps working no matter how
/// many modals are stacked.
///
/// The layer underneath the card is a real barrier, so the modal behind it
/// cannot be clicked while a notice is up. Removing the entry restores the
/// modal exactly as it was -- nothing about the modal's route or state is
/// touched.
///
///   page -> modal route -> notice barrier -> notice card
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
/// ## Calling it
///
/// Portals do not normally call [AppNotice] directly -- each one exposes a
/// named facade (`AdminNotice`, `SuperAdminNotice`) that fills in its own
/// [NoticeTheme], so call sites stay short and a portal's palette is stated
/// in exactly one file.
class AppNotice {
  const AppNotice._();

  /// How long a self-closing notice stays up.
  static const Duration successDuration = Duration(seconds: 4);
  static const Duration infoDuration = Duration(seconds: 5);

  /// Entries currently on screen, newest last. Kept so a page can clear
  /// them when it navigates away.
  static final List<OverlayEntry> _active = <OverlayEntry>[];

  /// True while at least one notice is up. Useful in tests.
  static bool get isShowing => _active.isNotEmpty;

  /// An action finished. Closes itself after [successDuration].
  static Future<void> success(
    BuildContext context,
    String message, {
    required NoticeTheme theme,
    String? title,
  }) {
    return _present<void>(
      context: context,
      theme: theme,
      spec: _NoticeSpec(
        type: NoticeType.success,
        title: title ?? 'Success',
        message: message,
        autoDismissAfter: successDuration,
        dismissOnBarrierTap: true,
      ),
    );
  }

  /// Something worth knowing that is not a failure. Closes itself after
  /// [infoDuration].
  static Future<void> info(
    BuildContext context,
    String message, {
    required NoticeTheme theme,
    String? title,
  }) {
    return _present<void>(
      context: context,
      theme: theme,
      spec: _NoticeSpec(
        type: NoticeType.info,
        title: title ?? 'Just so you know',
        message: message,
        autoDismissAfter: infoDuration,
        dismissOnBarrierTap: true,
      ),
    );
  }

  /// An operation failed. Stays up until it is acknowledged, so a failed
  /// save can never scroll past unseen.
  static Future<void> error(
    BuildContext context,
    String message, {
    required NoticeTheme theme,
    String? title,
    String okLabel = 'OK',
  }) {
    return _present<void>(
      context: context,
      theme: theme,
      spec: _NoticeSpec(
        type: NoticeType.error,
        title: title ?? 'Something went wrong',
        message: message,
        confirmLabel: okLabel,
      ),
    );
  }

  /// A decision that has to be made before something consequential
  /// happens. Never closes on its own and never on an outside click.
  ///
  /// Completes true when confirmed, false when cancelled or dismissed --
  /// so `if (await ...confirm(...))` reads naturally and a dismissal is
  /// always the safe answer.
  static Future<bool> confirm(
    BuildContext context, {
    required NoticeTheme theme,
    required String title,
    required String message,
    String confirmLabel = 'Continue',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    Widget? detail,
    IconData? icon,
  }) async {
    final result = await _present<bool>(
      context: context,
      theme: theme,
      spec: _NoticeSpec(
        type: NoticeType.warning,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        detail: detail,
        iconOverride: icon,
      ),
    );

    return result ?? false;
  }

  /// Closes every notice that is currently up.
  static void dismissAll() {
    for (final entry in List<OverlayEntry>.from(_active)) {
      if (entry.mounted) entry.remove();
    }
    _active.clear();
  }

  // ------------------------------------------------------------------

  static Future<T?> _present<T>({
    required BuildContext context,
    required NoticeTheme theme,
    required _NoticeSpec spec,
  }) {
    // rootOverlay: the overlay the Navigator paints dialog routes into.
    // Inserting here is what puts the notice above an open modal.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    // No overlay means there is no app to show it in (a disposed context,
    // or a widget built outside a Navigator). Failing silently is better
    // than throwing on top of whatever already went wrong.
    if (overlay == null) {
      assert(() {
        debugPrint('AppNotice: no overlay available for "${spec.message}"');
        return true;
      }());
      return Future<T?>.value();
    }

    final completer = Completer<T?>();
    late final OverlayEntry entry;
    var closed = false;

    void close(Object? result) {
      if (closed) return;
      closed = true;

      _active.remove(entry);
      if (entry.mounted) entry.remove();
      if (!completer.isCompleted) completer.complete(result as T?);
    }

    entry = OverlayEntry(
      builder: (_) => _NoticeLayer(spec: spec, theme: theme, onClosed: close),
    );

    _active.add(entry);
    overlay.insert(entry);

    return completer.future;
  }
}

/// Everything one notice needs to render itself.
class _NoticeSpec {
  final NoticeType type;
  final String title;
  final String message;

  /// Null for the types that wait to be acknowledged.
  final Duration? autoDismissAfter;

  /// Error and warning ignore a click on the barrier on purpose.
  final bool dismissOnBarrierTap;

  final String? confirmLabel;
  final String? cancelLabel;
  final bool destructive;
  final Widget? detail;

  /// Lets a caller name the action more precisely than the type's default
  /// icon does (a trash can for a delete, a calendar for a reschedule).
  final IconData? iconOverride;

  const _NoticeSpec({
    required this.type,
    required this.title,
    required this.message,
    this.autoDismissAfter,
    this.dismissOnBarrierTap = false,
    this.confirmLabel,
    this.cancelLabel,
    this.destructive = false,
    this.detail,
    this.iconOverride,
  });

  bool get isConfirmation => type == NoticeType.warning;

  Color accent(NoticeTheme theme) {
    switch (type) {
      case NoticeType.success:
        return theme.success;
      case NoticeType.error:
        return theme.error;
      case NoticeType.info:
        return theme.info;
      case NoticeType.warning:
        return theme.warning;
    }
  }

  Color accentSoft(NoticeTheme theme) {
    switch (type) {
      case NoticeType.success:
        return theme.successSoft;
      case NoticeType.error:
        return theme.errorSoft;
      case NoticeType.info:
        return theme.infoSoft;
      case NoticeType.warning:
        return theme.warningSoft;
    }
  }

  IconData get icon {
    final override = iconOverride;
    if (override != null) return override;

    switch (type) {
      case NoticeType.success:
        return Icons.check_circle_rounded;
      case NoticeType.error:
        return Icons.error_rounded;
      case NoticeType.info:
        return Icons.info_rounded;
      case NoticeType.warning:
        return Icons.warning_amber_rounded;
    }
  }
}

/// The barrier plus the card, as one overlay entry.
class _NoticeLayer extends StatefulWidget {
  final _NoticeSpec spec;
  final NoticeTheme theme;
  final void Function(Object? result) onClosed;

  const _NoticeLayer({
    required this.spec,
    required this.theme,
    required this.onClosed,
  });

  @override
  State<_NoticeLayer> createState() => _NoticeLayerState();
}

class _NoticeLayerState extends State<_NoticeLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 130),
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: widget.theme.enterCurve,
    reverseCurve: Curves.easeInCubic,
  );

  final FocusScopeNode _focusScope = FocusScopeNode(debugLabel: 'AppNotice');

  Timer? _autoDismiss;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();

    final after = widget.spec.autoDismissAfter;
    if (after != null) {
      _autoDismiss = Timer(after, () => _close(null));
    }
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _controller.dispose();
    _focusScope.dispose();
    super.dispose();
  }

  /// Plays the exit, then asks the owner to pull the entry.
  Future<void> _close(Object? result) async {
    if (_closing) return;
    _closing = true;

    _autoDismiss?.cancel();

    // A disposed ticker cannot animate; drop straight to removal.
    if (mounted) {
      await _controller.reverse();
    }

    widget.onClosed(result);
  }

  void _onBarrierTap() {
    if (!widget.spec.dismissOnBarrierTap) return;
    _close(null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Escape is "no": it cancels a confirmation and acknowledges the
      // rest. It never confirms anything.
      _close(widget.spec.isConfirmation ? false : null);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _close(widget.spec.isConfirmation ? true : null);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final theme = widget.theme;

    return FocusScope(
      node: _focusScope,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) {
          return Stack(
            children: [
              // The barrier. It is opaque to pointers either way, so the
              // modal underneath cannot be clicked by accident; whether a
              // tap *dismisses* is what differs by type.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onBarrierTap,
                  child: FadeTransition(
                    opacity: _curve,
                    child: ColoredBox(color: theme.barrier),
                  ),
                ),
              ),

              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: FadeTransition(
                        opacity: _curve,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.94,
                            end: 1,
                          ).animate(_curve),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: _card(spec, theme),
      ),
    );
  }

  Widget _card(_NoticeSpec spec, NoticeTheme theme) {
    return Semantics(
      liveRegion: true,
      container: true,
      label: '${spec.title}. ${spec.message}',
      child: ConstrainedBox(
        // Comfortable on a phone-width window and never a banner on a
        // wide monitor.
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 260),
        child: Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(theme.cardRadius),
              border: Border.all(color: theme.border),
              boxShadow: theme.shadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (spec.autoDismissAfter != null) _countdownBar(spec, theme),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 12, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: spec.accentSoft(theme),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          spec.icon,
                          color: spec.accent(theme),
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            spec.title,
                            style: TextStyle(
                              color: theme.titleText,
                              fontSize: 16,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () =>
                            _close(spec.isConfirmation ? false : null),
                        icon: const Icon(Icons.close_rounded, size: 19),
                        color: theme.iconMuted,
                        hoverColor: theme.hoverTint,
                        splashRadius: 20,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        // Lines the text up under the title, past the icon.
                        padding: const EdgeInsets.only(left: 54),
                        child: Text(
                          spec.message,
                          style: TextStyle(
                            color: theme.bodyText,
                            fontSize: 13.5,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (spec.detail != null) ...[
                        const SizedBox(height: 16),
                        spec.detail!,
                      ],
                    ],
                  ),
                ),

                if (spec.confirmLabel != null) _actions(spec, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A thin bar draining to zero, so a self-closing notice shows how long
  /// it has left rather than vanishing without warning.
  Widget _countdownBar(_NoticeSpec spec, NoticeTheme theme) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      return Container(height: 3, color: spec.accentSoft(theme));
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: spec.autoDismissAfter!,
      builder: (context, value, _) {
        return SizedBox(
          height: 3,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: spec.accentSoft(theme),
            valueColor: AlwaysStoppedAnimation<Color>(spec.accent(theme)),
          ),
        );
      },
    );
  }

  Widget _actions(_NoticeSpec spec, NoticeTheme theme) {
    final confirmStyle = spec.destructive || spec.type == NoticeType.error
        ? theme.destructiveButton
        : theme.confirmButton;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: BoxDecoration(
        color: theme.surfaceTint,
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cancel = spec.cancelLabel == null
              ? null
              : OutlinedButton(
                  onPressed: () => _close(false),
                  style: theme.cancelButton,
                  child: Text(spec.cancelLabel!),
                );

          final confirm = ElevatedButton(
            autofocus: true,
            onPressed: () => _close(spec.isConfirmation ? true : null),
            style: confirmStyle,
            child: Text(spec.confirmLabel!),
          );

          // Stack full-width when the card has narrowed, so neither label
          // gets clipped.
          if (constraints.maxWidth < 300 && cancel != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [confirm, const SizedBox(height: 10), cancel],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (cancel != null) ...[cancel, const SizedBox(width: 10)],
              confirm,
            ],
          );
        },
      ),
    );
  }
}
