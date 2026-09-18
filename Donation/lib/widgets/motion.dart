import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motion helpers for the donation site.
///
/// Every animation here is decorative: the page renders complete and fully
/// interactive whether or not a single one of them runs. That matters for
/// two reasons - a visitor who has asked their system for reduced motion
/// gets the page with the movement switched off, and a donate button is
/// never waiting on an animation before it can be pressed.
class Motion {
  const Motion._();

  /// True when the platform asks for reduced motion. On the web this maps
  /// to the `prefers-reduced-motion` media query.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Broadcasts a tick on every scroll frame so descendant [Reveal] and
/// [CountUp] widgets can re-check whether they have come into view.
///
/// One listener for the whole page, rather than one per animated element.
class RevealScope extends StatefulWidget {
  const RevealScope({super.key, required this.child});

  final Widget child;

  @override
  State<RevealScope> createState() => _RevealScopeState();
}

class _RevealScopeState extends State<RevealScope> {
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _RevealTick(
      tick: _tick,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _tick.value++;
          // Never swallow the notification - the scroll view still needs it.
          return false;
        },
        child: widget.child,
      ),
    );
  }
}

class _RevealTick extends InheritedWidget {
  const _RevealTick({required this.tick, required super.child});

  final ValueNotifier<int> tick;

  static ValueNotifier<int>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_RevealTick>()
        ?.tick;
  }

  @override
  bool updateShouldNotify(_RevealTick oldWidget) => tick != oldWidget.tick;
}

/// Calls [builder] with `false`, then with `true` once this widget's box has
/// scrolled far enough into the viewport to be worth animating.
///
/// Fires once and then stops listening, so a revealed section never
/// re-animates when the visitor scrolls back up past it.
class VisibilityTrigger extends StatefulWidget {
  const VisibilityTrigger({
    super.key,
    required this.builder,
    this.fraction = 0.88,
  });

  final Widget Function(BuildContext context, bool visible) builder;

  /// How far down the viewport the widget's top edge must reach before it
  /// counts as visible, as a fraction of viewport height.
  final double fraction;

  @override
  State<VisibilityTrigger> createState() => _VisibilityTriggerState();
}

class _VisibilityTriggerState extends State<VisibilityTrigger> {
  bool _visible = false;
  ValueNotifier<int>? _tick;

  @override
  void initState() {
    super.initState();
    // Anything already on screen at first paint reveals straight away, so
    // above-the-fold content is never stuck invisible waiting for a scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final tick = _RevealTick.maybeOf(context);

    if (tick != _tick) {
      _tick?.removeListener(_check);
      _tick = tick;
      _tick?.addListener(_check);
    }

    // With no RevealScope above us there is nothing to listen to, so show
    // the content rather than leaving it permanently hidden.
    if (_tick == null && !_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_visible) setState(() => _visible = true);
      });
      return;
    }

    // Dependencies also change when the window is resized, which can bring
    // a section into view without any scrolling happening. Re-check, or
    // content that was below the fold would stay hidden.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _tick?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_visible || !mounted) return;

    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) return;

    final viewport = MediaQuery.of(context).size.height;
    final top = object.localToGlobal(Offset.zero).dy;

    if (top < viewport * widget.fraction && top + object.size.height > 0) {
      _tick?.removeListener(_check);
      setState(() => _visible = true);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _visible);
}

/// Fades and lifts [child] into place when it scrolls into view.
class Reveal extends StatelessWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.offsetY = 28,
    this.durationMs = 620,
  });

  final Widget child;
  final int delayMs;
  final double offsetY;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;

    return VisibilityTrigger(
      builder: (context, visible) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: visible ? 1 : 0),
          duration: Duration(milliseconds: durationMs + delayMs),
          curve: Interval(
            // Turns the delay into a slice of one curve rather than a timer,
            // so a staggered row still finishes together.
            delayMs == 0
                ? 0
                : (delayMs / (durationMs + delayMs)).clamp(0.0, 0.6),
            1,
            curve: Curves.easeOutCubic,
          ),
          child: child,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, offsetY * (1 - value)),
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}

/// Counts from zero up to [value] the first time it scrolls into view.
///
/// Only ever used for numbers that come from real records - it animates a
/// figure, it does not invent one.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.durationMs = 1400,
  });

  final num value;
  final TextStyle style;
  final String prefix;
  final String suffix;
  final int durationMs;

  String _format(num n) {
    final whole = n.round();
    final digits = whole.abs().toString();
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }

    return '${whole < 0 ? '-' : ''}$buffer';
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return Text('$prefix${_format(value)}$suffix', style: style);
    }

    return VisibilityTrigger(
      builder: (context, visible) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: visible ? value.toDouble() : 0),
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
          builder: (context, current, _) {
            return Text(
              '$prefix${_format(current)}$suffix',
              style: style,
            );
          },
        );
      },
    );
  }
}

/// Lifts and optionally brightens [child] on pointer hover.
///
/// Wraps rather than replaces whatever sits inside, so a hover treatment
/// can be added to a card without touching what the card does.
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.builder,
    this.lift = 6,
    this.scale = 1.0,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final double lift;
  final double scale;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    final active = _hovered && !reduced;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        offset: Offset(0, active ? -widget.lift / 100 : 0),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          scale: active ? widget.scale : 1.0,
          // The hover state is still reported when motion is reduced, so a
          // card can change its border or shadow without moving.
          child: widget.builder(context, _hovered),
        ),
      ),
    );
  }
}

/// A slow, continuous drift. Used only on decorative background shapes.
class Floating extends StatefulWidget {
  const Floating({
    super.key,
    required this.child,
    this.amplitude = 10,
    this.seconds = 7,
    this.phase = 0,
  });

  final Widget child;
  final double amplitude;
  final int seconds;

  /// Offsets the cycle so several floating shapes don't move in lockstep.
  final double phase;

  @override
  State<Floating> createState() => _FloatingState();
}

class _FloatingState extends State<Floating>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = (_controller.value + widget.phase) * 2 * math.pi;
        return Transform.translate(
          offset: Offset(0, math.sin(t) * widget.amplitude),
          child: child,
        );
      },
    );
  }
}
