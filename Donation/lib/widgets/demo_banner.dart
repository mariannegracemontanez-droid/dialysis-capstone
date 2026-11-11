import 'package:flutter/material.dart';

import '../config/payment_config.dart';
import '../theme/brand.dart';

/// Small sandbox notice shown above the donation form while the server is
/// in sandbox mode. Clear but unobtrusive: one slim line, no loud colours,
/// and it never suggests a real GCash or PayMongo payment.
class DemoModeBanner extends StatelessWidget {
  const DemoModeBanner({super.key, this.detail});

  /// Optional extra detail, e.g. which sandbox provider is active.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final text = detail == null ? kDemoBannerText : '$kDemoBannerText  ·  $detail';
    return Semantics(
      container: true,
      label: text,
      child: Container(
        width: double.infinity,
        color: Brand.tealSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline_rounded, size: 15, color: Brand.brandDeep),
            const SizedBox(width: 6),
            Flexible(
              child: ExcludeSemantics(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: Brand.body(12.5, color: Brand.brandDeep),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
