import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/center_profile.dart';
import '../../models/center_schedule.dart';
import '../../models/clinic_shift.dart';
import '../../services/center_profile_service.dart';
import '../../services/center_schedule_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/admin_validators.dart';
import '../../widgets/admin_card_row.dart';
import '../../widgets/admin_header.dart';
import '../../widgets/admin_notice.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_title.dart';
import '../auth/logout.dart';
import '../dashboard/dashboard_page.dart';
import '../patients/patients_page.dart';

/// The Center Admin's view of their own center, and the one place they
/// edit it.
///
/// Everything on this page is backed by data that already existed:
/// `clinics.machine`, `clinics.requirements`, `clinics.operating_hours`,
/// `clinic_shifts`, and the new `clinics.house_rules` column. Saving goes
/// through [CenterProfileService], which writes those same columns -- no
/// second capacity field, no second requirements store, no second shift
/// system.
///
/// View and edit are the same page rather than a modal: there are five
/// groups of related fields here, and a dialog tall enough to hold them
/// would scroll worse than the page does.
class CenterProfilePage extends StatefulWidget {
  const CenterProfilePage({super.key});

  @override
  State<CenterProfilePage> createState() => _CenterProfilePageState();
}

class _CenterProfilePageState extends State<CenterProfilePage> {
  final CenterProfileService _service = CenterProfileService();
  final CenterScheduleService _scheduleService = CenterScheduleService();
  final ScrollController _pageScroll = ScrollController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  CenterProfile? _center;
  List<ClinicShift> _shifts = const [];
  List<String> _operatingDays = const [];
  CenterCapacitySnapshot? _capacity;
  String? _adminName;

  bool _editing = false;

  // ---- edit state -------------------------------------------------
  // Populated from the loaded center when edit mode opens, discarded on
  // cancel, so an abandoned edit can never leak into the next one.

  final TextEditingController _machinesController = TextEditingController();
  final TextEditingController _houseRulesController = TextEditingController();

  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;

  /// True when the stored operating_hours string was free text this
  /// panel could not read as a time range. The admin is told, rather
  /// than having the old value silently replaced.
  bool _hoursWereFreeText = false;
  String _originalHoursText = '';

  final Map<String, bool> _selectedRequirements = {};
  final List<TextEditingController> _customRequirements = [];

  final List<_ShiftDraft> _shiftDrafts = [];

  static const int _houseRulesLimit = 4000;
  static const int _customRequirementLimit = 120;
  static const int _maxMachines = 500;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    _machinesController.dispose();
    _houseRulesController.dispose();
    _disposeEditControllers();
    super.dispose();
  }

  void _disposeEditControllers() {
    for (final controller in _customRequirements) {
      controller.dispose();
    }
    _customRequirements.clear();

    for (final draft in _shiftDrafts) {
      draft.dispose();
    }
    _shiftDrafts.clear();
  }

  // ------------------------------------------------------------ load

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final snapshot = await _service.loadProfile();
      final adminName = await _service.getCurrentAdminName();

      // Best effort: the page is still useful without live occupancy,
      // so a capacity read that fails must not blank the whole profile.
      CenterCapacitySnapshot? capacity;
      try {
        capacity = await _scheduleService.getCapacitySnapshot(
          snapshot.center.id,
        );
      } catch (e) {
        debugPrint('Center profile capacity snapshot error: $e');
      }

      if (!mounted) return;

      setState(() {
        _center = snapshot.center;
        _shifts = snapshot.shifts;
        _operatingDays = snapshot.operatingDays;
        _capacity = capacity;
        _adminName = adminName;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load center profile error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    // The one setup mistake that is worth naming precisely: the page's
    // migration has not been run, so either the house_rules column or
    // the update function is missing. Anything else is reported plainly.
    if (text.contains('update_center_profile') ||
        text.contains('house_rules')) {
      return 'The center profile is not set up in the database yet. Run '
          'supabase/center_profile.sql in the Supabase SQL editor, then '
          'reload this page.';
    }

    return 'Something went wrong. Please try again.';
  }

  // -------------------------------------------------------- edit mode

  void _startEditing() {
    final center = _center;
    if (center == null) return;

    _disposeEditControllers();

    _machinesController.text = center.machines.toString();
    _houseRulesController.text = center.houseRules;

    // Operating hours: read the stored string back into two times when
    // it is in the form this panel writes. When it is legacy free text,
    // keep it visible and start from the center's own shift window
    // rather than guessing.
    _originalHoursText = center.operatingHours.trim();
    final parsed = AdminValidators.parseRange(center.operatingHours);

    if (parsed != null) {
      _openTime = parsed.start;
      _closeTime = parsed.end;
      _hoursWereFreeText = false;
    } else {
      _hoursWereFreeText = _originalHoursText.isNotEmpty;
      _openTime = _earliestShiftStart() ?? const TimeOfDay(hour: 8, minute: 0);
      _closeTime = _latestShiftEnd() ?? const TimeOfDay(hour: 17, minute: 0);
    }

    // Requirements: anything stored that exactly matches a common option
    // comes back ticked; anything else is preserved verbatim as a custom
    // row instead of being dropped or forced into a label it isn't.
    _selectedRequirements
      ..clear()
      ..addEntries(
        kCommonCenterRequirements.map(
          (option) => MapEntry(option, center.requirements.contains(option)),
        ),
      );

    for (final item in center.requirements) {
      if (!kCommonCenterRequirements.contains(item)) {
        _customRequirements.add(TextEditingController(text: item));
      }
    }

    // One draft per shift code, NOT one per stored row. A center the
    // Super Admin created after center_scheduling_foundation.sql ran has
    // no `clinic_shifts` rows at all, so editing off `_shifts` alone gave
    // the admin nothing to fill in and no way out of the empty state. A
    // code with no stored row gets a blank draft instead, which is only
    // written once the admin actually configures it.
    for (final code in ClinicShift.codes) {
      final existing = ClinicShift.byCode(_shifts, code);
      _shiftDrafts.add(
        existing != null
            ? _ShiftDraft.from(existing)
            : _ShiftDraft.blank(shiftCode: code, machines: center.machines),
      );
    }

    setState(() => _editing = true);
  }

  void _cancelEditing() {
    _disposeEditControllers();
    setState(() => _editing = false);
  }

  TimeOfDay? _earliestShiftStart() {
    TimeOfDay? earliest;
    for (final shift in _shifts) {
      final time = AdminValidators.parseTime(shift.startTime);
      if (time == null) continue;
      if (earliest == null ||
          AdminValidators.minutesOf(time) <
              AdminValidators.minutesOf(earliest)) {
        earliest = time;
      }
    }
    return earliest;
  }

  TimeOfDay? _latestShiftEnd() {
    TimeOfDay? latest;
    for (final shift in _shifts) {
      final time = AdminValidators.parseTime(shift.endTime);
      if (time == null) continue;
      if (latest == null ||
          AdminValidators.minutesOf(time) > AdminValidators.minutesOf(latest)) {
        latest = time;
      }
    }
    return latest;
  }

  void _addCustomRequirement() {
    setState(() => _customRequirements.add(TextEditingController()));
  }

  void _removeCustomRequirement(int index) {
    setState(() {
      final removed = _customRequirements.removeAt(index);
      removed.dispose();
    });
  }

  /// The exact list that will replace `clinics.requirements`. Unticking a
  /// box removes it from here, which is what makes an unticked
  /// requirement actually disappear from the stored array.
  List<String> _buildRequirements() {
    return <String>[
      for (final option in kCommonCenterRequirements)
        if (_selectedRequirements[option] == true) option,
      for (final controller in _customRequirements)
        if (controller.text.trim().isNotEmpty) controller.text.trim(),
    ];
  }

  // -------------------------------------------------------- validation

  /// Every rule the Save button applies, in the order the admin reads the
  /// form. Returns the first problem as a sentence naming the field, or
  /// null when everything is valid.
  String? _validate() {
    final machinesError = AdminValidators.wholeNumber(
      _machinesController.text,
      label: 'number of dialysis machines',
      min: 0,
      max: _maxMachines,
    );
    if (machinesError != null) return machinesError;

    final machines = int.parse(_machinesController.text.trim());

    final hoursError = AdminValidators.timeRange(
      start: _openTime,
      end: _closeTime,
      label: 'operating hours',
    );
    if (hoursError != null) return hoursError;

    final requirements = _buildRequirements();

    for (var i = 0; i < _customRequirements.length; i++) {
      final text = _customRequirements[i].text.trim();
      if (text.isEmpty) {
        return 'Custom requirement ${i + 1} is empty. Type the requirement '
            'or remove the row.';
      }
      if (text.length > _customRequirementLimit) {
        return 'Custom requirement ${i + 1} is too long (maximum '
            '$_customRequirementLimit characters).';
      }
    }

    if (requirements.isEmpty) {
      return 'Please enter at least one requirement. Tick the documents '
          'patients must bring, or add a custom requirement.';
    }

    final houseRulesError = AdminValidators.optionalText(
      _houseRulesController.text,
      label: 'house rules',
      maxLength: _houseRulesLimit,
    );
    if (houseRulesError != null) return houseRulesError;

    // Shifts. Each one is checked on its own first, so the message names
    // the shift that is wrong; the cross-shift checks come after.
    for (final draft in _shiftDrafts) {
      // A shift this center has never configured and the admin has not
      // started filling in is left alone: empty AM + empty PM is the
      // legitimate starting state of a newly created center, not a form
      // error. The moment either time is picked or a name is typed, the
      // draft stops being unconfigured and every rule below applies to
      // it in full -- so a half-entered range is still refused.
      if (draft.isUnconfigured) continue;

      final label = '${draft.shiftCode} shift';

      final labelError = AdminValidators.optionalText(
        draft.labelController.text,
        label: '$label name',
        maxLength: 40,
      );
      if (labelError != null) return labelError;

      final rangeError = AdminValidators.timeRange(
        start: draft.start,
        end: draft.end,
        label: label,
      );
      if (rangeError != null) return rangeError;

      final capacityError = AdminValidators.wholeNumber(
        draft.capacityController.text,
        label: '$label capacity',
        min: 0,
        max: _maxMachines,
      );
      if (capacityError != null) return capacityError;

      final capacity = int.parse(draft.capacityController.text.trim());

      // One machine serves one patient per shift, which is the rule the
      // seeded capacities and the Super Admin's machines x 2 slot
      // estimate both already assume.
      if (capacity > machines) {
        return 'The $label capacity ($capacity) cannot be more than the '
            'center\'s $machines dialysis '
            '${machines == 1 ? 'machine' : 'machines'}.';
      }

      if (!draft.isActive) continue;

      final withinError = AdminValidators.rangeWithin(
        start: draft.start!,
        end: draft.end!,
        outerStart: _openTime!,
        outerEnd: _closeTime!,
        label: label,
        outerLabel: 'center operating hours',
      );
      if (withinError != null) return withinError;
    }

    final configured = _shiftDrafts.where((d) => !d.isUnconfigured).toList();
    final active = configured.where((d) => d.isActive).toList();

    // Only once this center has at least one shift in play. A center
    // that has configured none yet is saving the REST of its profile,
    // and blocking that on a shift it has not reached would make the
    // page unsavable for every newly created center. For a center whose
    // shifts already exist every draft is configured, so this rule still
    // fires exactly as it did before.
    if (configured.isNotEmpty && active.isEmpty) {
      return 'At least one shift must stay active, otherwise no patient '
          'can be scheduled at this center.';
    }

    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        final overlap = AdminValidators.nonOverlappingRanges(
          firstStart: active[i].start!,
          firstEnd: active[i].end!,
          firstLabel: '${active[i].shiftCode} shift',
          secondStart: active[j].start!,
          secondEnd: active[j].end!,
          secondLabel: '${active[j].shiftCode} shift',
        );
        if (overlap != null) return overlap;
      }
    }

    return null;
  }

  /// The highest number of patients already recurring in [shiftId] on any
  /// single operating day. Lowering capacity under this would leave days
  /// over-booked, so the admin is asked to confirm rather than blocked --
  /// a center genuinely losing a machine has to be able to record that.
  int _peakScheduled(String shiftId) {
    final snapshot = _capacity;
    if (snapshot == null) return 0;

    var peak = 0;
    for (final day in snapshot.days) {
      final shift = day.shiftById(shiftId);
      if (shift != null && shift.scheduled > peak) peak = shift.scheduled;
    }
    return peak;
  }

  // -------------------------------------------------------------- save

  Future<void> _save() async {
    final center = _center;
    if (center == null || _saving) return;

    final error = _validate();
    if (error != null) {
      AdminNotice.error(context, error, title: 'Check the center profile');
      return;
    }

    // Over-booking warnings, gathered before anything is written.
    final overbooked = <String>[];
    for (final draft in _shiftDrafts) {
      final shift = draft.shift;

      // Nothing can be over-booked in a shift that does not exist yet:
      // it has no id to look occupancy up by and no patients recurring
      // in it. Skipping covers both the untouched and the newly
      // configured case.
      if (shift == null) continue;

      final capacity = int.parse(draft.capacityController.text.trim());
      final peak = _peakScheduled(shift.id);

      if (!draft.isActive && peak > 0) {
        overbooked.add(
          'Turning off the ${draft.shiftCode} shift leaves $peak '
          'patient${peak == 1 ? '' : 's'} recurring in it.',
        );
      } else if (draft.isActive && capacity < peak) {
        overbooked.add(
          'The ${draft.shiftCode} shift already has $peak '
          'patient${peak == 1 ? '' : 's'} on its busiest day, more than the '
          'new capacity of $capacity.',
        );
      }
    }

    if (overbooked.isNotEmpty) {
      final proceed = await AdminNotice.confirm(
        context,
        title: 'This leaves shifts over capacity',
        message:
            '${overbooked.join(' ')} Existing schedules are not changed, but '
            'those days will show as over capacity until patients are moved.',
        confirmLabel: 'Save anyway',
        icon: Icons.event_busy_rounded,
      );

      if (!proceed || !mounted) return;
    }

    setState(() => _saving = true);

    try {
      await _service.saveCenterInfo(
        machines: int.parse(_machinesController.text.trim()),
        requirements: _buildRequirements(),
        operatingHours: AdminValidators.formatRange(_openTime!, _closeTime!),
        houseRules: _houseRulesController.text,
      );

      // Only the shifts that actually changed are written, so an
      // untouched shift's row keeps its existing values and timestamps.
      for (final draft in _shiftDrafts) {
        // Never configured and not being configured now: no row is
        // created, so a center that saves the rest of its profile does
        // not get half-empty AM/PM rows it never asked for.
        if (draft.isUnconfigured) continue;

        final shift = draft.shift;

        if (shift == null) {
          // First time this center's AM or PM shift is configured.
          // Upserts on `unique (clinic_id, shift_code)`, so saving again
          // updates this same row instead of adding a second one.
          await _service.createShift(
            shiftCode: draft.shiftCode,
            label: draft.labelController.text.trim(),
            startTime: AdminValidators.toSqlTime(draft.start!),
            endTime: AdminValidators.toSqlTime(draft.end!),
            capacity: int.parse(draft.capacityController.text.trim()),
            isActive: draft.isActive,
          );
          continue;
        }

        if (!draft.isDirty) continue;

        await _service.saveShift(
          shift: shift,
          label: draft.labelController.text.trim(),
          startTime: AdminValidators.toSqlTime(draft.start!),
          endTime: AdminValidators.toSqlTime(draft.end!),
          capacity: int.parse(draft.capacityController.text.trim()),
          isActive: draft.isActive,
        );
      }

      if (!mounted) return;

      _disposeEditControllers();
      setState(() {
        _editing = false;
        _saving = false;
      });

      await _load();

      if (!mounted) return;
      AdminNotice.success(
        context,
        'The center profile has been updated.',
        title: 'Center profile saved',
      );
    } catch (e) {
      debugPrint('Save center profile error: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      AdminNotice.error(context, _friendlyError(e));
    }
  }

  // ------------------------------------------------------------ shell

  void _onNavSelect(int index) {
    if (index == AdminNav.dashboard) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
    } else if (index == AdminNav.patients) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PatientsPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminTitle(
      page: 'Center Profile',
      child: Scaffold(
        backgroundColor: AppTheme.canvas,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminSidebar(
              selectedIndex: AdminNav.centerProfile,
              onSelect: _onNavSelect,
              onLogout: () => adminLogout(context),
              centerName: _center?.name,
              machineCount: _center?.machines,
            ),
            Expanded(
              child: Column(
                children: [
                  AdminHeader(
                    adminName: _adminName,
                    centerName: _center?.name,
                    centerProfileActive: true,
                    onOpenCenterProfile: () {},
                  ),
                  Expanded(child: _content()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final loadError = _loadError;
    if (loadError != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: AppTheme.iconBox(
                    AppTheme.dangerSoft,
                    radius: AppTheme.rLg,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: AppTheme.danger,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Center profile unavailable',
                  style: AppTheme.sectionTitle,
                ),
                const SizedBox(height: 8),
                Text(
                  loadError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Try again'),
                  style: AppTheme.secondaryButton(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = AppTheme.pagePadding(MediaQuery.of(context).size.width);

        return Scrollbar(
          controller: _pageScroll,
          child: SingleChildScrollView(
            controller: _pageScroll,
            padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 8),
            child: Center(
              child: ConstrainedBox(
                // The same ceiling the Dashboard and Patients pages use,
                // so the three read as one workspace rather than this one
                // sitting narrower than the pages either side of it.
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.maxContentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pageHeader(),
                    const SizedBox(height: 18),
                    _overviewCards(constraints.maxWidth),
                    const SizedBox(height: 18),
                    _capacitySection(),
                    const SizedBox(height: 18),
                    _hoursSection(),
                    const SizedBox(height: 18),
                    _shiftsSection(),
                    const SizedBox(height: 18),
                    _requirementsSection(),
                    const SizedBox(height: 18),
                    _houseRulesSection(),
                    const SizedBox(height: 18),
                    _donationPlaceholder(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pageHeader() {
    final center = _center!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.surface, AppTheme.headerTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: AppTheme.iconBox(
                  AppTheme.accentBlueSoft,
                  radius: AppTheme.rLg,
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: AppTheme.blue1,
                  size: 23,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CENTER INFORMATION', style: AppTheme.eyebrow),
                    const SizedBox(height: 6),
                    Text(center.name, style: AppTheme.pageTitle),
                    const SizedBox(height: 7),
                    Text(
                      [
                        if (center.address.trim().isNotEmpty) center.address,
                        if (center.city.trim().isNotEmpty) center.city,
                      ].join(', '),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = _editing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : _cancelEditing,
                      style: AppTheme.secondaryButton(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 17),
                      label: Text(_saving ? 'Saving...' : 'Save Changes'),
                      style: AppTheme.primaryButton(),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('Refresh'),
                      style: AppTheme.secondaryButton(),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _startEditing,
                      icon: const Icon(Icons.edit_rounded, size: 17),
                      label: const Text('Edit Center Profile'),
                      style: AppTheme.primaryButton(),
                    ),
                  ],
                );

          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 16), actions],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _overviewCards(double width) {
    final center = _center!;

    return AdminCardRow(
      width: width,
      cards: [
        _infoCard(
          'Contact number',
          center.contactNumber.trim().isEmpty
              ? 'Not provided'
              : center.contactNumber,
          Icons.call_rounded,
          AppTheme.blue1,
          AppTheme.accentBlueSoft,
        ),
        _infoCard(
          'Dialysis machines',
          center.machines.toString(),
          Icons.medical_services_rounded,
          AppTheme.accentTeal,
          AppTheme.accentTealSoft,
        ),
        _infoCard(
          'Operating days',
          _operatingDays.isEmpty ? 'Not set' : '${_operatingDays.length} days',
          Icons.calendar_month_rounded,
          AppTheme.accentGreen,
          AppTheme.accentGreenSoft,
          footnote: _operatingDays.isEmpty
              ? null
              : _operatingDays.map((d) => d.substring(0, 3)).join(', '),
        ),
        _infoCard(
          'Operating hours',
          center.operatingHours.trim().isEmpty
              ? 'Not set'
              : center.operatingHours,
          Icons.schedule_rounded,
          AppTheme.accentOrange,
          AppTheme.accentOrangeSoft,
        ),
      ],
    );
  }

  Widget _infoCard(
    String label,
    String value,
    IconData icon,
    Color accent,
    Color soft, {
    String? footnote,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: AppTheme.iconBox(soft, radius: AppTheme.rLg),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(), style: AppTheme.eyebrow),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: AppTheme.blue3,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    footnote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- capacity

  Widget _capacitySection() {
    final center = _center!;

    return AdminSection(
      title: 'Center Capacity',
      subtitle:
          'The number of dialysis machines at this center. Per-shift '
          'capacity is set with each shift below.',
      icon: Icons.medical_services_rounded,
      accent: AppTheme.accentTeal,
      accentSoft: AppTheme.accentTealSoft,
      child: _editing
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  child: _labelledField(
                    label: 'Dialysis machines',
                    required: true,
                    child: TextField(
                      controller: _machinesController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      style: AppTheme.fieldTextStyle,
                      decoration: AppTheme.field(hintText: 'e.g. 10'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 26),
                    child: Text(
                      'Whole numbers only, from 0 to 500. A shift can never '
                      'be given a capacity larger than this, since one '
                      'machine treats one patient per shift.',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : _readOnlyRow([
              ('Dialysis machines', center.machines.toString()),
              ('Super Admin slot estimate', center.availableSlots.toString()),
              if (center.targetDailyCapacity != null)
                ('Daily capacity cap', '${center.targetDailyCapacity}'),
            ]),
    );
  }

  // ------------------------------------------------------------- hours

  Widget _hoursSection() {
    final center = _center!;

    return AdminSection(
      title: 'Operating Hours',
      subtitle:
          'When the center is open. Shown to patients in the CureNurture '
          'mobile app.',
      icon: Icons.schedule_rounded,
      accent: AppTheme.accentOrange,
      accentSoft: AppTheme.accentOrangeSoft,
      child: !_editing
          ? _readOnlyRow([
              (
                'Hours',
                center.operatingHours.trim().isEmpty
                    ? 'Not set'
                    : center.operatingHours,
              ),
              (
                'Operating days',
                _operatingDays.isEmpty ? 'Not set' : _operatingDays.join(', '),
              ),
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hoursWereFreeText) ...[
                  _hint(
                    'The stored hours ("$_originalHoursText") are not in a '
                    'time format this page can read. Saving will replace '
                    'them with the times below.',
                    icon: Icons.info_outline_rounded,
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _labelledField(
                        label: 'Opening time',
                        required: true,
                        child: _timeField(
                          value: _openTime,
                          onPick: (time) => setState(() => _openTime = time),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _labelledField(
                        label: 'Closing time',
                        required: true,
                        child: _timeField(
                          value: _closeTime,
                          onPick: (time) => setState(() => _closeTime = time),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Saved as "${_openTime == null || _closeTime == null ? '--' : AdminValidators.formatRange(_openTime!, _closeTime!)}". '
                  'Operating days stay where they are set today, on the '
                  'schedule configuration.',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }

  // ------------------------------------------------------------ shifts

  Widget _shiftsSection() {
    return AdminSection(
      title: 'Shift Schedule',
      subtitle:
          'The center\'s AM and PM dialysis shifts. Set each one\'s start '
          'and end time here; the AM/PM codes the daily schedule runs on '
          'are not editable.',
      icon: Icons.swap_horiz_rounded,
      accent: AppTheme.blue1,
      accentSoft: AppTheme.accentBlueSoft,
      // In edit mode the drafts drive the list, not the stored rows, so
      // a center with no `clinic_shifts` rows still gets an empty AM and
      // PM editor to fill in. Read-only still shows only what is
      // actually stored.
      child: _editing
          ? Column(
              children: [
                for (var i = 0; i < _shiftDrafts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _shiftEditor(_shiftDrafts[i]),
                ],
              ],
            )
          : (_shifts.isEmpty
                ? _hint(
                    'No shifts are configured for this center yet. Choose '
                    '"Edit profile" and set the AM and PM shift times — '
                    'patients cannot be given a recurring schedule until '
                    'at least one shift exists.',
                    icon: Icons.warning_amber_rounded,
                  )
                : Column(
                    children: [
                      for (var i = 0; i < _shifts.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _shiftReadOnly(_shifts[i]),
                      ],
                    ],
                  )),
    );
  }

  Widget _shiftReadOnly(ClinicShift shift) {
    final peak = _peakScheduled(shift.id);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          AdminPill(
            label: shift.shiftCode,
            color: AppTheme.blue1,
            background: AppTheme.accentBlueSoft,
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shift.displayLabel,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatStoredRange(shift.startTime, shift.endTime),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _miniStat('Capacity', shift.capacity.toString()),
          ),
          Expanded(flex: 2, child: _miniStat('Busiest day', '$peak scheduled')),
          AdminPill(
            label: shift.isActive ? 'Active' : 'Inactive',
            color: shift.isActive ? AppTheme.accentGreen : AppTheme.textMuted,
            background: shift.isActive
                ? AppTheme.accentGreenSoft
                : AppTheme.surface,
          ),
        ],
      ),
    );
  }

  Widget _shiftEditor(_ShiftDraft draft) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              AdminPill(
                label: '${draft.shiftCode} Shift',
                color: AppTheme.blue1,
                background: AppTheme.accentBlueSoft,
              ),
              if (draft.shift == null) ...[
                const SizedBox(width: 8),
                const AdminPill(
                  label: 'Not set up yet',
                  color: AppTheme.textMuted,
                  background: AppTheme.surface,
                ),
              ],
              const Spacer(),
              Text(
                draft.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: draft.isActive
                      ? AppTheme.accentGreen
                      : AppTheme.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: draft.isActive,
                onChanged: (value) => setState(() => draft.isActive = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 220,
                child: _labelledField(
                  label: 'Shift name',
                  child: TextField(
                    controller: draft.labelController,
                    maxLength: 40,
                    style: AppTheme.fieldTextStyle,
                    decoration: AppTheme.field(
                      hintText: draft.shiftCode == 'AM'
                          ? 'Morning'
                          : 'Afternoon',
                      dense: true,
                    ).copyWith(counterText: ''),
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: _labelledField(
                  label: 'Start time',
                  required: true,
                  child: _timeField(
                    value: draft.start,
                    dense: true,
                    onPick: (time) => setState(() => draft.start = time),
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: _labelledField(
                  label: 'End time',
                  required: true,
                  child: _timeField(
                    value: draft.end,
                    dense: true,
                    onPick: (time) => setState(() => draft.end = time),
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: _labelledField(
                  label: 'Capacity',
                  required: true,
                  child: TextField(
                    controller: draft.capacityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    style: AppTheme.fieldTextStyle,
                    decoration: AppTheme.field(hintText: '0', dense: true),
                  ),
                ),
              ),
            ],
          ),
          // Says plainly that leaving this one blank is allowed, so the
          // required-field asterisks above do not read as "you must fill
          // this in before you can save anything".
          if (draft.shift == null) ...[
            const SizedBox(height: 10),
            Text(
              'This shift has not been set up for the center yet. Pick a '
              'start and end time to create it, or leave both blank to '
              'set it up later.',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: AppTheme.eyebrow),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatStoredRange(String start, String end) {
    final parsedStart = AdminValidators.parseTime(start);
    final parsedEnd = AdminValidators.parseTime(end);

    if (parsedStart == null || parsedEnd == null) return '$start - $end';
    return AdminValidators.formatRange(parsedStart, parsedEnd);
  }

  // ------------------------------------------------------ requirements

  Widget _requirementsSection() {
    final center = _center!;

    return AdminSection(
      title: 'Center Requirements',
      subtitle:
          'What a patient must bring when applying to this center. Shown '
          'to patients in the mobile app.',
      icon: Icons.fact_check_rounded,
      accent: AppTheme.accentPurple,
      accentSoft: AppTheme.accentPurpleSoft,
      child: !_editing
          ? (center.requirements.isEmpty
                ? _hint(
                    'No requirements have been set for this center yet.',
                    icon: Icons.info_outline_rounded,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final requirement in center.requirements)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 17,
                                color: AppTheme.accentGreen,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  requirement,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tick the documents patients must bring. Requirements '
                  'already set for this center are ticked.',
                  style: AppTheme.sectionSubtitle,
                ),
                const SizedBox(height: 12),
                for (final option in kCommonCenterRequirements)
                  _requirementCheckbox(option),
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppTheme.border),
                const SizedBox(height: 14),
                const Text('Custom requirements', style: AppTheme.fieldLabel),
                const SizedBox(height: 4),
                Text(
                  'Anything not on the standard list. Existing custom '
                  'requirements are kept exactly as they were saved.',
                  style: AppTheme.sectionSubtitle,
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < _customRequirements.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customRequirements[i],
                            maxLength: _customRequirementLimit,
                            style: AppTheme.fieldTextStyle,
                            decoration: AppTheme.field(
                              hintText: 'Enter a requirement',
                              dense: true,
                            ).copyWith(counterText: ''),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () => _removeCustomRequirement(i),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('Remove'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(color: AppTheme.dangerSoft),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.rMd),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _addCustomRequirement,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Add Requirement'),
                    style: AppTheme.secondaryButton(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _requirementCheckbox(String label) {
    final checked = _selectedRequirements[label] ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        onTap: () => setState(() => _selectedRequirements[label] = !checked),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                onChanged: (value) => setState(
                  () => _selectedRequirements[label] = value ?? false,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: checked
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------- house rules

  Widget _houseRulesSection() {
    final center = _center!;

    return AdminSection(
      title: 'House Rules',
      subtitle:
          'The center\'s own rules for patients and visitors. One free-form '
          'block of text.',
      icon: Icons.rule_rounded,
      accent: AppTheme.accentGreen,
      accentSoft: AppTheme.accentGreenSoft,
      child: _editing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _houseRulesController,
                  minLines: 8,
                  maxLines: 18,
                  maxLength: _houseRulesLimit,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTheme.fieldTextStyle.copyWith(height: 1.6),
                  decoration: AppTheme.field(
                    hintText: 'Enter the center\'s house rules here...',
                  ).copyWith(alignLabelWithHint: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_houseRulesController.text.characters.length} / '
                  '$_houseRulesLimit characters',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            )
          : (center.hasHouseRules
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceTint,
                      borderRadius: BorderRadius.circular(AppTheme.rLg),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      center.houseRules,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.65,
                      ),
                    ),
                  )
                : _hint(
                    'No house rules have been written yet. Use Edit Center '
                    'Profile to add them.',
                    icon: Icons.info_outline_rounded,
                  )),
    );
  }

  // -------------------------------------------------- donation placeholder

  /// Reserved space only.
  ///
  /// Nothing here reads, writes or influences a donation. The existing
  /// donation flow (donations, donation_allocations, fund_distributions
  /// and the Dashboard's donation card) is untouched by this page; this
  /// section exists so the bank details feature has an agreed home when
  /// it is built.
  Widget _donationPlaceholder() {
    return AdminSection(
      title: 'Donation Receiving Information',
      subtitle: 'Bank information for receiving donations.',
      icon: Icons.account_balance_rounded,
      accent: AppTheme.accentPink,
      accentSoft: AppTheme.accentPinkSoft,
      trailing: const AdminPill(
        label: 'Coming Soon',
        color: AppTheme.accentPink,
        background: AppTheme.accentPinkSoft,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
        decoration: BoxDecoration(
          color: AppTheme.surfaceTint,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: AppTheme.iconBox(
                AppTheme.accentPinkSoft,
                radius: AppTheme.rLg,
              ),
              child: const Icon(
                Icons.savings_rounded,
                color: AppTheme.accentPink,
                size: 23,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Bank details for receiving donations will live here',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.blue3,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This section is reserved for a future enhancement. Donations '
              'continue to work exactly as they do today and are not '
              'affected by anything on this page.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- helpers

  Widget _readOnlyRow(List<(String, String)> entries) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in entries)
          Container(
            constraints: const BoxConstraints(minWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceTint,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.$1.toUpperCase(), style: AppTheme.eyebrow),
                const SizedBox(height: 4),
                Text(
                  entry.$2,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _labelledField({
    required String label,
    required Widget child,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(label, style: AppTheme.fieldLabel),
            if (required) ...[
              const SizedBox(width: 3),
              const Text(
                '*',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }

  /// A field-shaped button that opens the platform time picker. Typing a
  /// time by hand is what produced most of the invalid values this page
  /// has to guard against, so the picker is the only way in.
  Widget _timeField({
    required TimeOfDay? value,
    required ValueChanged<TimeOfDay> onPick,
    bool dense = false,
  }) {
    return Material(
      color: AppTheme.surfaceTint,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        hoverColor: AppTheme.accentSoft,
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: value ?? const TimeOfDay(hour: 8, minute: 0),
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          height: dense ? 44 : 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 17,
                color: AppTheme.iconMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value == null
                      ? 'Set a time'
                      : AdminValidators.formatTime(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: value == null
                        ? AppTheme.textMuted
                        : AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: AppTheme.iconMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(String message, {required IconData icon}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accentBlueSoft,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppTheme.blue1),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One shift's in-progress edits.
///
/// Held separately from the loaded [ClinicShift] so Cancel restores the
/// stored row exactly, and so [isDirty] can skip writing a shift nobody
/// touched.
///
/// [shift] is null for a center whose AM or PM row does not exist in
/// `clinic_shifts` yet (see [_ShiftDraft.blank]). Such a draft starts
/// with no times at all and, while it stays that way, is neither
/// validated nor written -- an unconfigured shift is a valid state for a
/// newly created center, not an error to nag the admin about.
class _ShiftDraft {
  /// The stored row this draft edits, or null when the shift has never
  /// been created for this center.
  final ClinicShift? shift;

  /// 'AM' or 'PM'. Read from [shift] when there is one, and otherwise
  /// the code the row will be created with -- so the rest of the page
  /// can name the shift without caring whether it exists yet.
  final String shiftCode;

  final TextEditingController labelController;
  final TextEditingController capacityController;
  TimeOfDay? start;
  TimeOfDay? end;
  bool isActive;

  final String _originalLabel;
  final String _originalCapacity;
  final TimeOfDay? _originalStart;
  final TimeOfDay? _originalEnd;
  final bool _originalActive;

  _ShiftDraft._({
    required this.shift,
    required this.shiftCode,
    required this.labelController,
    required this.capacityController,
    required this.start,
    required this.end,
    required this.isActive,
    required String originalLabel,
    required String originalCapacity,
    required TimeOfDay? originalStart,
    required TimeOfDay? originalEnd,
    required bool originalActive,
  }) : _originalLabel = originalLabel,
       _originalCapacity = originalCapacity,
       _originalStart = originalStart,
       _originalEnd = originalEnd,
       _originalActive = originalActive;

  factory _ShiftDraft.from(ClinicShift shift) {
    final label = shift.shiftLabel;
    final capacity = shift.capacity.toString();
    final start = AdminValidators.parseTime(shift.startTime);
    final end = AdminValidators.parseTime(shift.endTime);

    return _ShiftDraft._(
      shift: shift,
      shiftCode: shift.shiftCode,
      labelController: TextEditingController(text: label),
      capacityController: TextEditingController(text: capacity),
      start: start,
      end: end,
      isActive: shift.isActive,
      originalLabel: label,
      originalCapacity: capacity,
      originalStart: start,
      originalEnd: end,
      originalActive: shift.isActive,
    );
  }

  /// A shift this center has never configured.
  ///
  /// Both times start null, which is what renders the AM/PM fields empty
  /// and what [isUnconfigured] reads to leave the shift alone. Capacity
  /// is pre-filled with the center's machine count -- the exact starting
  /// value center_scheduling_foundation.sql seeds an existing clinic's
  /// shifts with -- so the admin only has to pick the two times.
  factory _ShiftDraft.blank({
    required String shiftCode,
    required int machines,
  }) {
    final capacity = machines.toString();

    return _ShiftDraft._(
      shift: null,
      shiftCode: shiftCode,
      labelController: TextEditingController(),
      capacityController: TextEditingController(text: capacity),
      start: null,
      end: null,
      isActive: true,
      originalLabel: '',
      originalCapacity: capacity,
      originalStart: null,
      originalEnd: null,
      originalActive: true,
    );
  }

  /// True while this is a shift that does not exist in the database and
  /// the admin has not begun configuring it -- no times picked and no
  /// name typed. Capacity is deliberately not part of the test: a blank
  /// draft pre-fills it, so counting it would make an untouched shift
  /// look configured.
  ///
  /// An unconfigured shift is skipped by validation and never written,
  /// which is what keeps "empty AM + empty PM" a valid state for a newly
  /// created center instead of a form error.
  bool get isUnconfigured {
    return shift == null &&
        start == null &&
        end == null &&
        labelController.text.trim().isEmpty;
  }

  bool get isDirty {
    return labelController.text != _originalLabel ||
        capacityController.text != _originalCapacity ||
        start != _originalStart ||
        end != _originalEnd ||
        isActive != _originalActive;
  }

  void dispose() {
    labelController.dispose();
    capacityController.dispose();
  }
}
