import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/center_model.dart';
import '../models/donation_summary.dart';
import '../models/notification_item.dart';

class DashboardService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  String computeStatus(int availableSlots) {
    if (availableSlots == 0) return 'full';
    if (availableSlots <= 2) return 'busy';
    return 'open';
  }

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
  /// capacity (machines x 2 shifts) minus how many patients are currently
  /// reserved/accepted at this clinic (see getReservedPatientCount).
  ///
  /// This is deliberately separate from, and never written into,
  /// clinics.slots_available -- it is NOT the authoritative day/shift
  /// scheduling capacity (that remains CenterScheduleService's
  /// getCapacitySnapshot() in admin_panel, untouched by this), just a
  /// coarser, at-a-glance headcount estimate for Super Admin. Never
  /// negative -- clamped to 0 if reserved patients exceed capacity.
  int calculateAvailableSlotsEstimate({
    required int machines,
    required int reservedPatients,
  }) {
    final totalCapacity = machines * 2;
    return math.max(0, totalCapacity - reservedPatients);
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

  Future<Map<String, int>> fetchOverviewStats() async {
    final patients = await _supabase.from('patients').select('id');
    final appointments = await _supabase.from('appointments').select('id');
    final centers = await _supabase.from('clinics').select('id');

    final totalDonations = await fetchVerifiedDonationTotal();

    return {
      'patients': (patients as List).length,
      'appointments': (appointments as List).length,
      'centers': (centers as List).length,
      'donations': totalDonations,
    };
  }

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
    final status = computeStatus(slotAvailable);

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
      'status': status,
      'operating_hours': operatingHours,
      'contact_number': contactNumber,
    });
  }

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
  }) async {
    final status = computeStatus(slotAvailable);

    await _supabase
        .from('clinics')
        .update({
          'name': name,
          'address': address,
          'city': city,
          'requirements': _parseRequirements(requirements),
          'latitude': latitude,
          'longitude': longitude,
          'slots_available': slotAvailable,
          'machine': machines,
          'shifts': shifts,
          'status': status,
          'operating_hours': operatingHours,
          'contact_number': contactNumber,
        })
        .eq('id', centerId);
  }

  Future<void> deleteCenter(String centerId) async {
    await _supabase.from('clinics').delete().eq('id', centerId);
  }
}
