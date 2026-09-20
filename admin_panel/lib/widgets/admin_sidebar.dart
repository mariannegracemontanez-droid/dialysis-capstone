import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Which Admin destination the sidebar is currently highlighting.
///
/// The indices match the ones the pages already used (0 = Dashboard,
/// 1 = Patients), so nothing about navigation changes.
class AdminNav {
  const AdminNav._();

  static const int dashboard = 0;
  static const int patients = 1;

  /// The Center Profile page. It has no sidebar row of its own -- it is
  /// reached from the Admin header -- so passing this as `selectedIndex`
  /// simply leaves every row unhighlighted, which is exactly right while
  /// the admin is somewhere the sidebar does not list.
  static const int centerProfile = 2;
}

/// The shared CureNurture Admin sidebar.
///
/// Presentation only: it renders the brand block, the two navigation
/// destinations, an optional center summary and the log out button. Every
/// action is a callback the calling page supplies, so the Dashboard and
/// the Patients page each keep their own existing navigation and logout
/// behaviour unchanged - this widget only gives them one appearance.
///
/// The brand block is the product name alone. The head nurse's name used
/// to sit underneath it; it now belongs to [AdminHeader] at the top of
/// the page, so an account detail is not rendered inside the product's
/// branding and is not repeated in two places at once.
class AdminSidebar extends StatelessWidget {
  /// Currently active destination, one of the [AdminNav] constants.
  final int selectedIndex;

  /// Called with the tapped destination index. The page decides what
  /// navigating there means.
  final ValueChanged<int> onSelect;

  /// Existing logout action of the calling page.
  final VoidCallback onLogout;

  /// Center summary shown above the log out button. Omitted when the
  /// clinic hasn't resolved yet.
  final String? centerName;
  final int? machineCount;

  const AdminSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
    this.centerName,
    this.machineCount,
  });

  @override
  Widget build(BuildContext context) {
    final width = AppTheme.sidebarWidth(MediaQuery.of(context).size.width);

    return AnimatedContainer(
      duration: AppTheme.motion(context, AppTheme.normal),
      curve: AppTheme.ease,
      width: width,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 26),
          _brand(),
          const SizedBox(height: 22),
          const Divider(height: 1, thickness: 1, color: AppTheme.border),
          const SizedBox(height: 14),

          AdminSidebarItem(
            label: 'Dashboard',
            icon: Icons.dashboard_rounded,
            selected: selectedIndex == AdminNav.dashboard,
            onTap: () => onSelect(AdminNav.dashboard),
          ),
          AdminSidebarItem(
            label: 'Patients',
            icon: Icons.people_alt_rounded,
            selected: selectedIndex == AdminNav.patients,
            onTap: () => onSelect(AdminNav.patients),
          ),

          const Spacer(),

          if (centerName != null) _centerCard(),
          if (centerName != null) const SizedBox(height: 14),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded, size: 17),
                label: const Text('Log out'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppTheme.surface,
                  foregroundColor: AppTheme.blue3,
                  side: const BorderSide(color: AppTheme.borderStrong),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            '© 2026 CureNurture',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _brand() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.border),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/CureNurture_CircleLogo.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    Icons.local_hospital_rounded,
                    color: AppTheme.blue1,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CureNurture',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.blue3,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 3),
                // The portal, not the person. The head nurse's name is
                // shown once, in the Admin header.
                Text(
                  'Center Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.surfaceTint,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.health_and_safety_rounded,
                  color: AppTheme.blue1,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    centerName!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (machineCount != null) ...[
              const SizedBox(height: 7),
              Text(
                '$machineCount dialysis machines',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One navigation row. Inactive rows stay quiet; the active one takes a
/// CureNurture blue block with white icon and label.
class AdminSidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const AdminSidebarItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppTheme.white : AppTheme.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: AnimatedContainer(
        duration: AppTheme.motion(context, AppTheme.fast),
        curve: AppTheme.ease,
        decoration: BoxDecoration(
          color: selected ? AppTheme.blue1 : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            onTap: onTap,
            hoverColor: selected ? Colors.transparent : AppTheme.accentSoft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? AppTheme.white : AppTheme.iconMuted,
                    size: 19,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13.5,
                        height: 1.25,
                        letterSpacing: 0.1,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
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
}
