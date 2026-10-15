// Which centres a clinic-admin (head nurse) account may be assigned to.
//
// A centre is eligible when its record is Active and no active admin is
// already assigned to it. Open/Closed availability is deliberately NOT a
// rule: it follows the operating hours, so it changes through the day, and
// the existing assignment flow never required an open centre.

import 'center_status.dart';

/// Whether the `clinics` row [clinic] can take a new admin assignment.
/// [clinicsWithAdmin] holds the ids of centres that already have an active
/// admin. [currentClinicId] is the centre the account being edited already
/// holds, which stays selectable for that account.
bool isCenterEligibleForAssignment(
  Map<String, dynamic> clinic, {
  required Set<String> clinicsWithAdmin,
  String? currentClinicId,
}) {
  final id = clinic['id']?.toString();
  if (id == null || id.isEmpty) return false;
  if (id == currentClinicId) return true;

  final status = clinic['status']?.toString();
  if (centerRecordStatusOf(status) != CenterRecordStatus.active) return false;

  return !clinicsWithAdmin.contains(id);
}

/// The [clinics] an admin can be assigned to, in their existing order.
List<Map<String, dynamic>> eligibleCentersForAssignment(
  List<Map<String, dynamic>> clinics, {
  required Set<String> clinicsWithAdmin,
  String? currentClinicId,
}) {
  return clinics
      .where(
        (clinic) => isCenterEligibleForAssignment(
          clinic,
          clinicsWithAdmin: clinicsWithAdmin,
          currentClinicId: currentClinicId,
        ),
      )
      .toList();
}
