import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The bar across the top of every Admin page.
///
///   Hello, Maria Santos                            [ Center Profile ]
///
/// The head nurse's name lives here and nowhere else in the shell. It
/// used to sit under the CureNurture wordmark in the sidebar, which put
/// an account detail inside the product's branding and repeated it on
/// every page; the sidebar now carries the brand alone.
///
/// Presentation only. The name is supplied by the page (which already
/// loads the admin profile for other reasons) and [onOpenCenterProfile]
/// is the page's own navigation.
class AdminHeader extends StatelessWidget {
  /// Null while the profile is still loading -- the greeting falls back
  /// to a neutral form rather than flashing a placeholder name.
  final String? adminName;

  /// Shown as quiet context beside the greeting when known.
  final String? centerName;

  final VoidCallback onOpenCenterProfile;

  /// True on the Center Profile page itself, where the button becomes a
  /// non-interactive marker instead of a link back to the page you are
  /// already on.
  final bool centerProfileActive;

  const AdminHeader({
    super.key,
    required this.onOpenCenterProfile,
    this.adminName,
    this.centerName,
    this.centerProfileActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final name = adminName?.trim();
    final greeting = name == null || name.isEmpty ? 'Hello' : 'Hello, $name';

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: AppTheme.motion(context, AppTheme.normal),
                  child: Text(
                    greeting,
                    key: ValueKey(greeting),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.blue3,
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (centerName != null && centerName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    centerName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: 38,
            child: centerProfileActive
                ? const _CurrentPageMarker()
                : OutlinedButton.icon(
                    onPressed: onOpenCenterProfile,
                    icon: const Icon(Icons.apartment_rounded, size: 17),
                    label: const Text('Center Profile'),
                    style: AppTheme.secondaryButton(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The Center Profile chip while that page is open: same footprint, no
/// action, so the header does not shift when navigating to it.
class _CurrentPageMarker extends StatelessWidget {
  const _CurrentPageMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.accentBlueSoft,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.borderStrong),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.apartment_rounded, size: 17, color: AppTheme.blue1),
          SizedBox(width: 8),
          Text(
            'Center Profile',
            style: TextStyle(
              color: AppTheme.blue1,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
