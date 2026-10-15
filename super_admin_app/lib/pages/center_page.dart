import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/center_model.dart';
import '../services/dashboard_service.dart';
import '../config/supabase_config.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/center_capacity.dart';
import '../utils/center_capacity_input.dart';
import '../utils/center_requirements.dart';
import '../utils/center_status.dart';
import '../utils/form_dirty_state.dart';
import '../utils/operating_hours.dart';
import '../utils/ph_contact_number.dart';
import '../widgets/center_details_dialog.dart';
import '../widgets/center_status_badges.dart';
import '../widgets/super_admin_notice.dart';
import 'dart:ui';


/// Validates a Machines/Available Slots entry: must be a whole, non-negative
/// number. Returns null when valid, or a user-facing message otherwise --
/// used so invalid input is rejected instead of silently becoming 0.
String? _validateWholeNumberField(String value) {
  final parsed = double.tryParse(value);

  if (parsed == null) {
    return 'Please enter a valid number';
  }

  if (parsed != parsed.truncateToDouble()) {
    return 'Please enter a whole number';
  }

  if (parsed < 0) {
    return 'Value cannot be negative';
  }

  return null;
}

/// The fixed list of common dialysis center requirements shown as checkboxes
/// in the Add/Edit Center form. Anything a stored center's requirements list
/// contains that isn't exactly one of these is treated as an "Other
/// Requirement" instead of being discarded.
const List<String> _commonRequirementOptions = [
  'Latest Laboratory Results',
  'Latest Hepatitis Profile',
  'Copy of 3 Consecutive HD Treatments',
  'Referral/Endorsement Letter from Nephrologist',
  'Latest Medical Abstract',
  'Updated Philhealth MDR',
  'PDD Certification',
  'PHIC Consumption',
  'Photocopy of Government-Issued ID',
  '1×1 Picture',
];

/// The Centres page's status filter. Availability (Open/Closed, from the
/// operating hours) and record status (Active/Inactive) are separate
/// concepts, so each option matches exactly one of them -- the same values
/// the table's two status badges show. Busy and Full no longer exist.
enum _CenterStatusFilter {
  open('Open'),
  closed('Closed'),
  active('Active'),
  inactive('Inactive');

  const _CenterStatusFilter(this.label);

  final String label;

  bool matches(CenterModel clinic) => switch (this) {
    _CenterStatusFilter.open =>
      clinic.availability() == CenterAvailability.open,
    _CenterStatusFilter.closed =>
      clinic.availability() == CenterAvailability.closed,
    _CenterStatusFilter.active => clinic.isActive,
    _CenterStatusFilter.inactive => !clinic.isActive,
  };
}

/// User-controlled sort options for the centers table. Sorting only reorders
/// the already-loaded/filtered list -- it never changes the database query.
enum _CenterSortOption {
  newestFirst('Newest First'),
  oldestFirst('Oldest First'),
  nameAsc('Center Name A–Z'),
  nameDesc('Center Name Z–A'),
  mostSlots('Most Available Slots'),
  fewestSlots('Fewest Available Slots');

  const _CenterSortOption(this.label);

  final String label;
}

class ClinicsPage extends StatefulWidget {
  final VoidCallback? onUpdated;

  const ClinicsPage({super.key, this.onUpdated});

  @override
  State<ClinicsPage> createState() => _ClinicsPageState();
}

class _ClinicsPageState extends State<ClinicsPage> {
  final DashboardService _service = DashboardService();

  bool _isLoading = true;
  List<CenterModel> _clinics = [];
  String _searchText = '';

  // Super Admin capacity ESTIMATE (see DashboardService
  // .getReservedPatientCount/.calculateAvailableSlotsEstimate) -- keyed by
  // clinic id, fetched once per _loadClinics() call alongside the centers
  // themselves, never refetched on a rebuild. A missing entry means still
  // loading; a null value means that clinic's patient-count query failed
  // (never treated as 0 reserved, which would wrongly look like full
  // capacity).
  Map<String, int?> _reservedCounts = {};

  // Center management filters/sort -- all client-side, applied on top of the
  // already-loaded _clinics list. null sentinels mean "All Statuses"/
  // "All Cities" respectively.
  _CenterStatusFilter? _statusFilter;
  String? _cityFilter;
  _CenterSortOption _sortOption = _CenterSortOption.newestFirst;

  static const Color pageBg = Color(0xFFF4F8FB);

  @override
  void initState() {
    super.initState();
    _loadClinics();
  }

  Future<void> _loadClinics() async {
    setState(() => _isLoading = true);

    try {
      // Active AND inactive centres: inactive ones stay listed (with their
      // status) so they can be reactivated.
      final clinics = await _service.fetchAllCenters();
      clinics.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Reserved/accepted patient headcount per clinic, for the Super
      // Admin capacity ESTIMATE only -- fetched once here, alongside the
      // centers themselves, never on every rebuild. Each clinic's query is
      // isolated in its own try/catch so one clinic failing doesn't lose
      // every other clinic's count, or fail the centers list itself; a
      // failure is recorded as null (unknown), never silently treated as 0
      // reserved, which would wrongly look like full capacity.
      final reservedCounts = <String, int?>{};
      await Future.wait(
        clinics.map((clinic) async {
          try {
            reservedCounts[clinic.id] = await _service.getReservedPatientCount(
              clinic.id,
            );
          } catch (_) {
            reservedCounts[clinic.id] = null;
          }
        }),
      );

      if (!mounted) return;

      setState(() {
        _clinics = clinics;
        _reservedCounts = reservedCounts;

        // If the previously selected city no longer exists in the freshly
        // loaded data (e.g. its last center was soft-closed or otherwise
        // dropped), fall back to "All Cities" instead of leaving the
        // dropdown pointed at a value absent from its items list.
        final cityFilter = _cityFilter;
        if (cityFilter != null &&
            !clinics.any((clinic) => clinic.city == cityFilter)) {
          _cityFilter = null;
        }
      });
    } catch (error) {
      if (!mounted) return;

      SuperAdminNotice.error(context, 'Failed to load centers: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Search -> Status filter -> City filter -> Sort, applied in that order on
  /// top of the already-loaded _clinics list. Nothing here touches the
  /// database query or _clinics itself, so the stat cards (which read
  /// _clinics directly) are unaffected.
  List<CenterModel> get _filteredClinics {
    Iterable<CenterModel> result = _clinics;

    final query = _searchText.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((clinic) {
        return clinic.name.toLowerCase().contains(query) ||
            clinic.address.toLowerCase().contains(query) ||
            clinic.city.toLowerCase().contains(query) ||
            clinic.contactNumber.toLowerCase().contains(query);
      });
    }

    final statusFilter = _statusFilter;
    if (statusFilter != null) {
      // Matches the same values the table's status badges display.
      result = result.where(statusFilter.matches);
    }

    final cityFilter = _cityFilter;
    if (cityFilter != null) {
      result = result.where((clinic) => clinic.city == cityFilter);
    }

    final sorted = result.toList();

    switch (_sortOption) {
      case _CenterSortOption.newestFirst:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _CenterSortOption.oldestFirst:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _CenterSortOption.nameAsc:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _CenterSortOption.nameDesc:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
      case _CenterSortOption.mostSlots:
        sorted.sort((a, b) => b.availableSlots.compareTo(a.availableSlots));
      case _CenterSortOption.fewestSlots:
        sorted.sort((a, b) => a.availableSlots.compareTo(b.availableSlots));
    }

    return sorted;
  }

  /// Unique, non-empty city names from the loaded center list, sorted
  /// alphabetically -- generated from data, never hardcoded.
  ///
  /// The All Cities dropdown was removed from the Centers UI, but the
  /// city-filter capability itself is deliberately kept intact (this getter,
  /// [_cityFilter], and the filter step in [_filteredClinics]) so nothing
  /// downstream loses the ability to filter by city.
  // ignore: unused_element
  List<String> get _availableCities {
    final cities = _clinics
        .map((clinic) => clinic.city.trim())
        .where((city) => city.isNotEmpty)
        .toSet()
        .toList();

    cities.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return cities;
  }

  /// This clinic's Super Admin capacity ESTIMATE, derived from the
  /// already-loaded _reservedCounts (see _loadClinics -- fetched once per
  /// load/refresh, never here). Pure arithmetic on already-fetched data,
  /// so it's safe to recompute on every build; nothing here performs a
  /// network call. Stays associated with the right clinic via clinic.id
  /// regardless of the list's current search/filter/sort order.
  _CapacityEstimate _capacityEstimateFor(CenterModel clinic) {
    // Machines × this centre's saved shifts (same formula as the modal).
    final totalCapacity = clinic.totalCapacity;
    final reserved = _reservedCounts[clinic.id];

    if (reserved == null) {
      return _CapacityEstimate(
        totalCapacity: totalCapacity,
        reserved: null,
        available: null,
      );
    }

    return _CapacityEstimate(
      totalCapacity: totalCapacity,
      reserved: reserved,
      available: _service.calculateAvailableSlotsEstimate(
        machines: clinic.machines,
        shifts: clinic.shifts,
        reservedPatients: reserved,
      ),
    );
  }

  bool get _hasActiveCenterFilters =>
      _searchText.trim().isNotEmpty ||
      _statusFilter != null ||
      _cityFilter != null ||
      _sortOption != _CenterSortOption.newestFirst;

  void _clearCenterFilters() {
    setState(() {
      _searchText = '';
      _statusFilter = null;
      _cityFilter = null;
      _sortOption = _CenterSortOption.newestFirst;
    });
  }

  /// Trimmed, lower-cased names of the currently loaded ACTIVE centres,
  /// excluding [excluding] -- the centre being edited, so re-saving it under
  /// its own unchanged name is never blocked.
  ///
  /// Inactive centres are deliberately excluded (the list now holds them
  /// too), so a new centre may still reuse an inactive historical centre's
  /// name. Only a duplicate ACTIVE name is prevented.
  ///
  /// This is a client-side check against the list this page has already
  /// loaded. It cannot see a centre created concurrently in another session
  /// or browser tab -- that would need a database constraint or a
  /// server-side create, neither of which is in scope here.
  Set<String> _activeCenterNamesExcluding(CenterModel? excluding) {
    return _clinics
        .where((clinic) => clinic.isActive && clinic.id != excluding?.id)
        .map((clinic) => clinic.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<void> _showClinicDialog([CenterModel? clinic]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) => _ClinicFormDialog(
        clinic: clinic,
        existingCenterNames: _activeCenterNamesExcluding(clinic),
      ),
    );

    if (saved != true) return;

    await _loadClinics();
    widget.onUpdated?.call();

    if (!mounted) return;

    SuperAdminNotice.success(
      context,
      clinic == null
          ? 'Center created successfully.'
          : 'Center updated successfully.',
    );
  }

  /// How many active admin accounts are assigned to [clinic], for the
  /// deactivation confirmation. Null when the count could not be read.
  Future<int?> _assignedAdminCount(CenterModel clinic) async {
    try {
      final rows = await SupabaseConfig.client
          .from('profiles')
          .select('id')
          .eq('clinic_id', clinic.id)
          .eq('role', 'admin')
          .eq('status', 'active');
      return rows.length;
    } catch (_) {
      return null;
    }
  }

  /// Marks [clinic] Inactive (when [activate] is false) or Active again.
  ///
  /// Replaces the old "Delete center" action, which hid the centre for good
  /// and set every assigned admin inactive. Now ONLY `clinics.status`
  /// changes: the centre record, its donations, patients, audit history and
  /// admin accounts are left exactly as they are, and the centre stays
  /// listed here so it can be reactivated.
  Future<void> _setCenterActive(
    CenterModel clinic, {
    required bool activate,
  }) async {
    final adminCount = activate ? null : await _assignedAdminCount(clinic);
    if (!mounted) return;

    final adminNote = switch (adminCount) {
      null => '',
      0 => ' No admin account is assigned to it.',
      1 =>
        ' 1 admin account is assigned to it; that account is not changed '
            '-- manage it from Account Management if needed.',
      _ =>
        ' $adminCount admin accounts are assigned to it; those accounts are '
            'not changed -- manage them from Account Management if needed.',
    };

    // A warning notice rather than a dialog of its own, so the question is
    // raised into the root overlay and an outside click cannot answer it.
    final confirmed = await SuperAdminNotice.confirm(
      context,
      title: activate ? 'Reactivate center?' : 'Deactivate center?',
      message: activate
          ? '${clinic.name} will be marked Active again and can be assigned '
                'a clinic admin and shown in operational views.'
          : '${clinic.name} will be marked Inactive. It stays in this list '
                'with all of its history, is hidden from the dashboard, and '
                'cannot be chosen for new admin assignments.$adminNote',
      confirmLabel: activate ? 'Reactivate' : 'Deactivate',
      destructive: !activate,
      icon: activate ? Icons.restart_alt_rounded : Icons.block_rounded,
    );

    if (!confirmed || !mounted) return;

    try {
      await _service.setCenterRecordStatus(
        centerId: clinic.id,
        status: activate
            ? CenterRecordStatus.active
            : CenterRecordStatus.inactive,
      );

      await ProfileService().logAction(
        action: activate ? 'reactivate_clinic' : 'deactivate_clinic',
        targetId: clinic.id,
        targetName: clinic.name,
      );

      if (!mounted) return;

      await _loadClinics();
      widget.onUpdated?.call();

      if (!mounted) return;

      SuperAdminNotice.success(
        context,
        activate
            ? '${clinic.name} is Active again.'
            : '${clinic.name} is now Inactive.',
      );
    } catch (error) {
      if (!mounted) return;

      SuperAdminNotice.error(
        context,
        'Unable to ${activate ? 'reactivate' : 'deactivate'} center: $error',
      );
    }
  }

  void _showCenterDetails(CenterModel clinic) {
    final estimate = _capacityEstimateFor(clinic);
    showCenterDetailsDialog(
      context,
      clinic,
      reservedPatients: estimate.reserved,
      estimatedAvailable: estimate.available,
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinics = _filteredClinics;
    // The stat cards describe the operational network, so they count Active
    // centres only; inactive ones are listed below but not counted here.
    final activeClinics = _clinics.where((clinic) => clinic.isActive).toList();
    final inactiveCount = _clinics.length - activeClinics.length;
    final openCount = activeClinics
        .where((clinic) => clinic.availability() == CenterAvailability.open)
        .length;
    final totalSlots = activeClinics.fold<int>(
      0,
      (sum, clinic) => sum + clinic.availableSlots,
    );
    final totalMachines = activeClinics.fold<int>(
      0,
      (sum, clinic) => sum + clinic.machines,
    );

    final pagePadding = AppTheme.pagePadding(
      MediaQuery.of(context).size.width,
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: pageBg,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        // Padding lives inside the scroll view so the scrollbar sits on the
        // viewport edge rather than floating inside the content.
        padding: EdgeInsets.all(pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 18 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _HeaderCard(onAdd: () => _showClinicDialog()),
            ),

            const SizedBox(height: 22),

            LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxWidth < 850;

                final cards = [
                  _DashboardStatCard(
                    icon: Icons.business_rounded,
                    label: 'Active Centers',
                    value: activeClinics.length.toString(),
                    description: inactiveCount == 0
                        ? 'Registered dialysis centers'
                        : '$inactiveCount inactive not counted',
                  ),

                  _DashboardStatCard(
                    icon: Icons.schedule_rounded,
                    // Active centres whose availability is Open right now
                    // (inside their operating hours) -- the same value the
                    // table's Open/Closed badge shows.
                    label: 'Open Now',
                    value: openCount.toString(),
                    description: 'Currently within operating hours',
                    accent: AppTheme.accentGreen,
                    accentSoft: AppTheme.accentGreenSoft,
                  ),

                  _DashboardStatCard(
                    icon: Icons.event_available_rounded,
                    label: 'Available Slots',
                    value: totalSlots.toString(),
                    description: 'Total remaining capacity',
                    accent: AppTheme.accentOrange,
                    accentSoft: AppTheme.accentOrangeSoft,
                  ),

                  _DashboardStatCard(
                    icon: Icons.precision_manufacturing_rounded,
                    label: 'Machines',
                    value: totalMachines.toString(),
                    description: 'Total available machines',
                    accent: AppTheme.accentTeal,
                    accentSoft: AppTheme.accentTealSoft,
                  ),
                ];

                if (isSmall) {
                  return Column(
                    children: cards.asMap().entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: cardWithDelay(entry.value, entry.key),
                      );
                    }).toList(),
                  );
                }

                return Row(
                  children: cards.asMap().entries.map((entry) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: entry.key == cards.length - 1 ? 0 : 12,
                        ),
                        child: cardWithDelay(entry.value, entry.key),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: AppTheme.gapLg),

            // Search/filters and the centers list share one surface so the
            // page reads as a single working area rather than two stacked
            // cards.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _CentersPanel(
                searchText: _searchText,
                onSearchChanged: (value) {
                  setState(() => _searchText = value);
                },
                onRefresh: _loadClinics,
                statusFilter: _statusFilter,
                onStatusChanged: (value) {
                  setState(() => _statusFilter = value);
                },
                sortOption: _sortOption,
                onSortChanged: (value) {
                  setState(() => _sortOption = value);
                },
                hasActiveFilters: _hasActiveCenterFilters,
                onClearFilters: _clearCenterFilters,
                isLoading: _isLoading,
                clinics: clinics,
                // Centers exist but none match the current search/filters,
                // vs. there being no centers at all -- different situations
                // with different messaging and a different call to action.
                hasAnyCenters: _clinics.isNotEmpty,
                onAdd: () => _showClinicDialog(),
                onEdit: _showClinicDialog,
                onView: _showCenterDetails,
                onSetActive: (clinic, activate) =>
                    _setCenterActive(clinic, activate: activate),
                capacityEstimateFor: _capacityEstimateFor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget cardWithDelay(Widget card, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + (index * 80)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: card,
    );
  }

}

/// The Add/Edit Center dialog's own content and local state (form fields,
/// map selection, save-in-progress flag). This is its own StatefulWidget --
/// rather than a StatefulBuilder living inside _showClinicDialog -- so its
/// TextEditingControllers are disposed by the framework's own
/// State.dispose(), at the moment this widget is actually, finally removed
/// from the tree (i.e. once the dialog's exit transition has completed),
/// instead of being disposed manually as soon as `await showDialog(...)`
/// returns in the caller -- which can happen *before* the exit transition's
/// last frame has rendered. That premature-disposal race was the root cause
/// of the "TextEditingController used after being disposed" crash: the
/// dialog was still finishing its close animation (so Flutter could still
/// rebuild/repaint its TextFormFields) after _showClinicDialog had already
/// disposed the very controllers those fields read from.
class _ClinicFormDialog extends StatefulWidget {
  final CenterModel? clinic;

  /// Trimmed, lower-cased names of the other ACTIVE centres, used only to
  /// reject an accidental duplicate active name (see the Center Name
  /// field's validator). Closed centres are not in this set, so a name may
  /// still be reused after its centre has been soft-closed.
  final Set<String> existingCenterNames;

  const _ClinicFormDialog({
    required this.clinic,
    required this.existingCenterNames,
  });

  @override
  State<_ClinicFormDialog> createState() => _ClinicFormDialogState();
}

class _ClinicFormDialogState extends State<_ClinicFormDialog> {
  final DashboardService _service = DashboardService();
  final formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;
  late final TextEditingController addressController;
  late final TextEditingController cityController;
  late final TextEditingController machinesController;
  // Add: editable. Pre-filled as Machines × Shifts until the Super Admin
  // types their own value, which is then never overwritten (see
  // _recalculateAvailableSlots). Edit: read-only, as before.
  late final TextEditingController slotsController;
  // Add: editable, starting at 2. Edit: read-only, showing the centre's
  // saved shift count, which is saved back unchanged.
  late final TextEditingController shiftsController;

  /// True once the Super Admin has typed into Available Slots on Add, so a
  /// later Machines/Shifts change no longer replaces their value.
  bool _slotsEditedByUser = false;

  /// Set while the form itself writes slotsController, so that write is not
  /// mistaken for the Super Admin's own edit.
  bool _updatingSlots = false;

  // Operating hours come from two time pickers and are saved in the existing
  // `7:00 AM - 5:00 PM` text form. A stored value the parser cannot read is
  // kept in _legacyHours and saved back untouched unless new times are
  // picked, so an existing record is never broken by opening Edit.
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  String? _legacyHours;
  String? _hoursError;

  // Holds only the 10 digits after the fixed +63 prefix.
  late final TextEditingController contactController;

  // A stored contact number that is not a recognisable PH mobile number
  // (e.g. a landline or "N/A"); shown so the Super Admin can re-enter it.
  String? _legacyContact;

  /// Field values as they were when the form opened, for the "unsaved
  /// changes" checks (see hasFormChanges).
  late final Map<String, Object?> _originalValues;

  // Requirements: a fixed checkbox list plus free-form "Other Requirements"
  // entries, instead of one free-text field. Selected/typed values are
  // still joined into a single string and sent through the existing
  // createCenter/updateCenter -> _parseRequirements pipeline unchanged, so
  // the stored format (and the database column) never changes.
  late final Map<String, bool> selectedCommonRequirements;
  late final List<TextEditingController> customRequirementControllers;

  bool isSaving = false;
  bool isFindingLocation = false;

  double? selectedLatitude;
  double? selectedLongitude;

  late final MapController mapController;

  static const Color primary = Color(0xFF0F719F);
  static const Color darkBlue = Color(0xFF0F3A55);
  static const Color mutedText = Color(0xFF647583);

  // CureNurture's current project scope is Valenzuela City only, so City is
  // system-defined rather than typed by the Super Admin. Kept as a plain
  // constant (not a new field/table) -- if that scope ever changes, this is
  // the one place to update.
  static const String _fixedCity = 'Valenzuela City';

  @override
  void initState() {
    super.initState();

    final clinic = widget.clinic;

    nameController = TextEditingController(text: clinic?.name ?? '');
    addressController = TextEditingController(text: clinic?.address ?? '');
    // Add: always the fixed city. Edit: whatever is actually stored for this
    // center, shown as-is -- never silently rewritten to _fixedCity here,
    // even if it happens to differ (that would be a data question for the
    // Super Admin to look into, not something this form should "fix" on its
    // own by opening/saving the dialog).
    cityController = TextEditingController(text: clinic?.city ?? _fixedCity);

    // Add: nothing stored yet, so every common requirement starts
    // unchecked and there are no "Other Requirements" rows. Edit: parse
    // whatever is actually stored -- anything that exactly matches a common
    // option is checked, and everything else is preserved verbatim as an
    // "Other Requirement" row rather than being discarded or forced into a
    // standard label it doesn't actually match.
    final storedRequirements = clinic != null
        ? parseStoredRequirements(clinic.requirements)
        : const <String>[];

    selectedCommonRequirements = {
      for (final option in _commonRequirementOptions)
        option: storedRequirements.contains(option),
    };

    customRequirementControllers = [
      for (final item in storedRequirements)
        if (!_commonRequirementOptions.contains(item))
          TextEditingController(text: item),
    ];

    machinesController = TextEditingController(
      text: clinic?.machines.toString() ?? '0',
    );
    // Add: no center exists yet, so this starts as the full computed
    // capacity for 0 machines (0), same as machinesController's own default.
    // Edit: the center's ACTUAL current available slots, shown as-is --
    // never recomputed from machines just because the dialog opened. It
    // only changes if the Super Admin actually edits Machines during this
    // session (see _recalculateAvailableSlots), which is the one thing
    // that already, unconditionally overwrites this column on Save today
    // regardless of what triggered it.
    slotsController = TextEditingController(
      text: clinic?.availableSlots.toString() ?? '0',
    );
    // Add: 2 shifts per day by default (the value every centre used to be
    // saved with). Edit: the centre's saved shift count.
    shiftsController = TextEditingController(
      text: (clinic?.shifts ?? defaultShiftsPerDay).toString(),
    );
    machinesController.addListener(_recalculateAvailableSlots);
    shiftsController.addListener(_recalculateAvailableSlots);
    slotsController.addListener(() {
      if (!_updatingSlots) _slotsEditedByUser = true;
    });

    final storedHours = clinic?.operatingHours.trim() ?? '';
    final hoursRange = parseOperatingHoursRange(storedHours);
    if (hoursRange != null) {
      _openTime = hoursRange.open;
      _closeTime = hoursRange.close;
    } else if (storedHours.isNotEmpty) {
      _legacyHours = storedHours;
    }

    final storedContact = clinic?.contactNumber.trim() ?? '';
    final localDigits = phLocalDigitsFromStored(storedContact);
    contactController = TextEditingController(text: localDigits ?? '');
    if (localDigits == null && storedContact.isNotEmpty) {
      _legacyContact = storedContact;
    }

    selectedLatitude = clinic?.latitude;
    selectedLongitude = clinic?.longitude;

    mapController = MapController();

    _originalValues = _currentValues();

    // Rebuild on every edit so the Save button follows the dirty state.
    for (final controller in [
      nameController,
      addressController,
      cityController,
      machinesController,
      contactController,
    ]) {
      controller.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  static int? _minutesOf(TimeOfDay? time) =>
      time == null ? null : time.hour * 60 + time.minute;

  /// The values a save would write, in comparable form.
  Map<String, Object?> _currentValues() => {
    'name': nameController.text,
    'address': addressController.text,
    'city': cityController.text,
    'requirements': _buildRequirementsValue(),
    'machines': machinesController.text,
    'shifts': shiftsController.text,
    'slots': slotsController.text,
    'open': _minutesOf(_openTime),
    'close': _minutesOf(_closeTime),
    'contact': contactController.text,
    'latitude': selectedLatitude,
    'longitude': selectedLongitude,
  };

  bool get _isEditing => widget.clinic != null;

  /// True once any value differs from what the form opened with. Changing a
  /// value back to its original makes this false again.
  bool get _hasChanges => hasFormChanges(_originalValues, _currentValues());

  bool get _hoursChanged =>
      _minutesOf(_openTime) != _originalValues['open'] ||
      _minutesOf(_closeTime) != _originalValues['close'];

  /// The `operating_hours` value to save: the picked times, or -- when the
  /// times were not touched on an edit -- exactly what was stored before.
  String _hoursToSave() {
    final open = _openTime;
    final close = _closeTime;
    if (_isEditing && !_hoursChanged) {
      return widget.clinic!.operatingHours.trim();
    }
    return formatOperatingHours(open!, close!);
  }

  /// The `contact_number` value to save: the stored value unchanged when the
  /// digits were not edited, otherwise `+63` followed by the 10 digits.
  String _contactToSave() {
    final digits = contactController.text.trim();
    if (_isEditing && digits == _originalValues['contact']) {
      return widget.clinic!.contactNumber.trim();
    }
    return composePhContactNumber(digits);
  }

  /// Hours validation for Save. Unchanged legacy hours on an edit are
  /// accepted as they are; anything new must be a valid picked pair.
  String? _validateHours() {
    final hadSavedHours =
        _originalValues['open'] != null || _legacyHours != null;
    if (_isEditing && !_hoursChanged && hadSavedHours) return null;
    return validateOperatingTimes(_openTime, _closeTime);
  }

  Future<void> _pickTime({required bool opening}) async {
    final current = opening ? _openTime : _closeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          current ??
          (opening
              ? const TimeOfDay(hour: 7, minute: 0)
              : const TimeOfDay(hour: 17, minute: 0)),
      helpText: opening ? 'Opening time' : 'Closing time',
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (opening) {
        _openTime = picked;
      } else {
        _closeTime = picked;
      }
      _hoursError = null;
    });
  }

  /// Close request from Cancel or the X button. Asks before discarding
  /// unsaved changes; closes straight away when there are none.
  Future<void> _requestClose() async {
    if (isSaving) return;

    if (_hasChanges) {
      final discard = await SuperAdminNotice.confirm(
        context,
        title: 'Discard changes?',
        message: 'Your changes to this center have not been saved.',
        confirmLabel: 'Discard',
        destructive: true,
        icon: Icons.edit_off_rounded,
      );
      if (!discard || !mounted) return;
    }

    Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    cityController.dispose();
    for (final controller in customRequirementControllers) {
      controller.dispose();
    }
    machinesController.removeListener(_recalculateAvailableSlots);
    machinesController.dispose();
    slotsController.dispose();
    shiftsController.dispose();
    contactController.dispose();
    super.dispose();
  }

  void _addCustomRequirement() {
    setState(() {
      customRequirementControllers.add(TextEditingController());
    });
  }

  void _removeCustomRequirement(int index) {
    setState(() {
      final removed = customRequirementControllers.removeAt(index);
      removed.dispose();
    });
  }

  /// Recomputes Available Slots as Machines × Shifts, in place, whenever
  /// Machines (or, on Add, Shifts) is actually edited. Opening Edit never
  /// resets it: the field keeps the centre's stored value until Machines is
  /// changed, exactly as before.
  ///
  /// On Add, once the Super Admin has typed their own Available Slots value
  /// it is kept as entered and never overwritten by this.
  ///
  /// A Machines or Shifts value the validators would reject (blank, "abc",
  /// "1.5", negative) is never used -- the field keeps its last value.
  void _recalculateAvailableSlots() {
    if (_slotsEditedByUser) return;

    final suggested = suggestedAvailableSlots(
      machinesController.text,
      shiftsController.text,
    );
    if (suggested == null) return;

    final next = suggested.toString();
    if (slotsController.text == next) return;

    _updatingSlots = true;
    setState(() => slotsController.text = next);
    _updatingSlots = false;
  }

  /// Builds the single string sent to createCenter/updateCenter, exactly as
  /// _buildTextField's free-text Requirements field used to. Joined with a
  /// newline (one of the separators DashboardService._parseRequirements
  /// already splits on) rather than a comma, so a custom requirement that
  /// itself happens to contain a comma isn't incorrectly split into two
  /// items when it's parsed back out on save.
  String _buildRequirementsValue() {
    final selected = <String>[
      for (final option in _commonRequirementOptions)
        if (selectedCommonRequirements[option] == true) option,
      for (final controller in customRequirementControllers)
        if (controller.text.trim().isNotEmpty) controller.text.trim(),
    ];

    return selected.join('\n');
  }

  Future<void> _searchLocation() async {

      final query = '${addressController.text} ${cityController.text}'.trim();

      if (query.isEmpty) {
        SuperAdminNotice.error(
          context,
          'Please enter an address or city first.',
          title: 'Check this before searching',
        );
        return;
      }

      setState(() => isFindingLocation = true);

      try {
        final url =
            'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1';

        final response = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Flutter App'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data.isNotEmpty) {
            final lat = double.parse(data[0]['lat']);
            final lon = double.parse(data[0]['lon']);

            setState(() {
              selectedLatitude = lat;
              selectedLongitude = lon;
            });

            mapController.move(LatLng(lat, lon), 16);
          } else {
            SuperAdminNotice.info(
              context,
              'No location found. Try a more specific address.',
            );
          }
        }
      } catch (error) {
        SuperAdminNotice.error(context, 'Unable to find location: $error');
      } finally {
        if (mounted) {
          setState(() => isFindingLocation = false);
        }
      }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String trimmedValue)? extraValidator,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      readOnly: readOnly,
      // A read-only field is system-defined, not something the Super Admin
      // fills in -- there is nothing for them to correct if it's ever
      // unexpectedly empty (e.g. an older record), so it's exempt from the
      // usual required-field check rather than silently blocking Save with
      // no way for the user to fix it.
      validator: readOnly
          ? null
          : (value) {
              final trimmed = value?.trim() ?? '';

              if (trimmed.isEmpty) {
                return 'This field is required';
              }

              if (extraValidator != null) {
                return extraValidator(trimmed);
              }

              return null;
            },
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        prefixIcon: Icon(icon, color: primary),
        suffixIcon: readOnly
            ? Icon(Icons.lock_outline_rounded, size: 18, color: mutedText)
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDCEAF1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
        filled: true,
        fillColor: const Color(0xFFF6FBFF),
      ),
    );
  }

  /// Opening and closing time pickers, replacing the old free-text hours
  /// field.
  Widget _buildOperatingHoursPicker() {
    final open = _openTime;
    final close = _closeTime;
    final isOvernight =
        open != null && close != null && _minutesOf(close)! < _minutesOf(open)!;

    Widget timeButton({
      required String label,
      required TimeOfDay? value,
      required bool opening,
    }) {
      return OutlinedButton.icon(
        onPressed: isSaving ? null : () => _pickTime(opening: opening),
        icon: Icon(
          opening ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
          size: 18,
          color: primary,
        ),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            value == null
                ? '$label: select'
                : '$label: ${formatOperatingTime(value)}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: value == null ? mutedText : darkBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: const Color(0xFFF6FBFF),
          side: const BorderSide(color: Color(0xFFDCEAF1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }

    final opening = timeButton(label: 'Opens', value: open, opening: true);
    final closing = timeButton(label: 'Closes', value: close, opening: false);

    final legacy = _legacyHours;
    final error = _hoursError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operating Hours',
          style: TextStyle(
            color: darkBlue,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 420) {
              return Column(
                children: [opening, const SizedBox(height: 10), closing],
              );
            }
            return Row(
              children: [
                Expanded(child: opening),
                const SizedBox(width: 12),
                Expanded(child: closing),
              ],
            );
          },
        ),
        if (legacy != null && !_hoursChanged)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Saved as "$legacy", which cannot be read as times. It is kept '
              'as-is unless you pick new opening and closing times.',
              style: const TextStyle(color: mutedText, fontSize: 12),
            ),
          ),
        if (isOvernight)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Closes the next day (overnight hours).',
              style: TextStyle(color: mutedText, fontSize: 12),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              style: const TextStyle(color: AppTheme.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Contact number with a fixed +63 prefix; only the 10 local digits are
  /// typed.
  Widget _buildContactNumberField() {
    final legacy = _legacyContact;

    return TextFormField(
      controller: contactController,
      keyboardType: TextInputType.phone,
      inputFormatters: const [PhLocalDigitsInputFormatter()],
      validator: (value) => validatePhLocalDigits(value ?? ''),
      decoration: InputDecoration(
        labelText: 'Contact Number',
        hintText: '9171234567',
        helperText: legacy != null
            ? 'Saved as "$legacy" -- enter it as a 10-digit mobile number.'
            : '10-digit mobile number without the leading 0.',
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.phone_rounded, color: primary),
        prefixText: '$phCountryCode ',
        prefixStyle: const TextStyle(
          color: darkBlue,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDCEAF1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
        filled: true,
        fillColor: const Color(0xFFF6FBFF),
      ),
    );
  }

  Widget _buildRequirementCheckbox(String label) {
    final isChecked = selectedCommonRequirements[label] ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          selectedCommonRequirements[label] = !isChecked;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: isChecked,
              activeColor: primary,
              onChanged: (value) {
                setState(() {
                  selectedCommonRequirements[label] = value ?? false;
                });
              },
            ),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: darkBlue, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomRequirementRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: customRequirementControllers[index],
              decoration: InputDecoration(
                hintText: 'Enter a requirement',
                prefixIcon: const Icon(
                  Icons.playlist_add_rounded,
                  color: primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFDCEAF1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primary, width: 1.6),
                ),
                filled: true,
                fillColor: const Color(0xFFF6FBFF),
              ),
              // Intentionally no validator -- Other Requirements are
              // optional, and an empty one is simply left out when saving
              // (see _buildRequirementsValue) rather than being required.
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _removeCustomRequirement(index),
            icon: const Icon(Icons.close_rounded),
            color: const Color(0xFFDE4D4D),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinic = widget.clinic;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      color: Colors.white,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // CLEAN HEADER - NO DARK GRADIENT
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(26, 24, 22, 20),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFE8F0F5)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF8FC),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Icon(
                                    clinic == null
                                        ? Icons.add_business_rounded
                                        : Icons.edit_location_alt_rounded,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        clinic == null
                                            ? 'Add New Center'
                                            : 'Edit Center Details',
                                        style: const TextStyle(
                                          color: darkBlue,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        clinic == null
                                            ? 'Create a new dialysis center profile.'
                                            : 'Update center information, capacity, and map location.',
                                        style: const TextStyle(
                                          color: mutedText,
                                          fontSize: 13.5,
                                          height: 1.35,
                                        ),
                                      ),
                                      if (clinic != null) ...[
                                        const SizedBox(height: 8),
                                        // Makes it unmistakable which
                                        // existing center is being updated,
                                        // not just that this is "edit mode".
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF3FAFC),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.edit_note_rounded,
                                                size: 15,
                                                color: Color(0xFF0F719F),
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  'Editing: ${clinic.name}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: Color(0xFF0F3A55),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: isSaving ? null : _requestClose,
                                  icon: const Icon(Icons.close_rounded),
                                  color: const Color(0xFF263B4A),
                                ),
                              ],
                            ),
                          ),

                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(26),
                              child: Form(
                                key: formKey,
                                // Ensures a field's error text appears (and
                                // stays in sync) as soon as the user edits it
                                // after a validation failure, instead of only
                                // updating on the next explicit validate()
                                // call.
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _SectionLabel(
                                      icon: Icons.info_outline_rounded,
                                      title: 'Basic Center Information',
                                    ),
                                    const SizedBox(height: 14),

                                    _buildTextField(
                                      controller: nameController,
                                      label: 'Center Name',
                                      icon: Icons.business_rounded,
                                      // Blocks an accidental duplicate
                                      // ACTIVE centre name. Case-insensitive
                                      // on the already-trimmed value
                                      // _buildTextField passes in. Runs via
                                      // the form's existing validate() call
                                      // in the Save handler, so it stops the
                                      // insert before it happens and shows
                                      // the reason under the field.
                                      extraValidator: (trimmedValue) {
                                        if (widget.existingCenterNames
                                            .contains(
                                              trimmedValue.toLowerCase(),
                                            )) {
                                          return 'An active center with this name already exists';
                                        }

                                        return null;
                                      },
                                    ),

                                    const SizedBox(height: 14),

                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _buildTextField(
                                            controller: addressController,
                                            label: 'Address',
                                            icon: Icons.location_on_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildTextField(
                                            controller: cityController,
                                            label: 'City',
                                            icon: Icons.location_city_rounded,
                                            readOnly: true,
                                            helperText:
                                                'Centers are currently limited to Valenzuela City.',
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 14),

                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.icon(
                                        onPressed: isFindingLocation
                                            ? null
                                            : _searchLocation,
                                        icon: isFindingLocation
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.my_location_rounded,
                                              ),
                                        label: Text(
                                          isFindingLocation
                                              ? 'Finding...'
                                              : 'Find on Map',
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: primary,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    const _SectionLabel(
                                      icon: Icons.map_outlined,
                                      title: 'Location',
                                    ),

                                    const SizedBox(height: 12),

                                    Container(
                                      height: 285,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: const Color(0xFFD9E7EF),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: FlutterMap(
                                          mapController: mapController,
                                          options: MapOptions(
                                            initialCenter: LatLng(
                                              selectedLatitude ?? 14.5995,
                                              selectedLongitude ?? 120.9842,
                                            ),
                                            initialZoom: 13,
                                            onTap: (tapPosition, point) {
                                              setState(() {
                                                selectedLatitude =
                                                    point.latitude;
                                                selectedLongitude =
                                                    point.longitude;
                                              });
                                            },
                                          ),
                                          children: [
                                            TileLayer(
                                              urlTemplate:
                                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                              userAgentPackageName:
                                                  'com.example.app',
                                            ),
                                            if (selectedLatitude != null &&
                                                selectedLongitude != null)
                                              MarkerLayer(
                                                markers: [
                                                  Marker(
                                                    point: LatLng(
                                                      selectedLatitude!,
                                                      selectedLongitude!,
                                                    ),
                                                    width: 44,
                                                    height: 44,
                                                    child: const Icon(
                                                      Icons.location_pin,
                                                      color: Color(0xFFEA5353),
                                                      size: 44,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(13),
                                      decoration: BoxDecoration(
                                        color: selectedLatitude != null
                                            ? const Color(0xFFEFF8FC)
                                            : const Color(0xFFFFF8E8),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selectedLatitude != null
                                                ? Icons.check_circle_rounded
                                                : Icons.touch_app_rounded,
                                            color: selectedLatitude != null
                                                ? primary
                                                : const Color(0xFFC7861B),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              selectedLatitude != null
                                                  ? 'Selected: Lat ${selectedLatitude!.toStringAsFixed(6)} | Lng ${selectedLongitude!.toStringAsFixed(6)}'
                                                  : 'Tap the map or use Find on Map to select the center location.',
                                              style: TextStyle(
                                                color: selectedLatitude != null
                                                    ? darkBlue
                                                    : const Color(0xFF8A651C),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    const _SectionLabel(
                                      icon: Icons.medical_services_outlined,
                                      title: 'Capacity',
                                    ),

                                    const SizedBox(height: 14),

                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildTextField(
                                            controller: machinesController,
                                            label: 'Machines',
                                            icon: Icons
                                                .precision_manufacturing_rounded,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                              decimal: false,
                                              signed: false,
                                            ),
                                            extraValidator:
                                                _validateWholeNumberField,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          // Editable when adding a centre;
                                          // read-only on Edit, as before.
                                          child: _buildTextField(
                                            controller: shiftsController,
                                            label: 'Shifts',
                                            icon: Icons.repeat_rounded,
                                            readOnly: clinic != null,
                                            keyboardType:
                                                TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            extraValidator:
                                                validateShiftsInput,
                                            helperText: clinic != null
                                                ? 'Saved shifts per day.'
                                                : 'Shifts per day.',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildTextField(
                                            controller: slotsController,
                                            label: 'Available Slots',
                                            icon: Icons.event_available_rounded,
                                            readOnly: clinic != null,
                                            keyboardType:
                                                TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            extraValidator:
                                                _validateWholeNumberField,
                                            helperText: clinic != null
                                                ? 'Recalculated from machines '
                                                      '× shifts when Machines '
                                                      'changes.'
                                                : 'Starts as machines × '
                                                      'shifts; you can change '
                                                      'it.',
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 24),

                                    const _SectionLabel(
                                      icon: Icons.checklist_rounded,
                                      title: 'Requirements',
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Select the requirements needed for '
                                      'patient registration.',
                                      style: TextStyle(
                                        color: mutedText,
                                        fontSize: 12.5,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF6FBFF),
                                        borderRadius: BorderRadius.circular(
                                          16,
                                        ),
                                        border: Border.all(
                                          color: const Color(0xFFDCEAF1),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          for (final option
                                              in _commonRequirementOptions)
                                            _buildRequirementCheckbox(option),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 18),

                                    const Text(
                                      'Other Requirements (Optional)',
                                      style: TextStyle(
                                        color: darkBlue,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    for (
                                      var i = 0;
                                      i < customRequirementControllers.length;
                                      i++
                                    )
                                      _buildCustomRequirementRow(i),

                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: _addCustomRequirement,
                                        icon: const Icon(Icons.add_rounded),
                                        label: const Text('Add Requirement'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: primary,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 10),

                                    const _SectionLabel(
                                      icon: Icons.schedule_rounded,
                                      title: 'Operating Information',
                                    ),

                                    const SizedBox(height: 14),

                                    _buildOperatingHoursPicker(),

                                    const SizedBox(height: 16),

                                    _buildContactNumberField(),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF7FAFC),
                              border: Border(
                                top: BorderSide(color: Color(0xFFE5EEF4)),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: isSaving ? null : _requestClose,
                                  child: const Text('Cancel'),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  // Editing: stays disabled until a value
                                  // actually differs from the saved record.
                                  onPressed:
                                      isSaving ||
                                          (clinic != null && !_hasChanges)
                                      ? null
                                      : () async {
                                          // Explicit re-entrancy guard: the
                                          // onPressed: isSaving ? null : ...
                                          // gate above only takes effect once
                                          // the dialog rebuilds, so two very
                                          // fast taps could otherwise both
                                          // reach this callback before that
                                          // rebuild happens. This stops a
                                          // second submission cold even in
                                          // that window.
                                          if (isSaving) return;

                                          final formValid = formKey
                                              .currentState!
                                              .validate();

                                          // Hours and contact are checked
                                          // again here, not only by the
                                          // fields, so nothing invalid can
                                          // reach the database.
                                          final hoursError = _validateHours();
                                          setState(
                                            () => _hoursError = hoursError,
                                          );

                                          if (!formValid ||
                                              hoursError != null) {
                                            return;
                                          }

                                          final contactError =
                                              validatePhLocalDigits(
                                                contactController.text,
                                              );
                                          if (contactError != null) {
                                            SuperAdminNotice.error(
                                              context,
                                              contactError,
                                              title:
                                                  'Check this before saving',
                                            );
                                            return;
                                          }

                                          if (selectedLatitude == null ||
                                              selectedLongitude == null) {
                                            SuperAdminNotice.error(
                                              context,
                                              'Please select a location on the map.',
                                              title:
                                                  'Check this before saving',
                                            );
                                            return;
                                          }

                                          setState(() => isSaving = true);

                                          try {
                                            if (clinic == null) {
                                              await _service.createCenter(
                                                name: nameController.text
                                                    .trim(),
                                                address: addressController.text
                                                    .trim(),
                                                city: cityController.text
                                                    .trim(),
                                                requirements:
                                                    _buildRequirementsValue(),
                                                latitude: selectedLatitude!,
                                                longitude: selectedLongitude!,
                                                // Form validation (via
                                                // _validateWholeNumberField)
                                                // already guarantees a valid,
                                                // non-negative whole number
                                                // here, so this no longer
                                                // silently falls back to 0 on
                                                // bad input.
                                                slotAvailable: double.parse(
                                                  slotsController.text.trim(),
                                                ).round(),
                                                machines: double.parse(
                                                  machinesController.text
                                                      .trim(),
                                                ).round(),
                                                shifts: int.parse(
                                                  shiftsController.text.trim(),
                                                ),
                                                operatingHours: _hoursToSave(),
                                                contactNumber:
                                                    _contactToSave(),
                                              );
                                            } else {
                                              await _service.updateCenter(
                                                centerId: clinic.id,
                                                // The centre's stored
                                                // lifecycle state, so a
                                                // soft-closed centre is not
                                                // silently reopened by an
                                                // ordinary edit.
                                                currentStatus: clinic.status,
                                                name: nameController.text
                                                    .trim(),
                                                address: addressController.text
                                                    .trim(),
                                                city: cityController.text
                                                    .trim(),
                                                requirements:
                                                    _buildRequirementsValue(),
                                                latitude: selectedLatitude!,
                                                longitude: selectedLongitude!,
                                                // Form validation (via
                                                // _validateWholeNumberField)
                                                // already guarantees a valid,
                                                // non-negative whole number
                                                // here, so this no longer
                                                // silently falls back to 0 on
                                                // bad input.
                                                slotAvailable: double.parse(
                                                  slotsController.text.trim(),
                                                ).round(),
                                                machines: double.parse(
                                                  machinesController.text
                                                      .trim(),
                                                ).round(),
                                                shifts: int.parse(
                                                  shiftsController.text.trim(),
                                                ),
                                                operatingHours: _hoursToSave(),
                                                contactNumber:
                                                    _contactToSave(),
                                              );
                                            }

                                            if (!mounted) return;

                                            // The parent page (via
                                            // _showClinicDialog) refreshes the
                                            // list and shows the success
                                            // snackbar once this dialog has
                                            // actually finished closing --
                                            // this widget's own controllers
                                            // must not be touched again after
                                            // this point.
                                            Navigator.of(context).pop(true);
                                          } catch (error) {
                                            if (!mounted) return;

                                            SuperAdminNotice.error(
                                              context,
                                              'Unable to save center: $error',
                                            );
                                          } finally {
                                            if (mounted) {
                                              setState(
                                                () => isSaving = false,
                                              );
                                            }
                                          }
                                        },
                                  icon: isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save_rounded),
                                  label: Text(
                                    clinic == null
                                        ? (isSaving
                                              ? 'Saving...'
                                              : 'Save Center')
                                        : (isSaving
                                              ? 'Saving...'
                                              : 'Save Changes'),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
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
}

class _HeaderCard extends StatelessWidget {
  final VoidCallback onAdd;

  const _HeaderCard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.white, AppTheme.headerTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.accentBlueSoft,
              borderRadius: BorderRadius.circular(AppTheme.rLg),
              border: Border.all(color: AppTheme.borderStrong),
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: AppTheme.blue1,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Centers Management',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppTheme.blue3,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Manage dialysis centers, operating details, capacity, and map locations in one organized workspace.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            height: 40,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Center'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.blue1,
                foregroundColor: AppTheme.white,
                padding: const EdgeInsets.symmetric(horizontal: 18),
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
        ],
      ),
    );
  }
}

class _DashboardStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String description;
  final Color accent;
  final Color accentSoft;

  const _DashboardStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.description,
    this.accent = AppTheme.blue1,
    this.accentSoft = AppTheme.accentBlueSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: AppTheme.iconBox(accentSoft),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: AppTheme.blue3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                    height: 1.3,
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

/// Search, filters and the centers list on one surface.
///
/// This replaces the two stacked cards that used to hold them. Every callback
/// is passed straight through to the same state handlers as before, so search,
/// status filtering, sorting, refresh, edit and delete all behave exactly as
/// they did.
class _CentersPanel extends StatefulWidget {
  final String searchText;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;

  final _CenterStatusFilter? statusFilter;
  final ValueChanged<_CenterStatusFilter?> onStatusChanged;

  final _CenterSortOption sortOption;
  final ValueChanged<_CenterSortOption> onSortChanged;

  final bool hasActiveFilters;
  final VoidCallback onClearFilters;

  final bool isLoading;
  final List<CenterModel> clinics;
  final bool hasAnyCenters;

  final VoidCallback onAdd;
  final void Function(CenterModel clinic) onEdit;
  final void Function(CenterModel clinic) onView;
  final void Function(CenterModel clinic, bool activate) onSetActive;
  final _CapacityEstimate Function(CenterModel clinic) capacityEstimateFor;

  const _CentersPanel({
    required this.searchText,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.statusFilter,
    required this.onStatusChanged,
    required this.sortOption,
    required this.onSortChanged,
    required this.hasActiveFilters,
    required this.onClearFilters,
    required this.isLoading,
    required this.clinics,
    required this.hasAnyCenters,
    required this.onAdd,
    required this.onEdit,
    required this.onView,
    required this.onSetActive,
    required this.capacityEstimateFor,
  });

  @override
  State<_CentersPanel> createState() => _CentersPanelState();
}

class _CentersPanelState extends State<_CentersPanel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchText);
  }

  @override
  void didUpdateWidget(covariant _CentersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.searchText != _controller.text) {
      _controller.text = widget.searchText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Keyed on the current value so an external reset (e.g. Clear Filters)
  // reliably resyncs the dropdown -- DropdownButtonFormField only reads
  // `initialValue` once per widget identity.
  Widget _filterDropdown<T>({
    required String keyPrefix,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 200,
      child: AppMenuTheme(
        child: DropdownButtonFormField<T>(
          key: ValueKey('$keyPrefix-$value'),
          initialValue: value,
          isExpanded: true,
          style: AppTheme.fieldTextStyle,
          icon: const Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: AppTheme.iconMuted,
          ),
          dropdownColor: AppTheme.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(AppTheme.menuRadius),
          decoration: AppTheme.field(
            dense: true,
            prefixIcon: Icon(icon, size: 17, color: AppTheme.blue1),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _sectionLabel({
    required IconData icon,
    required Color accent,
    required Color accentSoft,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: AppTheme.iconBox(accentSoft),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.blue3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            icon: Icons.filter_alt_outlined,
            accent: AppTheme.blue1,
            accentSoft: AppTheme.accentBlueSoft,
            title: 'Search & Filters',
            subtitle: 'Narrow the list by name, status, or order.',
            trailing: widget.hasActiveFilters
                ? TextButton.icon(
                    onPressed: widget.onClearFilters,
                    icon: const Icon(Icons.clear_all_rounded, size: 17),
                    label: const Text('Clear Filters'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.blue1,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : null,
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _controller,
                  onChanged: widget.onSearchChanged,
                  style: AppTheme.fieldTextStyle,
                  decoration: AppTheme.field(
                    hintText:
                        'Search by center name, city, address, or contact number...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: AppTheme.iconMuted,
                    ),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _controller.clear();
                              widget.onSearchChanged('');
                              setState(() {});
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppTheme.iconMuted,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Refresh',
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.accentBlueSoft,
                    foregroundColor: AppTheme.blue1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filterDropdown<_CenterStatusFilter?>(
                keyPrefix: 'status',
                icon: Icons.tune_rounded,
                value: widget.statusFilter,
                items: [
                  const DropdownMenuItem<_CenterStatusFilter?>(
                    value: null,
                    child: Text('All Statuses'),
                  ),
                  for (final option in _CenterStatusFilter.values)
                    DropdownMenuItem<_CenterStatusFilter?>(
                      value: option,
                      child: Text(option.label),
                    ),
                ],
                onChanged: widget.onStatusChanged,
              ),
              _filterDropdown<_CenterSortOption>(
                keyPrefix: 'sort',
                icon: Icons.sort_rounded,
                value: widget.sortOption,
                items: _CenterSortOption.values
                    .map(
                      (option) => DropdownMenuItem<_CenterSortOption>(
                        value: option,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) widget.onSortChanged(value);
                },
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1, thickness: 1, color: AppTheme.border),
          const SizedBox(height: 20),

          _sectionLabel(
            icon: Icons.view_list_rounded,
            accent: AppTheme.accentTeal,
            accentSoft: AppTheme.accentTealSoft,
            title: 'Centers List',
            subtitle:
                'Select a center to see its details. Use the actions to edit, '
                'deactivate or reactivate it.',
            trailing: widget.isLoading || widget.clinics.isEmpty
                ? null
                : Text(
                    widget.clinics.length == 1
                        ? '1 center'
                        : '${widget.clinics.length} centers',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),

          const SizedBox(height: 16),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: widget.isLoading
                ? const _LoadingPanel()
                : widget.clinics.isEmpty
                ? _EmptyPanel(
                    hasAnyCenters: widget.hasAnyCenters,
                    onAdd: widget.onAdd,
                    onClearFilters: widget.onClearFilters,
                  )
                : _CentersTable(
                    clinics: widget.clinics,
                    onEdit: widget.onEdit,
                    onView: widget.onView,
                    onSetActive: widget.onSetActive,
                    capacityEstimateFor: widget.capacityEstimateFor,
                  ),
          ),
        ],
      ),
    );
  }
}

/// The centers table itself. Same columns, same data, same row actions as
/// before -- only the spacing, type scale and pill treatment changed.
class _CentersTable extends StatelessWidget {
  final List<CenterModel> clinics;
  final void Function(CenterModel clinic) onEdit;
  final void Function(CenterModel clinic) onView;
  final void Function(CenterModel clinic, bool activate) onSetActive;
  final _CapacityEstimate Function(CenterModel clinic) capacityEstimateFor;

  const _CentersTable({
    required this.clinics,
    required this.onEdit,
    required this.onView,
    required this.onSetActive,
    required this.capacityEstimateFor,
  });

  static const TextStyle _headingStyle = TextStyle(
    color: AppTheme.textMuted,
    fontSize: 11.5,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static const TextStyle _bodyStyle = TextStyle(
    color: AppTheme.textSecondary,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('centers-table'),
      builder: (context, constraints) {
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                // Rows open the centre's details when clicked; no selection
                // checkboxes.
                showCheckboxColumn: false,
                headingRowColor: WidgetStateProperty.all(AppTheme.surfaceTint),
                headingRowHeight: 44,
                headingTextStyle: _headingStyle,
                dataTextStyle: _bodyStyle,
                dataRowMinHeight: 64,
                dataRowMaxHeight: 72,
                columnSpacing: 28,
                horizontalMargin: 16,
                dividerThickness: 1,
                border: const TableBorder(
                  horizontalInside: BorderSide(color: AppTheme.border),
                ),
                columns: [
                  const DataColumn(label: Text('CENTER')),
                  const DataColumn(label: Text('CITY')),
                  const DataColumn(label: Text('SLOTS')),
                  const DataColumn(label: Text('MACHINES')),
                  // Total capacity, reserved count and created date are
                  // shown in the centre details modal instead.
                  DataColumn(
                    label: Tooltip(
                      message:
                          'Super Admin estimate only: Total Capacity '
                          'minus Reserved. Not the Center Admin\'s '
                          'authoritative day/shift schedule.',
                      child: Text('AVAILABLE (EST.)'),
                    ),
                  ),
                  const DataColumn(
                    label: Tooltip(
                      message:
                          'Open or Closed right now, from the operating hours.',
                      child: Text('AVAILABILITY'),
                    ),
                  ),
                  const DataColumn(
                    label: Tooltip(
                      message:
                          'Active or Inactive center record. Inactive centers '
                          'keep their history but are not used operationally.',
                      child: Text('RECORD'),
                    ),
                  ),
                  const DataColumn(label: Text('ACTIONS')),
                ],
                rows: clinics.map((clinic) {
                  final estimate = capacityEstimateFor(clinic);

                  return DataRow(
                    onSelectChanged: (_) => onView(clinic),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 290,
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: AppTheme.iconBox(
                                  AppTheme.accentBlueSoft,
                                ),
                                child: const Icon(
                                  Icons.local_hospital_rounded,
                                  color: AppTheme.blue1,
                                  size: 17,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      clinic.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        height: 1.25,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.blue3,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      clinic.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11.5,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          clinic.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(
                        _MiniPill(
                          text: clinic.availableSlots.toString(),
                          icon: Icons.event_available_rounded,
                          background: AppTheme.accentGreenSoft,
                          foreground: AppTheme.accentGreen,
                        ),
                      ),
                      DataCell(
                        _MiniPill(
                          text: clinic.machines.toString(),
                          icon: Icons.precision_manufacturing_rounded,
                          background: AppTheme.accentTealSoft,
                          foreground: AppTheme.accentTeal,
                        ),
                      ),
                      DataCell(
                        estimate.available == null
                            ? const _MiniPill(
                                text: '—',
                                icon: Icons.calculate_outlined,
                                background: Color(0xFFF1F3F5),
                                foreground: AppTheme.textMuted,
                              )
                            : _MiniPill(
                                text: estimate.capacityExceeded
                                    ? '${estimate.available} · Capacity exceeded'
                                    : estimate.available.toString(),
                                icon: Icons.calculate_outlined,
                                background: estimate.capacityExceeded
                                    ? AppTheme.accentOrangeSoft
                                    : null,
                                foreground: estimate.capacityExceeded
                                    ? AppTheme.accentOrange
                                    : null,
                              ),
                      ),
                      DataCell(
                        CenterAvailabilityBadge(
                          availability: clinic.availability(),
                        ),
                      ),
                      DataCell(
                        CenterRecordStatusBadge(status: clinic.recordStatus),
                      ),
                      DataCell(
                        Row(
                          children: [
                            _ActionIconButton(
                              icon: Icons.visibility_outlined,
                              color: AppTheme.accentTeal,
                              tooltip: 'View details',
                              onTap: () => onView(clinic),
                            ),
                            const SizedBox(width: 8),
                            _ActionIconButton(
                              icon: Icons.edit_rounded,
                              color: AppTheme.blue1,
                              tooltip: 'Edit center',
                              onTap: () => onEdit(clinic),
                            ),
                            const SizedBox(width: 8),
                            if (clinic.isActive)
                              _ActionIconButton(
                                icon: Icons.block_rounded,
                                color: AppTheme.danger,
                                tooltip: 'Deactivate center',
                                onTap: () => onSetActive(clinic, false),
                              )
                            else
                              _ActionIconButton(
                                icon: Icons.restart_alt_rounded,
                                color: AppTheme.accentGreen,
                                tooltip: 'Reactivate center',
                                onTap: () => onSetActive(clinic, true),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}


class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? tooltip;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppTheme.rSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        hoverColor: color.withValues(alpha: 0.14),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );

    final label = tooltip;
    if (label == null) return button;
    return Tooltip(message: label, child: button);
  }
}

/// One clinic's Super Admin capacity ESTIMATE (see DashboardService
/// .getReservedPatientCount/.calculateAvailableSlotsEstimate) --
/// [totalCapacity] is always known (machines × saved shifts, pure
/// arithmetic on already-loaded data); [reserved]/[available] are null when that
/// clinic's patient-count query failed, so the UI can show "--" instead of
/// a misleadingly confident number.
class _CapacityEstimate {
  final int totalCapacity;
  final int? reserved;
  final int? available;

  const _CapacityEstimate({
    required this.totalCapacity,
    required this.reserved,
    required this.available,
  });

  bool get capacityExceeded => reserved != null && reserved! > totalCapacity;
}

class _MiniPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? background;
  final Color? foreground;

  const _MiniPill({
    required this.text,
    required this.icon,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? AppTheme.blue1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? AppTheme.accentBlueSoft,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              height: 1.2,
              color: foreground ?? AppTheme.blue3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('loading'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: const Column(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppTheme.blue1,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading centers...',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  /// True when centers exist but the current search/filters matched none of
  /// them; false when there are no centers at all yet. These are different
  /// situations and get different messaging/actions.
  final bool hasAnyCenters;
  final VoidCallback onAdd;
  final VoidCallback onClearFilters;

  const _EmptyPanel({
    required this.hasAnyCenters,
    required this.onAdd,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('empty'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: AppTheme.iconBox(
              AppTheme.accentBlueSoft,
              radius: AppTheme.rLg,
            ),
            child: Icon(
              hasAnyCenters ? Icons.search_off_rounded : Icons.business_rounded,
              color: AppTheme.blue1,
              size: 22,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasAnyCenters
                ? 'No centers match your search or filters.'
                : 'No centers available yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: AppTheme.blue3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasAnyCenters
                ? 'Try a different search term, or adjust the status filter.'
                : 'Create your first dialysis center to start managing capacity and operations.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          if (hasAnyCenters)
            TextButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.clear_all_rounded, size: 17),
              label: const Text('Clear Filters'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.blue1,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            SizedBox(
              height: 40,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Center'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.blue1,
                  foregroundColor: AppTheme.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
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
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionLabel({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0F719F), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0F3A55),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
