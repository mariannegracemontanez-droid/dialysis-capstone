import 'package:flutter/material.dart';

import '../utils/center_capacity.dart';
import '../utils/center_status.dart';

class CenterModel {
  final String id;
  final String name;
  final String address;
  final String city;
  final String requirements; // ✅ FIXED
  final double? latitude;
  final double? longitude;
  final int machines;
  final int totalPatients;
  final int availableSlots;
  final String status;
  final String operatingHours;
  final int shifts;
  final String contactNumber;
  final DateTime createdAt;

  /// The saved `created_at`, or null when the row has none (or it cannot be
  /// read). [createdAt] falls back to "now" so sorting keeps working; use
  /// this instead wherever the date is shown.
  final DateTime? savedCreatedAt;

  CenterModel({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.requirements,
    required this.latitude,
    required this.longitude,
    required this.machines,
    required this.totalPatients,
    required this.availableSlots,
    required this.status,
    required this.operatingHours,
    required this.shifts,
    required this.contactNumber,
    required this.createdAt,
    this.savedCreatedAt,
  });

  /// The `clinics.status` value that marks an INACTIVE centre record (the
  /// existing soft-delete marker). See utils/center_status.dart for how
  /// record status and Open/Closed availability are both derived.
  static const String closedStatus = inactiveCenterStatusValue;

  /// Active / Inactive record status. Legacy 'busy'/'full' rows are Active.
  CenterRecordStatus get recordStatus => centerRecordStatusOf(status);

  bool get isActive => recordStatus == CenterRecordStatus.active;

  /// True when this centre record is Inactive (`clinics.status == 'closed'`).
  /// Not the same as being closed for the day -- see [availability]. An
  /// inactive centre is excluded from the dashboard's operational figures
  /// and from new admin assignments.
  bool get isClosed => !isActive;

  /// Open / Closed right now: Open only for an Active centre inside its
  /// operating hours.
  CenterAvailability availability({TimeOfDay? now}) => centerAvailabilityOf(
    storedStatus: status,
    operatingHours: operatingHours,
    now: now,
  );

  /// Machines × this centre's saved shifts (see utils/center_capacity.dart).
  int get totalCapacity =>
      totalCenterCapacity(machines: machines, shifts: shifts);

  bool get isOpen => availability() == CenterAvailability.open;
  String get statusText => availability().label;

  factory CenterModel.fromJson(Map<String, dynamic> json) {
    final statusValue = json['open_status'] ?? json['status'] ?? 'open';
    final openTime = json['open_time']?.toString() ?? '';
    final closeTime = json['close_time']?.toString() ?? '';
    // No invented fallback: a centre without saved hours shows "Not set" and
    // is never counted as open. (This used to default to 7:00 AM - 5:00 PM.)
    final hours = json['operating_hours']?.toString() ??
        (openTime.isNotEmpty && closeTime.isNotEmpty
            ? '$openTime - $closeTime'
            : '');

    return CenterModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Center',
      address: json['address']?.toString() ?? 'Unspecified address',
      city: json['city']?.toString() ?? '',
     requirements: json['requirements']?.toString() ?? '',
      latitude: json['latitude'] != null
          ? double.tryParse(json['latitude'].toString())
          : null,
      longitude: json['longitude'] != null
          ? double.tryParse(json['longitude'].toString())
          : null,
      machines: int.tryParse(json['machine']?.toString() ?? '') ?? 0,
      totalPatients:
          int.tryParse(json['total_patients']?.toString() ?? '') ?? 0,
      availableSlots:
          int.tryParse(json['slots_available']?.toString() ?? '') ?? 0,
      status: statusValue.toString(),
      operatingHours: hours,
      // The saved shift count; the default applies only when it is missing.
      shifts: savedShiftsOrDefault(json['shifts']),
      contactNumber: json['contact_number']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ??
              DateTime.now()
          : DateTime.now(),
      savedCreatedAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}