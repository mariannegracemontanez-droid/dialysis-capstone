@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:donation_app/theme/brand.dart';
import 'package:donation_app/widgets/decor.dart';
import 'package:donation_app/widgets/donation_steps.dart';
import 'package:donation_app/widgets/ui.dart';

/// Renders the site's presentation components to golden images so the
/// design can be reviewed as a picture rather than as code.
///
/// Not a correctness check - run it with `--update-goldens` to regenerate
/// `test/goldens/*.png`. It is tagged `preview` so a normal `flutter test`
/// run skips it.
Future<void> _loadFonts() async {
  // Read straight off disk: these ship as font assets rather than as
  // entries in the `assets:` list, so rootBundle cannot see them in tests.
  Future<ByteData> read(String path) async {
    final bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer);
  }

  for (final family in ['Montserrat', 'Roboto']) {
    final loader = FontLoader(family)
      ..addFont(read('lib/assets/image/fonts/Montserrat-Regular.ttf'))
      ..addFont(read('lib/assets/image/fonts/Montserrat-Bold.ttf'));
    await loader.load();
  }

  // Without this every Icon renders as an empty box in the preview.
  final icons = File(
    '${_flutterRoot()}/bin/cache/artifacts/material_fonts/'
    'materialicons-regular.otf',
  );

  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(read(icons.path));
    await loader.load();
  }
}

/// Locates the Flutter SDK so the icon font can be pulled from its cache.
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env.replaceAll(r'\', '/');

  // `dart:io`'s resolvedExecutable points at <flutter>/bin/cache/dart-sdk/bin.
  final exe = Platform.resolvedExecutable.replaceAll(r'\', '/');
  final marker = '/bin/cache/dart-sdk/';
  final index = exe.indexOf(marker);
  return index == -1 ? '' : exe.substring(0, index);
}

/// Reveals need a frame to register as visible and then the length of their
/// curve to finish; the decorative loops never settle, so step manually.
Future<void> _settleReveals(WidgetTester tester) async {
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(_loadFonts);

  Widget sheet({required double width, required bool mobile}) {
    return MediaQuery(
      data: MediaQueryData(size: Size(width, 4000)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Brand.brand,
              primary: Brand.brand,
            ),
          ),
          home: Scaffold(
            backgroundColor: Brand.canvas,
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ------------------------------------------- hero band
                  Container(
                    decoration: const BoxDecoration(
                      gradient: Brand.deepGradient,
                    ),
                    child: Stack(
                      children: [
                        const Positioned.fill(child: FlowBackdrop()),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: mobile ? 44 : 72,
                          ),
                          child: ContentColumn(
                            child: mobile
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _heroText(mobile: true),
                                      const SizedBox(height: 32),
                                      _heroCard(),
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(flex: 7, child: _heroText()),
                                      const SizedBox(width: 48),
                                      Expanded(flex: 5, child: _heroCard()),
                                    ],
                                  ),
                          ),
                        ),
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: PulseLine(height: 38),
                        ),
                      ],
                    ),
                  ),

                  // ------------------------------------------ stats band
                  Transform.translate(
                    offset: const Offset(0, -30),
                    child: ContentColumn(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          color: Brand.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Brand.border),
                          boxShadow: Brand.shadowCard,
                        ),
                        child: ResponsiveRow(
                          breakpoint: 760,
                          gap: 24,
                          children: [
                            _stat(
                              Icons.verified_rounded,
                              Brand.mint,
                              Brand.mintSoft,
                              '128',
                              'Verified donations recorded',
                              mobile,
                            ),
                            _stat(
                              Icons.favorite_rounded,
                              Brand.coral,
                              Brand.coralSoft,
                              '₱486,200',
                              'Total contributed by donors',
                              mobile,
                            ),
                            _stat(
                              Icons.local_hospital_rounded,
                              Brand.brand,
                              Brand.sky,
                              '12',
                              'Dialysis centres you can support',
                              mobile,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ------------------------------------------ card grid
                  Container(
                    color: Brand.canvas,
                    padding: EdgeInsets.symmetric(vertical: mobile ? 44 : 64),
                    child: ContentColumn(
                      child: Column(
                        children: [
                          const SectionHeading(
                            eyebrow: 'How your donation helps',
                            title:
                                'Four ways your gift supports dialysis care.',
                            subtitle:
                                'These are the areas CureNurture directs '
                                'donor support toward.',
                          ),
                          const SizedBox(height: 40),
                          const ResponsiveRow(
                            breakpoint: 900,
                            gap: 18,
                            stagger: true,
                            equalHeight: true,
                            children: [
                              InfoCard(
                                icon: Icons.medical_services_rounded,
                                title: 'Treatment Support',
                                text:
                                    'Helping dialysis centres keep treatment '
                                    'available for the patients who rely on them.',
                                accent: Brand.teal,
                                accentSoft: Brand.tealSoft,
                              ),
                              InfoCard(
                                icon: Icons.favorite_rounded,
                                title: 'Patient Assistance',
                                text:
                                    'Easing the treatment-related needs that '
                                    'surround care, from getting to a centre '
                                    'to what follows.',
                                accent: Brand.coral,
                                accentSoft: Brand.coralSoft,
                                filled: true,
                              ),
                              InfoCard(
                                icon: Icons.local_hospital_rounded,
                                title: 'Dialysis Centre Support',
                                text:
                                    'Strengthening the centres themselves, so '
                                    'access to dialysis care holds steady.',
                                accent: Brand.brand,
                                accentSoft: Brand.sky,
                              ),
                              InfoCard(
                                icon: Icons.groups_rounded,
                                title: 'Community Care',
                                text:
                                    'Standing alongside patients and their '
                                    'families, so no one faces long-term '
                                    'treatment feeling alone.',
                                accent: Brand.lavender,
                                accentSoft: Brand.lavenderSoft,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ------------------------------------ step indicators
                  Container(
                    color: Brand.white,
                    padding: EdgeInsets.symmetric(vertical: mobile ? 36 : 52),
                    child: ContentColumn(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: Brand.card(radius: 22),
                            child: const DonationSteps(current: 1),
                          ),
                          const SizedBox(height: 26),
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: const BoxDecoration(
                              gradient: Brand.brandGradient,
                              borderRadius: BorderRadius.all(
                                Radius.circular(22),
                              ),
                            ),
                            child: const DonationSteps(
                              current: 1,
                              light: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ---------------------------------------- closing CTA
                  Container(
                    decoration: const BoxDecoration(
                      gradient: Brand.deepGradient,
                    ),
                    child: Stack(
                      children: [
                        const Positioned.fill(child: FlowBackdrop()),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: mobile ? 56 : 76,
                          ),
                          child: ContentColumn(
                            maxWidth: 820,
                            child: Column(
                              children: [
                                Container(
                                  height: 74,
                                  width: 74,
                                  decoration: BoxDecoration(
                                    gradient: Brand.coralGradient,
                                    borderRadius: BorderRadius.circular(26),
                                    boxShadow: Brand.shadowCoral,
                                  ),
                                  child: const Icon(
                                    Icons.volunteer_activism_rounded,
                                    color: Colors.white,
                                    size: 38,
                                  ),
                                ),
                                const SizedBox(height: 26),
                                Text(
                                  'Your support can help make dialysis care '
                                  'more accessible.',
                                  textAlign: TextAlign.center,
                                  style: Brand.display(
                                    mobile ? 29 : 42,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'Give once, give anonymously, or give to the '
                                  'centre closest to your heart.',
                                  textAlign: TextAlign.center,
                                  style: Brand.body(
                                    mobile ? 15 : 17,
                                    color: Colors.white.withValues(
                                      alpha: 0.84,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 30),
                                if (mobile)
                                  DonateButton(
                                    label: 'Donate Now',
                                    onPressed: () {},
                                    expand: true,
                                    large: true,
                                  )
                                else
                                  Wrap(
                                    spacing: 14,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      DonateButton(
                                        label: 'Donate Now',
                                        onPressed: () {},
                                        large: true,
                                      ),
                                      GhostButton(
                                        label: 'Learn More',
                                        icon: Icons.arrow_forward_rounded,
                                        light: true,
                                        onPressed: () {},
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('desktop design sheet', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 2560);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(sheet(width: 1280, mobile: false));
    await _settleReveals(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop.png'),
    );
  });

  testWidgets('mobile design sheet', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 3200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(sheet(width: 390, mobile: true));
    await _settleReveals(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/mobile.png'),
    );
  });
}

Widget _heroText({bool mobile = false}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Eyebrow('Compassion in action', light: true),
      const SizedBox(height: 24),
      Text(
        'Help keep hope flowing.',
        style: Brand.display(mobile ? 40 : 60, color: Colors.white),
      ),
      const SizedBox(height: 20),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Text(
          'Dialysis does not stop. For the people who depend on it, treatment '
          'is a part of every week — and so is the cost of getting there.',
          style: Brand.body(
            mobile ? 15.5 : 17.5,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
      ),
      const SizedBox(height: 32),
      if (mobile)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DonateButton(
              label: 'Donate Now',
              onPressed: () {},
              expand: true,
              large: true,
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Learn More',
              icon: Icons.arrow_forward_rounded,
              light: true,
              expand: true,
              onPressed: () {},
            ),
          ],
        )
      else
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            DonateButton(
              label: 'Donate Now',
              onPressed: () {},
              large: true,
            ),
            GhostButton(
              label: 'Learn More',
              icon: Icons.arrow_forward_rounded,
              light: true,
              onPressed: () {},
            ),
          ],
        ),
      const SizedBox(height: 30),
      const Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          TrustPill(
            icon: Icons.tune_rounded,
            text: 'You choose where it goes',
            light: true,
          ),
          TrustPill(
            icon: Icons.verified_rounded,
            text: 'Every gift is recorded',
            light: true,
          ),
          TrustPill(
            icon: Icons.visibility_off_rounded,
            text: 'Give anonymously if you prefer',
            light: true,
          ),
        ],
      ),
    ],
  );
}

Widget _heroCard() {
  return Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Brand.white,
      borderRadius: BorderRadius.circular(30),
      boxShadow: Brand.shadowLift,
    ),
    child: Column(
      children: [
        const CareGlyph(size: 92),
        const SizedBox(height: 20),
        Text(
          'Your donation becomes care.',
          textAlign: TextAlign.center,
          style: Brand.heading(24),
        ),
        const SizedBox(height: 12),
        Text(
          'Every contribution helps ease the weight of ongoing treatment, and '
          'tells a patient that someone they have never met decided to help.',
          textAlign: TextAlign.center,
          style: Brand.body(14.5),
        ),
        const SizedBox(height: 22),
        DonateButton(
          label: 'Donate Now',
          onPressed: () {},
          expand: true,
        ),
      ],
    ),
  );
}

Widget _stat(
  IconData icon,
  Color accent,
  Color accentSoft,
  String value,
  String label,
  bool mobile,
) {
  return Column(
    children: [
      Container(
        height: 50,
        width: 50,
        decoration: Brand.iconBox(accentSoft, radius: 16),
        child: Icon(icon, color: accent, size: 25),
      ),
      const SizedBox(height: 14),
      Text(value, style: Brand.display(mobile ? 30 : 36)),
      const SizedBox(height: 6),
      Text(
        label,
        textAlign: TextAlign.center,
        style: Brand.body(13.5, color: Brand.textMuted),
      ),
    ],
  );
}
