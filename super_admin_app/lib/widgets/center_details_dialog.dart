import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/center_model.dart';
import '../theme/app_theme.dart';
import '../utils/center_requirements.dart';
import '../utils/operating_hours.dart';
import '../utils/ph_contact_number.dart';
import 'center_status_badges.dart';

/// Shows [center]'s saved details in a modal: availability and record
/// status, capacity breakdown, hours, shifts, contact number, created date,
/// requirements and address. Only saved values are shown; anything missing
/// reads "Not set".
///
/// [reservedPatients] and [estimatedAvailable] are the Centres page's live
/// capacity estimate for this centre (reserved/accepted patients, and total
/// capacity minus reserved). Null means the count could not be loaded, shown
/// as "Unavailable" -- never as 0.
Future<void> showCenterDetailsDialog(
  BuildContext context,
  CenterModel center, {
  int? reservedPatients,
  int? estimatedAvailable,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => CenterDetailsDialog(
      center: center,
      reservedPatients: reservedPatients,
      estimatedAvailable: estimatedAvailable,
    ),
  );
}

class CenterDetailsDialog extends StatelessWidget {
  const CenterDetailsDialog({
    super.key,
    required this.center,
    this.reservedPatients,
    this.estimatedAvailable,
  });

  final CenterModel center;
  final int? reservedPatients;
  final int? estimatedAvailable;

  static const String notSet = 'Not set';
  static const String unavailable = 'Unavailable';

  static final DateFormat _createdFormat = DateFormat('MMM d, yyyy');

  String get _hoursText {
    final range = parseOperatingHoursRange(center.operatingHours);
    if (range != null) {
      return formatOperatingHours(range.open, range.close);
    }
    final raw = center.operatingHours.trim();
    return raw.isEmpty ? notSet : raw;
  }

  String get _contactText {
    final formatted = formatPhContactForDisplay(center.contactNumber);
    return formatted.isEmpty ? notSet : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final requirements = parseStoredRequirements(center.requirements);
    final address = [
      center.address.trim(),
      center.city.trim(),
    ].where((part) => part.isNotEmpty).join(', ');
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 600;

    // Machines × this centre's saved shifts -- the same formula the Centres
    // table uses for its Available (Est.) column.
    final totalCapacity = center.totalCapacity;
    final reserved = reservedPatients;
    final estimate = estimatedAvailable;
    final created = center.savedCreatedAt;

    // Capacity breakdown: machines x shifts = total capacity; reserved
    // patients are subtracted for the estimate. The saved available slots
    // are shown separately, as stored.
    final tiles = <Widget>[
      _InfoTile(
        icon: Icons.precision_manufacturing_rounded,
        label: 'Machines',
        value: center.machines.toString(),
      ),
      _InfoTile(
        icon: Icons.schedule_rounded,
        label: 'Shifts',
        value: center.shifts.toString(),
      ),
      _InfoTile(
        icon: Icons.dashboard_customize_rounded,
        label: 'Total Capacity',
        value: totalCapacity.toString(),
      ),
      _InfoTile(
        icon: Icons.groups_rounded,
        label: 'Reserved',
        value: reserved == null ? unavailable : reserved.toString(),
      ),
      _InfoTile(
        icon: Icons.calculate_outlined,
        label: 'Available (Est.)',
        value: estimate == null
            ? unavailable
            : reserved != null && reserved > totalCapacity
            ? '$estimate · capacity exceeded'
            : estimate.toString(),
      ),
      _InfoTile(
        icon: Icons.airline_seat_flat_rounded,
        label: 'Available Slots (saved)',
        value: center.availableSlots.toString(),
      ),
      _InfoTile(
        icon: Icons.access_time_rounded,
        label: 'Operating Hours',
        value: _hoursText,
      ),
      _InfoTile(
        icon: Icons.call_rounded,
        label: 'Contact Number',
        value: _contactText,
      ),
      _InfoTile(
        icon: Icons.event_rounded,
        label: 'Created',
        value: created == null
            ? notSet
            : _createdFormat.format(created.toLocal()),
      ),
    ];

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 12 : 32,
        vertical: isNarrow ? 16 : 28,
      ),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: EdgeInsets.all(isNarrow ? 16 : 24),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rXl),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.shadowMd,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isNarrow) ...[
                      Container(
                        width: 52,
                        height: 52,
                        decoration: AppTheme.iconBox(AppTheme.accentBlueSoft),
                        child: const Icon(
                          Icons.local_hospital_rounded,
                          color: AppTheme.blue1,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            center.name,
                            style: const TextStyle(
                              color: AppTheme.blue3,
                              fontSize: 21,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            address.isEmpty ? 'Address not set' : address,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              CenterAvailabilityBadge(
                                availability: center.availability(),
                              ),
                              CenterRecordStatusBadge(
                                status: center.recordStatus,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 620
                        ? 3
                        : constraints.maxWidth >= 380
                        ? 2
                        : 1;
                    const spacing = 12.0;
                    final tileWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                        columns;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final tile in tiles)
                          SizedBox(width: tileWidth, child: tile),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _DetailBlock(
                  icon: Icons.checklist_rounded,
                  title: 'Requirements',
                  child: requirements.isEmpty
                      ? const _BlockText('No requirements listed.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final item in requirements)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _BlockText('•  $item'),
                              ),
                          ],
                        ),
                ),
                // The address is shown once, under the centre name.
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.blue1, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color:
                        value == CenterDetailsDialog.notSet ||
                            value == CenterDetailsDialog.unavailable
                        ? AppTheme.textMuted
                        : AppTheme.blue3,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.blue1, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.blue3,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockText extends StatelessWidget {
  const _BlockText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 12.5,
        height: 1.45,
      ),
    );
  }
}
