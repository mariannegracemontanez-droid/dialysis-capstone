import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/clinic_announcement.dart';

const Color _primary = Color(0xFF225E72);
const Color _heading = Color(0xFF173B4F);
const Color _body = Color(0xFF5B6D7D);
const Color _muted = Color(0xFF7A8A94);
const Color _cardBorder = Color(0xFFE1EAF0);

/// How one announcement colour token is drawn. Mirrors the admin panel's
/// palette (announcements_section.dart) so a notice reads the same on both
/// sides; unknown tokens fall back to the general `blue` style.
class _AnnouncementStyle {
  final Color background;
  final Color border;
  final Color accent;
  final IconData icon;
  final String label;

  const _AnnouncementStyle({
    required this.background,
    required this.border,
    required this.accent,
    required this.icon,
    required this.label,
  });

  factory _AnnouncementStyle.of(String token) {
    switch (token) {
      case 'light_blue':
        return const _AnnouncementStyle(
          background: Color(0xFFEDF5FA),
          border: Color(0xFFD3E4EF),
          accent: Color(0xFF1D7FA3),
          icon: Icons.info_outline_rounded,
          label: 'Notice',
        );
      case 'green':
        return const _AnnouncementStyle(
          background: Color(0xFFE9F4EE),
          border: Color(0xFFCCE3D6),
          accent: Color(0xFF2F7A55),
          icon: Icons.check_circle_outline_rounded,
          label: 'Good news',
        );
      case 'orange':
        return const _AnnouncementStyle(
          background: Color(0xFFFAF0E7),
          border: Color(0xFFEEDAC5),
          accent: Color(0xFFB0662C),
          icon: Icons.notifications_active_outlined,
          label: 'Reminder',
        );
      case 'purple':
        return const _AnnouncementStyle(
          background: Color(0xFFF1EDF7),
          border: Color(0xFFDBD1EA),
          accent: Color(0xFF6B4E8F),
          icon: Icons.assignment_outlined,
          label: 'Administrative',
        );
      case 'red':
        return const _AnnouncementStyle(
          background: Color(0xFFFBEDED),
          border: Color(0xFFF0CFCF),
          accent: Color(0xFFB3403D),
          icon: Icons.warning_amber_rounded,
          label: 'Urgent',
        );
      case 'blue':
      default:
        return const _AnnouncementStyle(
          background: Color(0xFFE6EFF6),
          border: Color(0xFFC8DCE9),
          accent: _primary,
          icon: Icons.campaign_outlined,
          label: 'Announcement',
        );
    }
  }
}

/// Short date shown on the collapsed card: the day the notice is about if
/// it has one, otherwise when it was posted.
String _shortDateLabel(ClinicAnnouncement announcement) {
  final date = announcement.announcementDate;
  if (date != null) return DateFormat('EEE, MMM d').format(date);

  final posted = announcement.createdAt;
  if (posted != null) return 'Posted ${DateFormat('MMM d').format(posted)}';

  return '';
}

Widget _sectionHeader({required String title, required String subtitle}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: _heading,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _muted,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

/// A flat, non-interactive card for loading, empty and error states.
Widget _stateCard({
  required IconData icon,
  required String message,
  VoidCallback? onRetry,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _cardBorder),
    ),
    child: Row(
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _muted, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _body, fontSize: 13, height: 1.4),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(color: _primary, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Clinic Announcements
// ---------------------------------------------------------------------------

class ClinicAnnouncementsSection extends StatefulWidget {
  final bool isLoading;
  final bool hasError;
  final String? clinicName;
  final List<ClinicAnnouncement> announcements;
  final VoidCallback onRetry;

  const ClinicAnnouncementsSection({
    super.key,
    required this.isLoading,
    required this.hasError,
    required this.clinicName,
    required this.announcements,
    required this.onRetry,
  });

  @override
  State<ClinicAnnouncementsSection> createState() =>
      _ClinicAnnouncementsSectionState();
}

class _ClinicAnnouncementsSectionState
    extends State<ClinicAnnouncementsSection> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  /// Above this, the dot row would crowd the navigation bar; the "n / N"
  /// counter alone carries the position.
  static const int _maxDots = 7;

  @override
  void didUpdateWidget(covariant ClinicAnnouncementsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reload can shrink the list; never leave the carousel past its end.
    if (_currentIndex >= widget.announcements.length && _currentIndex != 0) {
      _currentIndex = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinicName = widget.clinicName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          title: 'Clinic Announcements',
          subtitle: clinicName == null
              ? 'Updates from your dialysis clinic'
              : 'Latest updates from $clinicName',
        ),
        const SizedBox(height: 14),
        _buildBody(context),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.isLoading) {
      return _stateCard(
        icon: Icons.campaign_outlined,
        message: 'Loading clinic announcements...',
      );
    }

    if (widget.hasError) {
      return _stateCard(
        icon: Icons.cloud_off_rounded,
        message: 'We could not load clinic announcements right now.',
        onRetry: widget.onRetry,
      );
    }

    final announcements = widget.announcements;
    if (announcements.isEmpty) {
      return _stateCard(
        icon: Icons.campaign_outlined,
        message:
            'No announcements right now. Clinic updates about schedules, '
            'closures, and events will appear here.',
      );
    }

    // Fixed height so a long announcement never stretches the Home page;
    // scaled with the system text size so large fonts don't overflow.
    final cardHeight = MediaQuery.textScalerOf(
      context,
    ).scale(170).clamp(170.0, 280.0);

    return Column(
      children: [
        SizedBox(
          height: cardHeight,
          child: PageView.builder(
            controller: _pageController,
            itemCount: announcements.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildAnnouncementCard(
                announcements[index],
                index,
                announcements.length,
              ),
            ),
          ),
        ),
        if (announcements.length > 1) ...[
          const SizedBox(height: 12),
          _buildNavigation(announcements.length),
        ],
      ],
    );
  }

  Widget _buildAnnouncementCard(
    ClinicAnnouncement announcement,
    int index,
    int total,
  ) {
    final style = _AnnouncementStyle.of(announcement.color);
    final dateLabel = _shortDateLabel(announcement);

    return Material(
      color: style.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: style.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showAnnouncementDetails(announcement, index, total),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AnnouncementChip(style: style),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateLabel,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                announcement.title.isEmpty
                    ? 'Clinic announcement'
                    : announcement.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _heading,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  announcement.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _body,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tap to read full announcement',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: style.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: style.accent,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigation(int total) {
    final isFirst = _currentIndex == 0;
    final isLast = _currentIndex >= total - 1;

    return Row(
      children: [
        _NavButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous announcement',
          onPressed: isFirst ? null : () => _goTo(_currentIndex - 1),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_currentIndex + 1} / $total',
                style: const TextStyle(
                  color: _primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (total <= _maxDots) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    total,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 6,
                      width: _currentIndex == index ? 18 : 6,
                      decoration: BoxDecoration(
                        color: _currentIndex == index
                            ? _primary
                            : const Color(0xFFD5E2E8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        _NavButton(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next announcement',
          onPressed: isLast ? null : () => _goTo(_currentIndex + 1),
        ),
      ],
    );
  }

  void _showAnnouncementDetails(
    ClinicAnnouncement announcement,
    int index,
    int total,
  ) {
    final style = _AnnouncementStyle.of(announcement.color);
    final meta = <_DetailMeta>[
      if (announcement.announcementDate != null)
        _DetailMeta(
          icon: Icons.event_outlined,
          text: DateFormat(
            'EEEE, MMMM d, yyyy',
          ).format(announcement.announcementDate!),
        ),
      if (announcement.createdAt != null)
        _DetailMeta(
          icon: Icons.schedule_rounded,
          text:
              'Posted ${DateFormat('MMM d, yyyy • h:mm a').format(announcement.createdAt!)}',
        ),
      if (widget.clinicName != null)
        _DetailMeta(
          icon: Icons.local_hospital_outlined,
          text: widget.clinicName!,
        ),
    ];

    _showClinicDetailSheet(
      context: context,
      chip: _AnnouncementChip(style: style),
      trailing: total > 1 ? '${index + 1} / $total' : null,
      title: announcement.title.isEmpty
          ? 'Clinic announcement'
          : announcement.title,
      meta: meta,
      body: announcement.body,
    );
  }
}

class _AnnouncementChip extends StatelessWidget {
  final _AnnouncementStyle style;

  const _AnnouncementChip({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: style.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.accent, size: 14),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              color: style.accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled ? Colors.white : const Color(0xFFF1F5F8),
        shape: CircleBorder(
          side: BorderSide(
            color: enabled ? const Color(0xFFD4E7EE) : const Color(0xFFE6EDF1),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 44,
            width: 44,
            child: Icon(
              icon,
              color: enabled ? _primary : const Color(0xFFB5C3CC),
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clinic House Rules
// ---------------------------------------------------------------------------

class ClinicHouseRulesSection extends StatelessWidget {
  final bool isLoading;
  final bool hasError;
  final String? clinicName;
  final String houseRules;
  final VoidCallback onRetry;

  const ClinicHouseRulesSection({
    super.key,
    required this.isLoading,
    required this.hasError,
    required this.clinicName,
    required this.houseRules,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          title: 'Clinic House Rules',
          subtitle: clinicName == null
              ? 'Rules to follow during your clinic visits'
              : 'Rules to follow at $clinicName',
        ),
        const SizedBox(height: 14),
        _buildBody(context),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading) {
      return _stateCard(
        icon: Icons.fact_check_outlined,
        message: 'Loading clinic house rules...',
      );
    }

    if (hasError) {
      return _stateCard(
        icon: Icons.cloud_off_rounded,
        message: 'We could not load the clinic house rules right now.',
        onRetry: onRetry,
      );
    }

    final rules = houseRules.trim();
    if (rules.isEmpty) {
      return _stateCard(
        icon: Icons.fact_check_outlined,
        message:
            'Your clinic has not posted house rules yet. Please ask the '
            'clinic staff if you have questions about visit policies.',
      );
    }

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showFullRules(context, rules),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1F5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: _primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Please follow these rules during every visit.',
                      style: TextStyle(
                        color: _heading,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8FA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE3EDF2)),
                ),
                child: Text(
                  rules,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _body,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showFullRules(context, rules),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: _primary,
                    size: 18,
                  ),
                  label: const Text(
                    'View all house rules',
                    style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullRules(BuildContext context, String rules) {
    _showClinicDetailSheet(
      context: context,
      chip: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fact_check_outlined, color: _primary, size: 14),
            SizedBox(width: 5),
            Text(
              'House rules',
              style: TextStyle(
                color: _primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      title: 'Clinic House Rules',
      meta: [
        if (clinicName != null)
          _DetailMeta(icon: Icons.local_hospital_outlined, text: clinicName!),
      ],
      body: rules,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared detail sheet
// ---------------------------------------------------------------------------

class _DetailMeta {
  final IconData icon;
  final String text;

  const _DetailMeta({required this.icon, required this.text});
}

/// Bottom sheet that shows the full text of an announcement or the house
/// rules. Sized to its content up to 85% of the screen, with the body
/// scrolling inside it so long text never pushes the Close button away.
Future<void> _showClinicDetailSheet({
  required BuildContext context,
  required Widget chip,
  required String title,
  required String body,
  List<_DetailMeta> meta = const [],
  String? trailing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.85;

      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    height: 5,
                    width: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5E2E8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 10, 0),
                  child: Row(
                    children: [
                      chip,
                      if (trailing != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          trailing,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded, color: _body),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _heading,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.25,
                          ),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...meta.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(item.icon, color: _muted, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.text,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        const Divider(color: _cardBorder, height: 1),
                        const SizedBox(height: 16),
                        Text(
                          body,
                          style: const TextStyle(
                            color: Color(0xFF34495A),
                            fontSize: 14.5,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: _primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
