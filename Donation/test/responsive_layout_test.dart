import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:donation_app/theme/brand.dart';
import 'package:donation_app/widgets/decor.dart';
import 'package:donation_app/widgets/donation_steps.dart';
import 'package:donation_app/widgets/motion.dart';
import 'package:donation_app/widgets/ui.dart';

/// Layout checks for the donation site's presentation components.
///
/// A RenderFlex overflow is reported as a framework error rather than a
/// thrown exception at the call site, so each case pumps the widget and
/// then asserts that no error was recorded. These cover the pieces most
/// likely to break on a narrow phone: the step indicator, the card grids
/// and the buttons.
void main() {
  // Every width the site is expected to survive, from a small phone up to a
  // large desktop monitor.
  const widths = <double>[320, 360, 375, 414, 600, 768, 1024, 1280, 1600];

  Future<void> pumpAt(
    WidgetTester tester,
    double width,
    Widget child, {
    bool reduceMotion = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 2400),
          disableAnimations: reduceMotion,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Brand.canvas,
              // Scrolls so tall content is never itself an overflow.
              body: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );

    // Not pumpAndSettle: the decorative pulse and float animations repeat
    // forever and would never settle.
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('DonationSteps', () {
    for (final width in widths) {
      for (final step in [0, 1, 2]) {
        testWidgets('step $step lays out at ${width.toInt()}px', (
          tester,
        ) async {
          await pumpAt(tester, width, DonationSteps(current: step));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('light variant lays out on a narrow screen', (tester) async {
      await pumpAt(
        tester,
        360,
        Container(
          color: Brand.brandDeep,
          child: const DonationSteps(current: 1, light: true),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('announces position for assistive technology', (tester) async {
      await pumpAt(tester, 1024, const DonationSteps(current: 1));

      final semantics = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Step 2 of 3')),
      );

      expect(semantics.label, contains('Enter your details'));
      expect(semantics.label, contains('current step'));
    });
  });

  group('card grids', () {
    // Mirrors how the landing page configures its card grids, so the
    // infinite-height trap that `stretch` sets inside a scroll view stays
    // covered.
    Widget grid() => ContentColumn(
      child: ResponsiveRow(
        stagger: true,
        equalHeight: true,
        children: const [
          InfoCard(
            icon: Icons.medical_services_rounded,
            title: 'Treatment Support',
            text: 'Helping dialysis centres keep treatment available.',
            accent: Brand.teal,
            accentSoft: Brand.tealSoft,
          ),
          InfoCard(
            icon: Icons.favorite_rounded,
            title: 'Patient Assistance',
            text: 'Easing the treatment-related needs that surround care.',
            accent: Brand.coral,
            accentSoft: Brand.coralSoft,
            filled: true,
          ),
          InfoCard(
            icon: Icons.local_hospital_rounded,
            title: 'Dialysis Centre Support',
            text: 'Strengthening the centres themselves.',
            accent: Brand.brand,
            accentSoft: Brand.sky,
          ),
          InfoCard(
            icon: Icons.groups_rounded,
            title: 'Community Care',
            text: 'Standing alongside patients and their families.',
            accent: Brand.lavender,
            accentSoft: Brand.lavenderSoft,
          ),
        ],
      ),
    );

    for (final width in widths) {
      testWidgets('four cards lay out at ${width.toInt()}px', (tester) async {
        await pumpAt(tester, width, grid());
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('buttons', () {
    for (final width in widths) {
      testWidgets('donate and ghost buttons fit at ${width.toInt()}px', (
        tester,
      ) async {
        await pumpAt(
          tester,
          width,
          ContentColumn(
            child: Column(
              children: [
                DonateButton(label: 'Donate Now', onPressed: () {}, large: true),
                const SizedBox(height: 12),
                DonateButton(
                  label: 'Donate Now',
                  onPressed: () {},
                  expand: true,
                ),
                const SizedBox(height: 12),
                GhostButton(
                  label: 'Learn More',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('donate button reports a press', (tester) async {
      var pressed = 0;

      await pumpAt(
        tester,
        1024,
        Center(
          child: DonateButton(
            label: 'Donate Now',
            onPressed: () => pressed++,
          ),
        ),
      );

      await tester.tap(find.text('Donate Now'));
      await tester.pump();

      expect(pressed, 1);
    });
  });

  group('section heading and decoration', () {
    for (final width in widths) {
      testWidgets('heading and artwork render at ${width.toInt()}px', (
        tester,
      ) async {
        await pumpAt(
          tester,
          width,
          Column(
            children: [
              const ContentColumn(
                child: SectionHeading(
                  eyebrow: 'How your donation helps',
                  title: 'Four ways your gift supports dialysis care.',
                  subtitle:
                      'These are the areas CureNurture directs donor support '
                      'toward.',
                ),
              ),
              const SizedBox(height: 20),
              const CareGlyph(),
              const SizedBox(height: 20),
              const WaveDivider(color: Brand.white),
              const SizedBox(height: 20),
              SizedBox(
                height: 160,
                child: Stack(
                  children: const [
                    Positioned.fill(child: FlowBackdrop()),
                    Positioned.fill(child: DriftField()),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const PulseLine(color: Brand.teal),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  TrustPill(
                    icon: Icons.tune_rounded,
                    text: 'You choose where it goes',
                  ),
                  TrustPill(
                    icon: Icons.verified_rounded,
                    text: 'Every gift is recorded',
                  ),
                  TrustPill(
                    icon: Icons.visibility_off_rounded,
                    text: 'Give anonymously if you prefer',
                  ),
                ],
              ),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('reduced motion', () {
    testWidgets('CountUp shows the final figure immediately', (tester) async {
      await pumpAt(
        tester,
        1024,
        const Center(
          child: CountUp(
            value: 12345,
            prefix: '₱',
            style: TextStyle(fontSize: 20),
          ),
        ),
        reduceMotion: true,
      );

      // No animation to wait for - the real number is on screen at once.
      expect(find.text('₱12,345'), findsOneWidget);
    });

    testWidgets('Reveal renders its child without animating', (tester) async {
      await pumpAt(
        tester,
        1024,
        const Reveal(child: Text('Visible immediately')),
        reduceMotion: true,
      );

      expect(find.text('Visible immediately'), findsOneWidget);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('CountUp formats thousands separators', (tester) async {
      await pumpAt(
        tester,
        1024,
        const Center(
          child: CountUp(value: 1000000, style: TextStyle(fontSize: 20)),
        ),
        reduceMotion: true,
      );

      expect(find.text('1,000,000'), findsOneWidget);
    });
  });
}
