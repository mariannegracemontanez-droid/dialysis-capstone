import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A row of equal-width summary cards that reflows as the window narrows:
/// all in one row on a comfortable width, two-up when it tightens, then
/// stacked.
///
/// The cards in a row are given equal heights through [IntrinsicHeight].
/// That wrapper is load-bearing, not cosmetic: these rows live inside a
/// vertically unbounded scroll view, and `CrossAxisAlignment.stretch` on
/// its own would hand each card a *tight infinite* height, which fails to
/// lay out and leaves the whole page blank. [IntrinsicHeight] gives the
/// row a real height first, so stretching is safe.
class AdminCardRow extends StatelessWidget {
  /// The cards, in order. Each is laid out with equal width.
  final List<Widget> cards;

  /// The width available to the row - normally a `LayoutBuilder`'s
  /// `constraints.maxWidth`.
  final double width;

  /// Gap between cards, used both horizontally and vertically.
  final double spacing;

  /// At or below this width every card is stacked.
  final double stackBelow;

  /// Below this width the cards pair up two-to-a-row.
  final double pairBelow;

  const AdminCardRow({
    super.key,
    required this.cards,
    required this.width,
    this.spacing = 16,
    this.stackBelow = 560,
    this.pairBelow = AppTheme.cardRowBreakpoint,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    if (cards.length == 1) return cards.single;

    if (width < stackBelow) return _stacked(cards);

    if (width < pairBelow) {
      final rows = <Widget>[];

      for (var i = 0; i < cards.length; i += 2) {
        // A trailing odd card takes the full width rather than sitting
        // half-width next to a gap.
        rows.add(
          i + 1 < cards.length ? _row([cards[i], cards[i + 1]]) : cards[i],
        );
      }

      return _stacked(rows);
    }

    return _row(cards);
  }

  Widget _stacked(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          children[i],
        ],
      ],
    );
  }

  Widget _row(List<Widget> children) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}
