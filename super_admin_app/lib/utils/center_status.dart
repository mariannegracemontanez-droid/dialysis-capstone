// The two separate centre states the Super Admin app shows, and how both are
// read from the data that already exists. There is no schema change: the
// `clinics` table has a single text `status` column, and both states are
// derived from it plus `operating_hours`.
//
// RECORD STATUS (Active / Inactive) -- is the centre record in use?
//   Stored in `clinics.status`. 'closed' has always been this app's
//   soft-delete marker (the old "Delete center" action wrote it), and the
//   Donation app and every Super Admin list already hide 'closed' centres,
//   so it stays the Inactive value. Everything else is Active.
//
// AVAILABILITY (Open / Closed) -- is an active centre open right now?
//   Derived from `clinics.operating_hours` via [isWithinOperatingHours], the
//   same rule the dashboard's "Open Now" figure already uses. An inactive
//   centre is never Open.
//
// Legacy `clinics.status` values, mapped without rewriting any row:
//   'open', 'busy', 'full', null, '' or anything else -> Active
//   'closed'                                          -> Inactive
// 'busy' and 'full' were capacity labels computed from available slots;
// they are no longer shown or written, and nothing else in the project reads
// them. Existing rows keep whatever value they hold until they are next
// activated or deactivated.

import 'package:flutter/material.dart';

import 'operating_hours.dart';

/// `clinics.status` value written for an Inactive centre (the existing
/// soft-delete marker).
const String inactiveCenterStatusValue = 'closed';

/// `clinics.status` value written for an Active centre.
const String activeCenterStatusValue = 'open';

enum CenterRecordStatus {
  active('Active'),
  inactive('Inactive');

  const CenterRecordStatus(this.label);
  final String label;

  /// The `clinics.status` value that represents this record status.
  String get storedValue => this == CenterRecordStatus.active
      ? activeCenterStatusValue
      : inactiveCenterStatusValue;
}

enum CenterAvailability {
  open('Open'),
  closed('Closed');

  const CenterAvailability(this.label);
  final String label;
}

/// Record status for a stored `clinics.status` value; see the mapping above.
CenterRecordStatus centerRecordStatusOf(String? storedStatus) {
  final value = storedStatus?.trim().toLowerCase() ?? '';
  return value == inactiveCenterStatusValue
      ? CenterRecordStatus.inactive
      : CenterRecordStatus.active;
}

/// Availability for a centre: Open only when its record is Active and
/// [operatingHours] says it is open at [now]. Missing or unreadable hours
/// are Closed -- never assumed open.
CenterAvailability centerAvailabilityOf({
  required String? storedStatus,
  required String? operatingHours,
  TimeOfDay? now,
}) {
  if (centerRecordStatusOf(storedStatus) == CenterRecordStatus.inactive) {
    return CenterAvailability.closed;
  }

  return isWithinOperatingHours(operatingHours, now: now)
      ? CenterAvailability.open
      : CenterAvailability.closed;
}
