import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/center_status.dart';

/// Colours and icon for an Open/Closed availability, shared by every centre
/// badge in the app so the two states always look the same.
(Color foreground, Color background, IconData icon) centerAvailabilityStyle(
  CenterAvailability availability,
) {
  return switch (availability) {
    CenterAvailability.open => (
      AppTheme.accentGreen,
      AppTheme.accentGreenSoft,
      Icons.check_circle_rounded,
    ),
    CenterAvailability.closed => (
      AppTheme.textMuted,
      const Color(0xFFF1F3F5),
      Icons.schedule_rounded,
    ),
  };
}

/// Colours and icon for an Active/Inactive record status.
(Color foreground, Color background, IconData icon) centerRecordStatusStyle(
  CenterRecordStatus status,
) {
  return switch (status) {
    CenterRecordStatus.active => (
      AppTheme.blue1,
      AppTheme.accentBlueSoft,
      Icons.verified_rounded,
    ),
    CenterRecordStatus.inactive => (
      AppTheme.danger,
      AppTheme.dangerSoft,
      Icons.block_rounded,
    ),
  };
}

class CenterAvailabilityBadge extends StatelessWidget {
  const CenterAvailabilityBadge({super.key, required this.availability});

  final CenterAvailability availability;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, icon) = centerAvailabilityStyle(
      availability,
    );
    return _Badge(
      label: availability.label,
      icon: icon,
      foreground: foreground,
      background: background,
      tooltip: 'Availability, from today\'s operating hours',
    );
  }
}

class CenterRecordStatusBadge extends StatelessWidget {
  const CenterRecordStatusBadge({super.key, required this.status});

  final CenterRecordStatus status;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, icon) = centerRecordStatusStyle(status);
    return _Badge(
      label: status.label,
      icon: icon,
      foreground: foreground,
      background: background,
      tooltip: 'Record status',
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.tooltip,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                height: 1.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
