import 'dart:math' as math;
import 'dart:ui' show PathMetric;

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

  /// Length of the brighter stretch of line the dot leaves behind it.
  static const double _trail = 46;

  Path _line(Size size) {
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
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final path = _line(size);

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // The highlight travels ALONG the drawn line: its position is read from
    // the path itself at the current distance, so it climbs and falls with
    // every rise instead of sliding along a straight horizontal.
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    if (total <= 0) return;

    final distance = total * progress.clamp(0.0, 1.0);
    final head = _pointAt(metrics, distance);
    if (head == null) return;

    // A short, brighter stretch of the line behind the dot, so the motion
    // reads as a pulse moving through the curve.
    final trailStart = math.max(0.0, distance - _trail);
    double walked = 0;
    for (final metric in metrics) {
      final from = math.max(trailStart - walked, 0.0);
      final to = math.min(distance - walked, metric.length);
      if (to > from) {
        canvas.drawPath(
          metric.extractPath(from, to),
          Paint()
            ..color = color.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round,
        );
      }
      walked += metric.length;
      if (walked >= distance) break;
    }

    canvas.drawCircle(
      head,
      9,
      Paint()..color = color.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      head,
      3.2,
      Paint()..color = color.withValues(alpha: 0.85),
    );
  }

  /// The point on [metrics] (taken as one continuous line) at [distance].
  static Offset? _pointAt(List<PathMetric> metrics, double distance) {
    double walked = 0;
    for (final metric in metrics) {
      if (distance <= walked + metric.length) {
        return metric.getTangentForOffset(distance - walked)?.position;
      }
      walked += metric.length;
    }
    final last = metrics.last;
    return last.getTangentForOffset(last.length)?.position;
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

/// A kidney (bean) outline of width [w], with its hilum - the inward notch -
/// facing right. [origin] is the shape's top-left corner; height is 1.42w.
Path _kidneyPath(Offset origin, double w) {
  final h = w * 1.42;
  final x = origin.dx;
  final y = origin.dy;

  return Path()
    ..moveTo(x + w * 0.62, y + h * 0.04)
    ..cubicTo(x + w * 0.18, y - h * 0.04, x - w * 0.06, y + h * 0.30,
        x + w * 0.04, y + h * 0.58)
    ..cubicTo(x + w * 0.12, y + h * 0.86, x + w * 0.42, y + h * 1.04,
        x + w * 0.72, y + h * 0.94)
    ..cubicTo(x + w * 0.98, y + h * 0.86, x + w * 1.02, y + h * 0.66,
        x + w * 0.84, y + h * 0.56)
    // the hilum: a soft inward curve on the right-hand side
    ..cubicTo(x + w * 0.70, y + h * 0.50, x + w * 0.70, y + h * 0.40,
        x + w * 0.84, y + h * 0.34)
    ..cubicTo(x + w * 1.02, y + h * 0.24, x + w * 0.98, y + h * 0.08,
        x + w * 0.62, y + h * 0.04)
    ..close();
}

/// [path] reflected about the vertical line x = [cx].
Path _mirroredPath(Path path, double cx) {
  return path.transform(
    (Matrix4.identity()
          ..translateByDouble(cx * 2, 0, 0, 1)
          ..scaleByDouble(-1, 1, 1, 1))
        .storage,
  );
}

/// An illustrative dialysis circuit for use on the dark brand gradient: a
/// pair of kidneys joined by a loop to a filter cartridge, with small dots
/// travelling the loop - leaving coral, returning turquoise after the
/// filter - as a gentle picture of treatment that keeps going. Decorative
/// and schematic, not a medical diagram. With reduced motion the dots
/// stand still.
class CareCircuit extends StatefulWidget {
  const CareCircuit({super.key});

  @override
  State<CareCircuit> createState() => _CareCircuitState();
}

class _CareCircuitState extends State<CareCircuit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
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
      child: reduced
          ? CustomPaint(
              painter: _CareCircuitPainter(progress: 0.12),
              size: Size.infinite,
            )
          : AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _CareCircuitPainter(progress: _controller.value),
                size: Size.infinite,
              ),
            ),
    );
  }
}

class _CareCircuitPainter extends CustomPainter {
  _CareCircuitPainter({required this.progress});

  final double progress;

  static const Color _turquoise = Color(0xFF7FD0D9);
  static const int _dots = 7;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final w = size.width;
    final h = size.height;

    // ---- the kidney pair, left
    final kw = math.min(h * 0.40, w * 0.14);
    final kh = kw * 1.42;
    final pairCx = w * 0.20;
    final top = (h - kh) / 2;
    final left = _kidneyPath(Offset(pairCx - kw * 1.08, top), kw);
    final right = _mirroredPath(
      _kidneyPath(Offset(pairCx - kw * 1.08, top), kw),
      pairCx,
    );
    canvas.drawPath(left, Paint()..color = _turquoise.withValues(alpha: 0.85));
    canvas.drawPath(right, Paint()..color = Brand.teal.withValues(alpha: 0.95));
    for (final k in [left, right]) {
      canvas.drawPath(
        k,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    // A small heart between them, echoing the CureNurture care glyph.
    final hx = pairCx;
    final hy = h * 0.5;
    final r = kw * 0.16;
    final heart = Path()
      ..moveTo(hx, hy + r * 0.95)
      ..cubicTo(hx - r * 1.5, hy + r * 0.05, hx - r * 0.72, hy - r * 1.05,
          hx, hy - r * 0.28)
      ..cubicTo(hx + r * 0.72, hy - r * 1.05, hx + r * 1.5, hy + r * 0.05,
          hx, hy + r * 0.95)
      ..close();
    canvas.drawPath(heart, Paint()..color = Brand.coralBright);

    // ---- the filter cartridge, right
    final fx = w * 0.84;
    final fw = math.max(18.0, w * 0.065);
    final fTop = h * 0.16;
    final fBottom = h * 0.84;
    final cartridge = RRect.fromRectAndRadius(
      Rect.fromLTRB(fx - fw / 2, fTop, fx + fw / 2, fBottom),
      Radius.circular(fw / 2),
    );
    canvas.drawRRect(
      cartridge,
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
    canvas.drawRRect(
      cartridge,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    for (double y = fTop + fw * 0.7; y < fBottom - fw * 0.6; y += 7) {
      canvas.drawLine(
        Offset(fx - fw * 0.28, y),
        Offset(fx + fw * 0.28, y),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.16)
          ..strokeWidth = 1,
      );
    }

    // ---- the loop: out over the top, through the filter, back underneath
    final start = Offset(pairCx + kw * 1.0, h * 0.36);
    final end = Offset(pairCx + kw * 1.0, h * 0.64);
    final loop = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(w * 0.46, h * 0.02, w * 0.70, h * 0.02, fx, fTop)
      ..lineTo(fx, fBottom)
      ..cubicTo(w * 0.70, h * 0.98, w * 0.46, h * 0.98, end.dx, end.dy);

    canvas.drawPath(
      loop,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    final metrics = loop.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final length = metric.length;

    // Where the filter section of the loop begins and ends, so dots past
    // it can be drawn "cleaned" (turquoise).
    final filterFrom = _lengthTo(metric, fTop, fx);

    for (int i = 0; i < _dots; i++) {
      final t = (progress + i / _dots) % 1.0;
      final d = t * length;
      final p = metric.getTangentForOffset(d)?.position;
      if (p == null) continue;
      final cleaned = d > filterFrom + (fBottom - fTop) * 0.5;
      final colour = cleaned ? _turquoise : Brand.coralBright;
      canvas.drawCircle(p, 7, Paint()..color = colour.withValues(alpha: 0.18));
      canvas.drawCircle(p, 3, Paint()..color = colour.withValues(alpha: 0.95));
    }
  }

  /// Distance along [metric] at which it first reaches the point (x, y)
  /// closely enough - here, the top of the filter cartridge.
  static double _lengthTo(PathMetric metric, double y, double x) {
    for (double d = 0; d < metric.length; d += 2) {
      final p = metric.getTangentForOffset(d)?.position;
      if (p != null && (p.dx - x).abs() < 2 && (p.dy - y).abs() < 2) return d;
    }
    return metric.length / 2;
  }

  @override
  bool shouldRepaint(covariant _CareCircuitPainter oldDelegate) =>
      oldDelegate.progress != progress;
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
