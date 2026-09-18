import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// The donation journey, shown as three steps.
///
/// These describe the flow the site actually performs: pick how you want to
/// give, fill in the donation details, and the donation is written to
/// CureNurture's records. It is a progress *indicator* only - it reports
/// where the visitor is, and changes nothing about how donating works.
class DonationSteps extends StatelessWidget {
  const DonationSteps({
    super.key,
    required this.current,
    this.light = false,
  });

  /// Zero-based index of the step the visitor is on.
  final int current;

  /// Renders for use on the deep gradient rather than a light surface.
  final bool light;

  static const List<({String title, String subtitle, IconData icon})> _steps = [
    (
      title: 'Choose how to give',
      subtitle: 'Anonymously, or with your donor account',
      icon: Icons.how_to_reg_rounded,
    ),
    (
      title: 'Enter your details',
      subtitle: 'Amount, destination and payment channel',
      icon: Icons.edit_note_rounded,
    ),
    (
      title: 'Donation recorded',
      subtitle: 'Saved to CureNurture’s verified records',
      icon: Icons.verified_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;

        if (stacked) {
          return Column(
            children: [
              for (int i = 0; i < _steps.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 21),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 2,
                        height: 16,
                        color: _connectorColor(i),
                      ),
                    ),
                  ),
                _step(i, stacked: true),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < _steps.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 21),
                    child: Container(height: 2, color: _connectorColor(i)),
                  ),
                ),
              Flexible(
                flex: 4,
                child: _step(i, stacked: false),
              ),
            ],
          ],
        );
      },
    );
  }

  Color _connectorColor(int index) {
    final done = index <= current;

    if (light) {
      return Colors.white.withValues(alpha: done ? 0.55 : 0.20);
    }

    return done ? Brand.brand.withValues(alpha: 0.45) : Brand.border;
  }

  Widget _step(int index, {required bool stacked}) {
    final isDone = index < current;
    final isCurrent = index == current;
    final isUpcoming = index > current;

    final Color circleFill;
    final Color circleContent;
    final Color titleColor;
    final Color subtitleColor;

    if (light) {
      circleFill = isUpcoming
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.white;
      circleContent = isUpcoming ? Colors.white : Brand.brandDeep;
      titleColor = Colors.white.withValues(alpha: isUpcoming ? 0.66 : 1);
      subtitleColor = Colors.white.withValues(alpha: isUpcoming ? 0.45 : 0.72);
    } else {
      circleFill = isUpcoming
          ? Brand.white
          : (isCurrent ? Brand.brand : Brand.mint);
      circleContent = isUpcoming ? Brand.textMuted : Colors.white;
      titleColor = isUpcoming ? Brand.textMuted : Brand.textStrong;
      subtitleColor = Brand.textMuted;
    }

    final circle = Container(
      height: 42,
      width: 42,
      decoration: BoxDecoration(
        color: circleFill,
        shape: BoxShape.circle,
        border: Border.all(
          color: light
              ? Colors.white.withValues(alpha: isUpcoming ? 0.3 : 0)
              : (isUpcoming ? Brand.borderSoft : Colors.transparent),
          width: 1.5,
        ),
        boxShadow: isCurrent && !light
            ? [
                BoxShadow(
                  color: Brand.brand.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Center(
        child: isDone
            ? Icon(Icons.check_rounded, size: 20, color: circleContent)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  color: circleContent,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
      ),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _steps[index].title,
          style: TextStyle(
            color: titleColor,
            fontSize: 14.5,
            height: 1.3,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _steps[index].subtitle,
          style: TextStyle(
            color: subtitleColor,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );

    // Screen readers get the position spoken rather than inferred from the
    // numbered circle.
    return Semantics(
      label:
          'Step ${index + 1} of ${_steps.length}: ${_steps[index].title}'
          '${isCurrent ? ', current step' : ''}'
          '${isDone ? ', completed' : ''}',
      excludeSemantics: true,
      child: stacked
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                circle,
                const SizedBox(width: 14),
                Expanded(child: text),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                circle,
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: text,
                ),
              ],
            ),
    );
  }
}
