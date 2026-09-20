import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/announcement.dart';
import '../../services/announcement_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_modal.dart';
import '../../widgets/admin_notice.dart';

/// Patient Announcements.
///
/// Center-authored notices the CureNurture mobile app shows to this
/// center's patients. Self-contained: it reads and writes only the
/// `patient_announcements` table through [AnnouncementService], and
/// nothing else on the dashboard depends on it.
class AnnouncementsSection extends StatefulWidget {
  final String clinicId;

  const AnnouncementsSection({super.key, required this.clinicId});

  @override
  State<AnnouncementsSection> createState() => AnnouncementsSectionState();
}

class AnnouncementsSectionState extends State<AnnouncementsSection> {
  final AnnouncementService _service = AnnouncementService();

  List<Announcement> _announcements = [];
  bool _isLoading = true;
  String? _error;

  /// Owned by this list, so its scrollbar never has to guess between this
  /// list and the page scrolling behind it.
  final ScrollController _listScroll = ScrollController();

  /// Caps the section's height so a long list scrolls inside the card
  /// rather than pushing the rest of the dashboard down.
  static const double _listMaxHeight = 360;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _listScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AnnouncementsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final rows = await _service.getAnnouncements(clinicId: widget.clinicId);
      if (!mounted) return;
      setState(() {
        _announcements = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load announcements.';
        _isLoading = false;
      });
      debugPrint('Load announcements error: $e');
    }
  }

  // ------------------------------------------------------------------ CRUD

  Future<void> _create() async {
    final result = await showAnnouncementEditor(context: context);
    if (result == null || !mounted) return;

    try {
      final created = await _service.createAnnouncement(
        clinicId: widget.clinicId,
        title: result.title,
        body: result.body,
        date: result.date,
        color: result.color,
      );

      if (!mounted) return;
      setState(() => _announcements = [created, ..._announcements]);
      AdminNotice.success(
        context,
        'The announcement is now visible to patients in the mobile app.',
        title: 'Announcement posted',
      );
    } catch (e) {
      if (!mounted) return;
      AdminNotice.error(context, _friendlyError(e));
    }
  }

  Future<void> _edit(Announcement announcement) async {
    final result = await showAnnouncementEditor(
      context: context,
      existing: announcement,
    );
    if (result == null || !mounted) return;

    try {
      final updated = await _service.updateAnnouncement(
        id: announcement.id,
        title: result.title,
        body: result.body,
        date: result.date,
        clearDate: result.date == null,
        color: result.color,
      );

      if (!mounted) return;
      setState(() {
        _announcements = [
          for (final item in _announcements)
            if (item.id == updated.id) updated else item,
        ];
      });
      AdminNotice.success(
        context,
        'Patients will see the updated announcement in the mobile app.',
        title: 'Announcement updated',
      );
    } catch (e) {
      if (!mounted) return;
      AdminNotice.error(context, _friendlyError(e));
    }
  }

  Future<void> _delete(Announcement announcement) async {
    final confirmed = await showAdminConfirm(
      context: context,
      title: 'Delete this announcement?',
      message:
          'It will be removed from the CureNurture mobile app for every '
          'patient at this center. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      destructive: true,
      detail: _AnnouncementCard(
        announcement: announcement,
        compact: true,
        onEdit: null,
        onDelete: null,
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteAnnouncement(announcement.id);
      if (!mounted) return;
      setState(() {
        _announcements = _announcements
            .where((item) => item.id != announcement.id)
            .toList();
      });
      AdminNotice.success(
        context,
        'It has been removed from the mobile app.',
        title: 'Announcement deleted',
      );
    } catch (e) {
      if (!mounted) return;
      AdminNotice.error(context, _friendlyError(e));
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return 'Something went wrong. Please try again.';
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return AdminSection(
      title: 'Patient Announcements',
      subtitle:
          'Notices shown to this center’s patients in the CureNurture '
          'mobile app.',
      icon: Icons.campaign_rounded,
      accent: AppTheme.accentOrange,
      accentSoft: AppTheme.accentOrangeSoft,
      trailing: SizedBox(
        height: 38,
        child: ElevatedButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('New'),
          style: AppTheme.primaryButton(
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
      ),
      child: AnimatedSize(
        duration: AppTheme.motion(context, AppTheme.normal),
        curve: AppTheme.ease,
        alignment: Alignment.topCenter,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const _AnnouncementSkeletonList();

    if (_error != null) {
      return _EmptyBlock(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        message: 'Check your connection and refresh the dashboard.',
        accent: AppTheme.danger,
        accentSoft: AppTheme.dangerSoft,
      );
    }

    if (_announcements.isEmpty) {
      return const _EmptyBlock(
        icon: Icons.campaign_outlined,
        title: 'No announcements yet',
        message:
            'Post a center event, a reminder, or an urgent notice and it '
            'will appear in the patients’ mobile app.',
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _listMaxHeight),
      child: Scrollbar(
        controller: _listScroll,
        child: ListView.separated(
          controller: _listScroll,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: _announcements.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final announcement = _announcements[index];

            return _AnnouncementCard(
              key: ValueKey(announcement.id),
              announcement: announcement,
              onEdit: () => _edit(announcement),
              onDelete: () => _delete(announcement),
            );
          },
        ),
      ),
    );
  }
}

// =====================================================================
// Card
// =====================================================================

/// How one announcement colour token is painted here. The token itself is
/// what the database stores; these values are this client's rendering of
/// it, chosen so the text stays legible on the tint.
class _AnnouncementPalette {
  final Color background;
  final Color border;
  final Color accent;
  final IconData icon;
  final String eyebrow;

  const _AnnouncementPalette({
    required this.background,
    required this.border,
    required this.accent,
    required this.icon,
    required this.eyebrow,
  });

  static _AnnouncementPalette of(String token) {
    switch (token) {
      case AnnouncementColor.lightBlue:
        return const _AnnouncementPalette(
          background: Color(0xFFEDF5FA),
          border: Color(0xFFD3E4EF),
          accent: AppTheme.blue1,
          icon: Icons.info_outline_rounded,
          eyebrow: 'NOTICE',
        );
      case AnnouncementColor.green:
        return const _AnnouncementPalette(
          background: AppTheme.accentGreenSoft,
          border: Color(0xFFCCE3D6),
          accent: AppTheme.accentGreen,
          icon: Icons.check_circle_outline_rounded,
          eyebrow: 'GOOD NEWS',
        );
      case AnnouncementColor.orange:
        return const _AnnouncementPalette(
          background: AppTheme.accentOrangeSoft,
          border: Color(0xFFEEDAC5),
          accent: AppTheme.accentOrange,
          icon: Icons.notifications_active_outlined,
          eyebrow: 'IMPORTANT REMINDER',
        );
      case AnnouncementColor.purple:
        return const _AnnouncementPalette(
          background: AppTheme.accentPurpleSoft,
          border: Color(0xFFDBD1EA),
          accent: AppTheme.accentPurple,
          icon: Icons.assignment_outlined,
          eyebrow: 'ADMINISTRATIVE',
        );
      case AnnouncementColor.red:
        return const _AnnouncementPalette(
          background: AppTheme.dangerSoft,
          border: Color(0xFFF0CFCF),
          accent: AppTheme.danger,
          icon: Icons.warning_amber_rounded,
          eyebrow: 'URGENT NOTICE',
        );
      case AnnouncementColor.blue:
      default:
        return const _AnnouncementPalette(
          background: Color(0xFFE6EFF6),
          border: Color(0xFFC8DCE9),
          accent: AppTheme.blue3,
          icon: Icons.campaign_outlined,
          eyebrow: 'ANNOUNCEMENT',
        );
    }
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// A trimmed version used inside the delete confirmation, where the
  /// card is a reference rather than something to act on.
  final bool compact;

  const _AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _AnnouncementPalette.of(announcement.color);

    return AdminHoverCard(
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: AppTheme.motion(context, AppTheme.fast),
          curve: AppTheme.ease,
          padding: EdgeInsets.all(compact ? 14 : 16),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            border: Border.all(
              color: hovered && !compact
                  ? palette.accent.withValues(alpha: 0.35)
                  : palette.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(palette.icon, size: 14, color: palette.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      palette.eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  if (announcement.isUpcoming && !compact)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: palette.accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        'Upcoming',
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                announcement.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14.5,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                announcement.body,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(child: _dateLine(palette)),
                  if (!compact && onEdit != null) ...[
                    const SizedBox(width: 8),
                    _cardAction(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      color: palette.accent,
                      onTap: onEdit!,
                    ),
                  ],
                  if (!compact && onDelete != null) ...[
                    const SizedBox(width: 4),
                    _cardAction(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      color: AppTheme.danger,
                      onTap: onDelete!,
                      iconOnly: true,
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dateLine(_AnnouncementPalette palette) {
    final date = announcement.announcementDate;

    if (date == null) {
      final posted = announcement.createdAt;

      return Text(
        posted == null
            ? 'No specific date'
            : 'Posted ${DateFormat('MMMM d, y').format(posted.toLocal())}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Row(
      children: [
        Icon(
          Icons.event_rounded,
          size: 13,
          color: palette.accent.withValues(alpha: 0.75),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            DateFormat('MMMM d, y').format(date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool iconOnly = false,
  }) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          hoverColor: color.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: iconOnly ? 7 : 9,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                if (!iconOnly) ...[
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Empty / loading states
// =====================================================================

class _EmptyBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final Color accentSoft;

  const _EmptyBlock({
    required this.icon,
    required this.title,
    required this.message,
    this.accent = AppTheme.blue1,
    this.accentSoft = AppTheme.accentBlueSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: AppTheme.iconBox(accentSoft, radius: AppTheme.rLg),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementSkeletonList extends StatelessWidget {
  const _AnnouncementSkeletonList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(2, (index) {
        return Container(
          margin: EdgeInsets.only(bottom: index == 1 ? 0 : 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceTint,
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminSkeleton(width: 96, height: 9),
              SizedBox(height: 12),
              AdminSkeleton(width: 190, height: 14),
              SizedBox(height: 10),
              AdminSkeleton(height: 9),
              SizedBox(height: 6),
              AdminSkeleton(width: 240, height: 9),
              SizedBox(height: 14),
              AdminSkeleton(width: 120, height: 9),
            ],
          ),
        );
      }),
    );
  }
}

// =====================================================================
// Create / edit modal
// =====================================================================

/// What the editor returns. Null date means "no specific date", which is
/// also how an existing date is cleared.
class AnnouncementDraft {
  final String title;
  final String body;
  final DateTime? date;
  final String color;

  const AnnouncementDraft({
    required this.title,
    required this.body,
    required this.date,
    required this.color,
  });
}

/// Opens the Create / Edit Announcement modal.
///
/// Returns the draft to save, or null when the admin cancelled. Saving is
/// left to the caller, so the modal never touches the database itself.
Future<AnnouncementDraft?> showAnnouncementEditor({
  required BuildContext context,
  Announcement? existing,
}) {
  return showAdminDialog<AnnouncementDraft>(
    context: context,
    builder: (dialogContext) => _AnnouncementEditor(existing: existing),
  );
}

class _AnnouncementEditor extends StatefulWidget {
  final Announcement? existing;

  const _AnnouncementEditor({this.existing});

  @override
  State<_AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<_AnnouncementEditor> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  DateTime? _date;
  late String _color;
  String? _error;

  static const int _titleLimit = 90;
  static const int _bodyLimit = 600;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _bodyController = TextEditingController(text: existing?.body ?? '');
    _date = existing?.announcementDate;
    _color = existing?.color ?? AnnouncementColor.blue;

    _titleController.addListener(_onChanged);
    _bodyController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onChanged() {
    // Clears a validation message as soon as the admin starts fixing it.
    if (_error != null) setState(() => _error = null);
    setState(() {});
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _date ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // Wide enough for a notice about something that already happened
      // and for one planned well ahead.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.blue1,
              onPrimary: AppTheme.white,
              surface: AppTheme.surface,
              onSurface: AppTheme.textPrimary,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: AppTheme.surface,
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: AppTheme.blue1,
              headerForegroundColor: AppTheme.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.rXl),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  void _submit() {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Give the announcement a title.');
      return;
    }

    if (body.isEmpty) {
      setState(() => _error = 'Add the announcement details.');
      return;
    }

    Navigator.of(context).pop(
      AnnouncementDraft(title: title, body: body, date: _date, color: _color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminModal(
      title: _isEditing ? 'Edit Announcement' : 'Create Announcement',
      subtitle: _isEditing
          ? 'Changes appear in the patients’ mobile app right away.'
          : 'This will be shown to every patient at your center in the '
                'CureNurture mobile app.',
      icon: _isEditing ? Icons.edit_note_rounded : Icons.campaign_rounded,
      accent: AppTheme.accentOrange,
      accentSoft: AppTheme.accentOrangeSoft,
      size: AdminModalSize.medium,
      errorText: _error,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: AppTheme.secondaryButton(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: Icon(
            _isEditing ? Icons.save_rounded : Icons.send_rounded,
            size: 17,
          ),
          label: Text(_isEditing ? 'Save changes' : 'Post announcement'),
          style: AppTheme.primaryButton(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminField(
            label: 'Title',
            required: true,
            helper: '${_titleController.text.characters.length}/$_titleLimit',
            child: TextField(
              controller: _titleController,
              maxLength: _titleLimit,
              textCapitalization: TextCapitalization.sentences,
              style: AppTheme.fieldTextStyle.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: AppTheme.field(
                hintText: 'e.g. Center closed on Friday',
              ).copyWith(counterText: ''),
            ),
          ),

          const AdminFieldGap(),

          AdminField(
            label: 'Announcement details',
            required: true,
            helper: '${_bodyController.text.characters.length}/$_bodyLimit',
            child: TextField(
              controller: _bodyController,
              maxLength: _bodyLimit,
              minLines: 4,
              maxLines: 7,
              textCapitalization: TextCapitalization.sentences,
              style: AppTheme.fieldTextStyle.copyWith(height: 1.5),
              decoration: AppTheme.field(
                hintText:
                    'Explain what patients need to know, and what they '
                    'should do about it.',
              ).copyWith(counterText: '', alignLabelWithHint: true),
            ),
          ),

          const AdminFieldGap(),

          AdminField(
            label: 'Date',
            helper: 'Optional',
            child: _DateField(
              date: _date,
              onPick: _pickDate,
              onClear: () => setState(() => _date = null),
            ),
          ),

          const AdminFieldGap(),

          AdminField(
            label: 'Announcement colour',
            child: _ColorPicker(
              selected: _color,
              onSelect: (token) => setState(() => _color = token),
            ),
          ),

          const SizedBox(height: 20),

          const Text('Preview', style: AppTheme.fieldLabel),
          const SizedBox(height: 8),
          _AnnouncementCard(
            announcement: Announcement(
              id: 'preview',
              clinicId: '',
              title: _titleController.text.trim().isEmpty
                  ? 'Announcement title'
                  : _titleController.text.trim(),
              body: _bodyController.text.trim().isEmpty
                  ? 'The announcement details will appear here.'
                  : _bodyController.text.trim(),
              announcementDate: _date,
              color: _color,
              createdAt: widget.existing?.createdAt ?? DateTime.now(),
            ),
            compact: true,
            onEdit: null,
            onDelete: null,
          ),
        ],
      ),
    );
  }
}

/// The optional date control: a field-shaped button that opens the date
/// picker, with a clear affordance once a date is set.
class _DateField extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DateField({
    required this.date,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;

    return Material(
      color: AppTheme.surfaceTint,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        hoverColor: AppTheme.accentSoft,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_rounded,
                size: 19,
                color: hasDate ? AppTheme.blue1 : AppTheme.iconMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasDate
                      ? DateFormat('MMMM d, y').format(date!)
                      : 'No specific date',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasDate ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 13.5,
                    fontWeight: hasDate ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (hasDate)
                IconButton(
                  tooltip: 'Remove date',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: AppTheme.iconMuted,
                  splashRadius: 16,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                )
              else
                const Text(
                  'Choose',
                  style: TextStyle(
                    color: AppTheme.blue1,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small, fixed set of harmonious colours rather than a full picker -
/// every option is guaranteed readable against the card's text colours.
class _ColorPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _ColorPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AnnouncementColor.all.map((token) {
            final palette = _AnnouncementPalette.of(token);
            final isSelected = token == selected;

            return Tooltip(
              message: AnnouncementColor.meaning(token),
              child: Material(
                color: palette.background,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                child: InkWell(
                  onTap: () => onSelect(token),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  child: AnimatedContainer(
                    duration: AppTheme.motion(context, AppTheme.fast),
                    curve: AppTheme.ease,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                      border: Border.all(
                        color: isSelected ? palette.accent : palette.border,
                        width: isSelected ? 1.6 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: palette.accent,
                            shape: BoxShape.circle,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 10,
                                  color: AppTheme.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AnnouncementColor.label(token),
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: 12.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          AnnouncementColor.meaning(selected),
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
