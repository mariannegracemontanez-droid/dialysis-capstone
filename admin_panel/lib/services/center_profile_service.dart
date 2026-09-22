import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/center_profile.dart';
import '../models/clinic_shift.dart';
import 'center_schedule_service.dart';
import 'supabase_config.dart';

/// Reads and writes the signed-in Center Admin's own center.
///
/// ## Scoping
///
/// The clinic is resolved from the admin's `profiles.clinic_id`, never
/// passed in, so there is no parameter a caller could point at someone
/// else's center. The write goes through the `update_center_profile`
/// database function (supabase/center_profile.sql), which re-checks the
/// caller's role and clinic server-side and touches only the four columns
/// the profile page owns -- so no broad UPDATE policy on `clinics` had to
/// be granted, and the Super-Admin-managed columns on that row stay
/// unreachable from this panel.
///
/// ## Reuse
///
/// Shift reads and writes are delegated to [CenterScheduleService], which
/// is already the one place `clinic_shifts` is touched and the one place
/// capacity is calculated. Nothing here duplicates a shift table, a
/// capacity rule or a requirements store.
class CenterProfileService {
  final SupabaseClient client = SupabaseConfig.client;
  final CenterScheduleService _scheduleService = CenterScheduleService();

  Future<String?> getCurrentClinicId() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final profile = await client
        .from('profiles')
        .select('clinic_id')
        .eq('id', user.id)
        .maybeSingle();

    return profile?['clinic_id']?.toString();
  }

  /// The signed-in admin's display name, for the "Hello, ..." header.
  Future<String?> getCurrentAdminName() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final profile = await client
        .from('profiles')
        .select('full_name')
        .eq('id', user.id)
        .maybeSingle();

    return profile?['full_name']?.toString();
  }

  /// Everything the Center Profile page shows, in one round trip pair.
  ///
  /// Throws with a readable message when the account has no clinic, so
  /// the page can say what is wrong instead of rendering an empty shell.
  Future<CenterProfileSnapshot> loadProfile() async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception(
        'Your account is not assigned to a center yet. Ask a Super Admin to '
        'assign one before editing the center profile.',
      );
    }

    final results = await Future.wait<Object?>([
      client
          .from('clinics')
          .select(
            'id, name, address, city, contact_number, machine, '
            'slots_available, status, operating_hours, target_daily_capacity, '
            'requirements, house_rules',
          )
          .eq('id', clinicId)
          .maybeSingle(),
      _scheduleService.getClinicShifts(clinicId),
      _scheduleService.getOperatingDays(clinicId),
    ]);

    final row = results[0] as Map<String, dynamic>?;

    if (row == null) {
      throw Exception(
        'Your center could not be found. It may have been removed by a '
        'Super Admin.',
      );
    }

    return CenterProfileSnapshot(
      center: CenterProfile.fromJson(row),
      shifts: results[1] as List<ClinicShift>,
      operatingDays: results[2] as List<String>,
    );
  }

  /// Saves the center-level fields.
  ///
  /// Everything is validated again inside `update_center_profile`, so a
  /// value that slipped past the form still cannot land in the database.
  /// [requirements] replaces the stored array wholesale -- that is what
  /// makes unticking a box actually remove it.
  Future<void> saveCenterInfo({
    required int machines,
    required List<String> requirements,
    required String operatingHours,
    required String houseRules,
  }) async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception('No center is assigned to this admin account.');
    }

    await client.rpc(
      'update_center_profile',
      params: {
        'p_clinic_id': clinicId,
        'p_machine': machines,
        'p_requirements': requirements,
        'p_operating_hours': operatingHours,
        'p_house_rules': houseRules.trim().isEmpty ? null : houseRules.trim(),
      },
    );
  }

  /// Updates one shift's label, times, capacity and active flag.
  ///
  /// Straight through to [CenterScheduleService.updateClinicShift], the
  /// existing writer for `clinic_shifts`. shift_code is never touched, so
  /// daily_schedules.shift, the AM/PM logic, the capacity snapshot and
  /// the mobile app all keep working against the same two values.
  Future<void> saveShift({
    required ClinicShift shift,
    required String label,
    required String startTime,
    required String endTime,
    required int capacity,
    required bool isActive,
  }) {
    return _scheduleService.updateClinicShift(
      shiftId: shift.id,
      shiftLabel: label,
      startTime: startTime,
      endTime: endTime,
      capacity: capacity,
      isActive: isActive,
    );
  }

  /// Creates the AM or PM shift for a center that does not have one yet.
  ///
  /// The clinic is resolved from the signed-in admin's own profile, the
  /// same way [saveCenterInfo] does it, so this cannot be pointed at
  /// another center's shifts. Delegates to
  /// [CenterScheduleService.createClinicShift], which upserts on the
  /// existing `unique (clinic_id, shift_code)` constraint and so stays
  /// idempotent across repeated saves.
  Future<void> createShift({
    required String shiftCode,
    required String label,
    required String startTime,
    required String endTime,
    required int capacity,
    required bool isActive,
  }) async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception('No center is assigned to this admin account.');
    }

    await _scheduleService.createClinicShift(
      clinicId: clinicId,
      shiftCode: shiftCode,
      shiftLabel: label,
      startTime: startTime,
      endTime: endTime,
      capacity: capacity,
      isActive: isActive,
    );
  }
}

/// The center plus its configured shifts and operating days.
class CenterProfileSnapshot {
  final CenterProfile center;
  final List<ClinicShift> shifts;
  final List<String> operatingDays;

  const CenterProfileSnapshot({
    required this.center,
    required this.shifts,
    required this.operatingDays,
  });
}
