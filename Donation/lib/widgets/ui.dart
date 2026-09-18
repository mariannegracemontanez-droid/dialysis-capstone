import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'motion.dart';

/// Shared building blocks for the donation site's pages.
///
/// These wrap presentation only. A button here takes whatever `onPressed`
/// it is given and calls it - none of them know anything about donations,
/// accounts or navigation.

/// Constrains content to the site's reading column and applies the
/// responsive side gutter.
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.child,
    this.maxWidth = Brand.maxContent,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Brand.gutter(width)),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// The site's primary call to action.
///
/// Coral is used for nothing else on the page, so wherever this button
/// appears it is the most urgent element in view. It keeps a real
/// [ElevatedButton] underneath for focus handling, keyboard activation and
/// semantics; the wrapper only adds the hover lift and glow.
class DonateButton extends StatelessWidget {
  const DonateButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.volunteer_activism_rounded,
    this.expand = false,
    this.large = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  /// Fills the available width - used on phones, where a full-width target
  /// is easier to hit with a thumb.
  final bool expand;
  final bool large;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final height = large ? 60.0 : 54.0;

    return HoverLift(
      lift: 3,
      scale: 1.02,
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: expand ? double.infinity : null,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: hovered ? Brand.shadowLift : Brand.shadowCoral,
          ),
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: large ? 22 : 20),
              label: Text(label),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) return Brand.coral;
                  if (states.contains(WidgetState.hovered)) {
                    return Brand.coralBright;
                  }
                  return Brand.coral;
                }),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
                overlayColor: WidgetStatePropertyAll(
                  Colors.white.withValues(alpha: 0.12),
                ),
                elevation: const WidgetStatePropertyAll(0),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: large ? 34 : 26),
                ),
                textStyle: WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: large ? 17 : 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                shape: WidgetStateProperty.resolveWith((states) {
                  // A visible ring for keyboard users, who get no hover.
                  final focused = states.contains(WidgetState.focused);
                  return RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: focused
                        ? const BorderSide(color: Colors.white, width: 2.5)
                        : BorderSide.none,
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Secondary action. [light] switches it for use on the dark gradient.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.light = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool light;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final foreground = light ? Colors.white : Brand.brandDeep;

    final style = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(foreground),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return light
              ? Colors.white.withValues(alpha: 0.14)
              : Brand.sky;
        }
        return Colors.transparent;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        final focused = states.contains(WidgetState.focused);
        return BorderSide(
          color: light
              ? Colors.white.withValues(alpha: focused ? 1 : 0.55)
              : (focused ? Brand.brandDeep : Brand.brand.withValues(alpha: 0.45)),
          width: focused ? 2.2 : 1.4,
        );
      }),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: Brand.displayFont,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );

    return SizedBox(
      height: 54,
      width: expand ? double.infinity : null,
      child: icon == null
          ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 19),
              label: Text(label),
              style: style,
            ),
    );
  }
}

/// Small uppercase category label that sits above a section title.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.light = false, this.color});

  final String text;
  final bool light;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = light ? Colors.white : (color ?? Brand.teal);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: light ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: tone.withValues(alpha: light ? 0.28 : 0.20)),
      ),
      child: Text(text.toUpperCase(), style: Brand.eyebrow(color: tone)),
    );
  }
}

/// Centred eyebrow + title + supporting line, the standard opening of a
/// section.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.light = false,
    this.align = TextAlign.center,
    this.eyebrowColor,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final bool light;
  final TextAlign align;
  final Color? eyebrowColor;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mobile = Brand.isMobile(width);
    final centred = align == TextAlign.center;

    return Reveal(
      child: Column(
        crossAxisAlignment: centred
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Eyebrow(eyebrow, light: light, color: eyebrowColor),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: align,
            style: Brand.display(
              mobile ? 28 : 38,
              color: light ? Colors.white : Brand.textStrong,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                subtitle!,
                textAlign: align,
                style: Brand.body(
                  mobile ? 15 : 16.5,
                  color: light
                      ? Colors.white.withValues(alpha: 0.82)
                      : Brand.textBody,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A rounded pill carrying a short reassurance, e.g. "Verified records".
class TrustPill extends StatelessWidget {
  const TrustPill({
    super.key,
    required this.icon,
    required this.text,
    this.light = false,
    this.color,
  });

  final IconData icon;
  final String text;
  final bool light;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = light ? Colors.white : (color ?? Brand.brand);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: light ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: tone.withValues(alpha: light ? 0.24 : 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: light ? Colors.white.withValues(alpha: 0.92) : tone,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White card with an accent-tinted icon tile. Used for the impact and
/// commitment grids.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.accent,
    required this.accentSoft,
    this.filled = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color accent;
  final Color accentSoft;

  /// Renders the card in its tinted variant, so a row of cards can mix
  /// weights instead of reading as four identical boxes.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      lift: 7,
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: const EdgeInsets.all(26),
          decoration: filled
              ? BoxDecoration(
                  color: accentSoft,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: accent.withValues(alpha: hovered ? 0.40 : 0.16),
                  ),
                )
              : BoxDecoration(
                  color: Brand.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: hovered
                        ? accent.withValues(alpha: 0.40)
                        : Brand.border,
                  ),
                  boxShadow: hovered ? Brand.shadowCard : Brand.shadowSoft,
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: Brand.iconBox(
                  filled ? Colors.white.withValues(alpha: 0.75) : accentSoft,
                  radius: 18,
                ),
                child: Icon(icon, color: accent, size: 27),
              ),
              const SizedBox(height: 20),
              Text(title, style: Brand.heading(19)),
              const SizedBox(height: 10),
              Text(text, style: Brand.body(14.5)),
            ],
          ),
        );
      },
    );
  }
}

/// Lays widgets out as a row on wide screens and a stacked column on
/// narrow ones, with consistent gaps either way.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.gap = 20,
    this.breakpoint = 900,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.stagger = false,
    this.equalHeight = false,
  });

  final List<Widget> children;
  final double gap;
  final double breakpoint;
  final CrossAxisAlignment crossAxisAlignment;

  /// Reveals the children one after another as the row scrolls into view,
  /// so a grid of cards arrives as a sequence rather than all at once.
  final bool stagger;

  /// Makes every child in the row as tall as the tallest, so a row of cards
  /// shares one baseline instead of ending at ragged heights.
  final bool equalHeight;

  Widget _item(int index) {
    final child = children[index];
    if (!stagger) return child;

    return Reveal(delayMs: index * 90, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                _item(i),
              ],
            ],
          );
        }

        final row = Row(
          crossAxisAlignment: equalHeight
              ? CrossAxisAlignment.stretch
              : crossAxisAlignment,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: _item(i)),
            ],
          ],
        );

        // `stretch` alone would hand the children an infinite height inside
        // a scroll view. IntrinsicHeight measures the tallest card first and
        // gives the row that bounded height to stretch into.
        return equalHeight ? IntrinsicHeight(child: row) : row;
      },
    );
  }
}
