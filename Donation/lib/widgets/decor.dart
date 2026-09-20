import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'motion.dart';

/// Decorative artwork for the donation site.
///
/// The motif throughout is *flow* - dialysis is filtration and circulation,
/// so the page leans on soft moving curves and a steady pulse rather than
/// clinical imagery. Every painter here is marked as decorative for screen
/// readers and carries no information that is not also written in text.

/// Layered translucent curves used behind the hero and the closing CTA.
class FlowBackdrop extends StatelessWidget {
  const FlowBackdrop({super.key, this.opacity = 1.0});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          painter: _FlowBackdropPainter(),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FlowBackdropPainter extends CustomPainter {
  void _band(
    Canvas canvas,
    Size size, {
    required double yFactor,
    required double amplitude,
    required double thickness,
    required Color color,
  }) {
    final path = Path();
    final baseY = size.height * yFactor;

    path.moveTo(-40, baseY);

    // Two joined cubics make a long, lazy S-curve across the full width.
    path.cubicTo(
      size.width * 0.22,
      baseY - amplitude,
      size.width * 0.38,
      baseY + amplitude,
      size.width * 0.6,
      baseY,
    );
    path.cubicTo(
      size.width * 0.78,
      baseY - amplitude * 0.8,
      size.width * 0.9,
      baseY + amplitude * 0.5,
      size.width + 40,
      baseY - amplitude * 0.3,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _band(
      canvas,
      size,
      yFactor: 0.26,
      amplitude: size.height * 0.16,
      thickness: 1.4,
      color: Colors.white.withValues(alpha: 0.16),
    );
    _band(
      canvas,
      size,
      yFactor: 0.44,
      amplitude: size.height * 0.20,
      thickness: 2.6,
      color: Colors.white.withValues(alpha: 0.10),
    );
    _band(
      canvas,
      size,
      yFactor: 0.68,
      amplitude: size.height * 0.14,
      thickness: 1.2,
      color: Colors.white.withValues(alpha: 0.14),
    );

    // Two soft orbs to give the gradient some depth behind the curves.
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.18),
      size.height * 0.30,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Brand.teal.withValues(alpha: 0.30),
            Brand.teal.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.84, size.height * 0.18),
            radius: size.height * 0.30,
          ),
        ),
    );

    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.92),
      size.height * 0.26,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Brand.coral.withValues(alpha: 0.16),
            Brand.coral.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.08, size.height * 0.92),
            radius: size.height * 0.26,
          ),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _FlowBackdropPainter oldDelegate) => false;
}

/// A wave that transitions one section's background colour into the next.
///
/// [flip] draws the wave upside down, for a light section flowing back into
/// a dark one.
class WaveDivider extends StatelessWidget {
  const WaveDivider({
    super.key,
    required this.color,
    this.height = 64,
    this.flip = false,
  });

  final Color color;
  final double height;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _WavePainter(color: color, flip: flip)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.color, required this.flip});

  final Color color;
  final bool flip;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    if (flip) {
      path.moveTo(0, size.height);
      path.lineTo(0, size.height * 0.45);
      path.cubicTo(
        size.width * 0.30,
        -size.height * 0.25,
        size.width * 0.66,
        size.height * 1.05,
        size.width,
        size.height * 0.32,
      );
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, size.height * 0.55);
      path.cubicTo(
        size.width * 0.30,
        size.height * 1.25,
        size.width * 0.66,
        -size.height * 0.05,
        size.width,
        size.height * 0.68,
      );
      path.lineTo(size.width, 0);
    }

    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.flip != flip;
}

/// A slow, steady pulse line - a quiet visual reference to ongoing
/// treatment and continuing life, rather than an alarm.
class PulseLine extends StatefulWidget {
  const PulseLine({
    super.key,
    this.color = Colors.white,
    this.height = 40,
  });

  final Color color;
  final double height;

  @override
  State<PulseLine> createState() => _PulseLineState();
}

class _PulseLineState extends State<PulseLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
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
    final reduced = Motion.reduced(context);

    return ExcludeSemantics(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: reduced
            ? CustomPaint(
                painter: _PulsePainter(progress: 1, color: widget.color),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _PulsePainter(
                    progress: _controller.value,
                    color: widget.color,
                  ),
                ),
              ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final path = Path()..moveTo(0, mid);

    // A flat baseline with one gentle rise, repeated across the width.
    const segments = 4;
    final segment = size.width / segments;

    for (int i = 0; i < segments; i++) {
      final x = segment * i;
      path.lineTo(x + segment * 0.42, mid);
      path.quadraticBezierTo(
        x + segment * 0.52,
        mid - size.height * 0.34,
        x + segment * 0.62,
        mid,
      );
      path.lineTo(x + segment, mid);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // A soft highlight travelling along the line.
    final dotX = size.width * progress;
    canvas.drawCircle(
      Offset(dotX, mid),
      3.2,
      Paint()..color = color.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      Offset(dotX, mid),
      9,
      Paint()..color = color.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// An abstract two-lobed care glyph - kidney-adjacent without being a
/// clinical diagram - with a heart at its centre.
class CareGlyph extends StatelessWidget {
  const CareGlyph({
    super.key,
    this.size = 120,
    this.color = Brand.teal,
    this.accent = Brand.coral,
  });

  final double size;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: size,
        width: size,
        child: CustomPaint(
          painter: _CareGlyphPainter(color: color, accent: accent),
        ),
      ),
    );
  }
}

class _CareGlyphPainter extends CustomPainter {
  _CareGlyphPainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  Path _lobe(Size size, {required bool mirrored}) {
    final w = size.width;
    final h = size.height;
    final path = Path();

    // A bean/lobe shape, drawn on the left then optionally mirrored.
    path.moveTo(w * 0.42, h * 0.18);
    path.cubicTo(w * 0.14, h * 0.18, w * 0.06, h * 0.42, w * 0.10, h * 0.60);
    path.cubicTo(w * 0.14, h * 0.80, w * 0.30, h * 0.90, w * 0.44, h * 0.84);
    path.cubicTo(w * 0.34, h * 0.70, w * 0.32, h * 0.44, w * 0.42, h * 0.18);
    path.close();

    if (!mirrored) return path;

    return path.transform(
      (Matrix4.identity()
            ..translateByDouble(w, 0, 0, 1)
            ..scaleByDouble(-1, 1, 1, 1))
          .storage,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _lobe(size, mirrored: false),
      Paint()..color = color.withValues(alpha: 0.85),
    );
    canvas.drawPath(
      _lobe(size, mirrored: true),
      Paint()..color = color.withValues(alpha: 0.55),
    );

    // Heart at the junction of the two lobes.
    final w = size.width;
    final h = size.height;
    final heart = Path();
    final cx = w * 0.5;
    final cy = h * 0.54;
    final r = w * 0.15;

    heart.moveTo(cx, cy + r * 0.95);
    heart.cubicTo(
      cx - r * 1.5, cy + r * 0.05,
      cx - r * 0.72, cy - r * 1.05,
      cx, cy - r * 0.28,
    );
    heart.cubicTo(
      cx + r * 0.72, cy - r * 1.05,
      cx + r * 1.5, cy + r * 0.05,
      cx, cy + r * 0.95,
    );
    heart.close();

    canvas.drawPath(heart, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _CareGlyphPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.accent != accent;
}

/// Scattered, slowly drifting dots. Sits behind light sections to stop
/// large white areas feeling empty.
class DriftField extends StatelessWidget {
  const DriftField({super.key, this.color = Brand.teal, this.count = 5});

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final random = math.Random(7);

    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          if (!w.isFinite || !h.isFinite) return const SizedBox.shrink();

          return Stack(
            children: [
              for (int i = 0; i < count; i++)
                Positioned(
                  left: w * (0.05 + random.nextDouble() * 0.9),
                  top: h * (0.05 + random.nextDouble() * 0.9),
                  child: Floating(
                    amplitude: 6 + random.nextDouble() * 8,
                    seconds: 8 + random.nextInt(6),
                    phase: random.nextDouble(),
                    child: Container(
                      height: 8 + random.nextDouble() * 14,
                      width: 8 + random.nextDouble() * 14,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
