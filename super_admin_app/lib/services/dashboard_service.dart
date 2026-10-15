import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/center_model.dart';
import '../models/donation_summary.dart';
import '../models/notification_item.dart';
import '../utils/center_capacity.dart';
import '../utils/center_status.dart';

class DashboardService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  /// Patient statuses that count as "accepted/reserved" at a clinic for the
  /// Super Admin capacity ESTIMATE (see calculateAvailableSlotsEstimate) --
  /// this mirrors the one existing definition of that concept already in
  /// the codebase, mobile-app's PatientService._activeStatuses (used by
  /// getActivePatientRow/hasPatientAccess): 'no_sched' (accepted by the
  /// Center Admin, no recurring schedule assigned yet) and 'active' (has
  /// an active recurring schedule). 'approved' is included defensively for
  /// the same reason mobile-app includes it there -- nothing in the current
  /// codebase writes that value, but it costs nothing to also treat it as
  /// reserved in case older data ever has it.
  static const List<String> _reservedPatientStatuses = [
    'no_sched',
    'active',
    'approved',
  ];

  /// Counts patients reserved/accepted at one clinic, for the Super Admin
  /// capacity estimate only. A plain read of the existing `patients` table
  /// -- no schema change, no new table, no RPC -- and never writes
  /// anything back. Deliberately lets a failure propagate (rather than
  /// swallowing it and returning 0) so a caller can tell "zero reserved
  /// patients" apart from "the count could not be fetched" and never
  /// mistakes the latter for the former.
  Future<int> getReservedPatientCount(String clinicId) async {
    final response = await _supabase
        .from('patients')
        .select('id')
        .eq('clinic_id', clinicId)
        .inFilter('status', _reservedPatientStatuses);

    return (response as List).length;
  }

  /// The Super Admin's own live capacity ESTIMATE: total theoretical
  /// capacity (machines × the centre's saved shifts) minus how many patients
  /// are currently reserved/accepted at this clinic (see
  /// getReservedPatientCount). The arithmetic lives in
  /// utils/center_capacity.dart so every screen uses the same formula.
  ///
  /// This is deliberately separate from, and never written into,
  /// clinics.slots_available -- it is NOT the authoritative day/shift
  /// scheduling capacity (that remains CenterScheduleService's
  /// getCapacitySnapshot() in admin_panel, untouched by this), just a
  /// coarser, at-a-glance headcount estimate for Super Admin. Never
  /// negative -- clamped to 0 if reserved patients exceed capacity.
  int calculateAvailableSlotsEstimate({
    required int machines,
    required int shifts,
    required int reservedPatients,
  }) {
    return estimatedAvailableSlots(
      totalCapacity: totalCenterCapacity(machines: machines, shifts: shifts),
      reservedPatients: reservedPatients,
    );
  }

  List<String> _parseRequirements(String requirements) {
    return requirements
        .split(RegExp(r'[,;\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  bool _isVerifiedDonation(Map<String, dynamic> record) {
    final status = record['status']?.toString().toLowerCase().trim() ?? '';
    return status == 'verified';
  }

  int _parseDonationAmount(Map<String, dynamic> record) {
    final amount = double.tryParse(record['amount']?.toString() ?? '0') ?? 0.0;
    return amount.toInt();
  }

  Future<int> fetchVerifiedDonationTotal() async {
    final response = await _supabase.from('donations').select('amount, status');

    final donations = response as List<dynamic>;

    int totalDonations = 0;

    for (final item in donations) {
      final record = item as Map<String, dynamic>;

      if (!_isVerifiedDonation(record)) continue;

      totalDonations += _parseDonationAmount(record);
    }

    return totalDonations;
  }

  // fetchOverviewStats() was removed (R6). It ran four unbounded full-table
  // scans -- patients, appointments, clinics and every donation row -- on
  // every dashboard load, and not one of the four values it returned reached
  // the UI: three were never read, and its donation total was overwritten by
  // the caller before the map was ever assigned to _stats. It also ran ahead
  // of fetchCenters() in the same try block, so a failure in a scan nobody
  // used (a denied policy, or the appointments table) aborted the whole
  // dashboard load. The donation figure the dashboard actually shows still
  // comes from the page's own _fetchVerifiedDonationTotal().

  Future<List<CenterModel>> fetchCenters() async {
    final response = await _supabase
        .from('clinics')
        .select()
        .or('status.is.null,status.neq.closed')
        .order('created_at', ascending: false);

    final list = response as List<dynamic>;

    return list
        .map(
          (postgres) => CenterModel.fromJson(postgres as Map<String, dynamic>),
        )
        .toList();
  }

  /// Every centre, Active and Inactive, for the Centres management page --
  /// inactive centres stay visible there (with their status) so they can be
  /// reactivated. Operational views keep using [fetchCenters].
  Future<List<CenterModel>> fetchAllCenters() async {
    final response = await _supabase
        .from('clinics')
        .select()
        .order('created_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => CenterModel.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Marks a centre record Active or Inactive by writing its
  /// `clinics.status` (see utils/center_status.dart). Only the status column
  /// changes: the centre row, its donations, patients, admins and audit
  /// history are all left as they are.
  Future<void> setCenterRecordStatus({
    required String centerId,
    required CenterRecordStatus status,
  }) async {
    // .select() so a zero-row update (centre removed, or not permitted) is
    // reported instead of silently looking like success.
    final updated = await _supabase
        .from('clinics')
        .update({'status': status.storedValue})
        .eq('id', centerId)
        .select('id');

    if (updated.isEmpty) {
      throw Exception(
        'This center could not be updated. It may have been removed or '
        'changed by someone else. Refresh and try again.',
      );
    }
  }

  Future<List<NotificationItem>> fetchNotifications() async {
    final response = await _supabase
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(6);

    final list = response as List<dynamic>;

    return list
        .map((item) => NotificationItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<DonationSummary>> fetchDonationSummary() async {
    final totalDonations = await fetchVerifiedDonationTotal();

    return [
      DonationSummary(
        centerName: 'Total Verified Donations',
        totalAmount: totalDonations.toDouble(),
      ),
    ];
  }

  Future<void> createCenter({
    required String name,
    required String address,
    required String city,
    required String requirements,
    required double latitude,
    required double longitude,
    required int slotAvailable,
    required int machines,
    required int shifts,
    required String operatingHours,
    required String contactNumber,
  }) async {
    await _supabase.from('clinics').insert({
      'name': name,
      'address': address,
      'city': city,
      'requirements': _parseRequirements(requirements),
      'latitude': latitude,
      'longitude': longitude,
      'slots_available': slotAvailable,
      'machine': machines,
      'shifts': shifts,
      // A new centre starts Active. Open/Closed availability is not stored;
      // it follows the operating hours.
      'status': CenterRecordStatus.active.storedValue,
      'operating_hours': operatingHours,
      'contact_number': contactNumber,
    });
  }

  /// Saves an ordinary edit. `clinics.status` (Active/Inactive) is never
  /// written here -- only [setCenterRecordStatus] changes it -- so editing a
  /// centre can neither reopen an inactive one nor rewrite a legacy value.
  /// [currentStatus] is still accepted from existing callers but unused.
  Future<void> updateCenter({
    required String centerId,
    required String name,
    required String address,
    required String city,
    required String requirements,
    required double latitude,
    required double longitude,
    required int slotAvailable,
    required int machines,
    required int shifts,
    required String operatingHours,
    required String contactNumber,
    String? currentStatus,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'address': address,
      'city': city,
      'requirements': _parseRequirements(requirements),
      'latitude': latitude,
      'longitude': longitude,
      'slots_available': slotAvailable,
      'machine': machines,
      'shifts': shifts,
      'operating_hours': operatingHours,
      'contact_number': contactNumber,
    };

    // .select() so the update reports which rows it actually changed. A
    // PostgREST update that matches nothing is NOT an error -- it quietly
    // affects zero rows -- so a center deleted or otherwise unreachable
    // between opening the Edit form and saving it still reported success.
    final updated = await _supabase
        .from('clinics')
        .update(payload)
        .eq('id', centerId)
        .select();

    if (updated.isEmpty) {
      throw Exception(
        'This center could not be updated. It may have been removed or '
        'changed by someone else. Refresh and try again.',
      );
    }
  }
}
