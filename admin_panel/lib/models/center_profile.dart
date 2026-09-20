/// One dialysis center, as the `clinics` row already stores it.
///
/// Every field below maps to a column that exists today. Nothing here
/// introduces a parallel capacity, requirements or hours field -- the
/// Center Profile page reads and writes the SAME columns the Super Admin
/// portal and the patient mobile app already use:
///
///   machine          the center's dialysis machines
///   requirements     text[] -- also written by the Super Admin's
///                    Add/Edit Center form
///   operating_hours  text -- also displayed by the mobile app's clinic
///                    pages
///   house_rules      text -- added by supabase/center_profile.sql, the
///                    only genuinely new column
///
/// Read-only here (Super Admin owns them): name, address, city, contact
/// number, slots_available and status.
class CenterProfile {
  final String id;
  final String name;
  final String address;
  final String city;
  final String contactNumber;

  /// Number of dialysis machines. The center-level capacity figure the
  /// Super Admin's available-slots estimate is derived from.
  final int machines;

  /// Coarse Super Admin estimate. Shown for context, never edited here --
  /// CenterScheduleService.getCapacitySnapshot remains the authoritative
  /// scheduling capacity.
  final int availableSlots;

  final String status;

  /// Free text such as `7:00 AM - 5:00 PM`.
  final String operatingHours;

  /// Optional day-level safety cap (clinics.target_daily_capacity).
  final int? targetDailyCapacity;

  final List<String> requirements;
  final String houseRules;

  const CenterProfile({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.contactNumber,
    required this.machines,
    required this.availableSlots,
    required this.status,
    required this.operatingHours,
    required this.targetDailyCapacity,
    required this.requirements,
    required this.houseRules,
  });

  factory CenterProfile.fromJson(Map<String, dynamic> json) {
    return CenterProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Center',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      contactNumber: json['contact_number']?.toString() ?? '',
      machines: int.tryParse(json['machine']?.toString() ?? '') ?? 0,
      availableSlots:
          int.tryParse(json['slots_available']?.toString() ?? '') ?? 0,
      status:
          json['status']?.toString() ?? json['open_status']?.toString() ?? '',
      operatingHours: json['operating_hours']?.toString() ?? '',
      targetDailyCapacity: json['target_daily_capacity'] == null
          ? null
          : int.tryParse(json['target_daily_capacity'].toString()),
      requirements: parseRequirements(json['requirements']),
      houseRules: json['house_rules']?.toString() ?? '',
    );
  }

  /// Reads `clinics.requirements` back into individual items.
  ///
  /// The column is `text[]`, so Supabase normally hands back a real List
  /// and each element is exactly one requirement -- no splitting, no
  /// guessing. The string branches exist only for rows written before
  /// the column was an array, and they follow the same rule the Super
  /// Admin's `_parseStoredRequirements` and the mobile app's
  /// `_requirementItems` already apply:
  ///
  ///   * a bracketed `[A, B, C]` value is Dart's own `List.toString()`,
  ///     whose commas were put there by code, so splitting on them is
  ///     safe;
  ///   * a bare string is legacy free text with no delimiter contract,
  ///     so it is only split on newlines -- the delimiter this app's own
  ///     UI writes. A comma inside old prose ("ID, referral") could just
  ///     as easily be one item as two, so it is left alone.
  ///
  /// Nothing is ever discarded.
  static List<String> parseRequirements(Object? raw) {
    if (raw == null) return const [];

    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    final text = raw.toString().trim();
    if (text.isEmpty) return const [];

    if (text.startsWith('[') && text.endsWith(']')) {
      return text
          .substring(1, text.length - 1)
          .split(RegExp(r'[,;\n]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    return text
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  bool get hasHouseRules => houseRules.trim().isNotEmpty;

  CenterProfile copyWith({
    int? machines,
    String? operatingHours,
    List<String>? requirements,
    String? houseRules,
  }) {
    return CenterProfile(
      id: id,
      name: name,
      address: address,
      city: city,
      contactNumber: contactNumber,
      machines: machines ?? this.machines,
      availableSlots: availableSlots,
      status: status,
      operatingHours: operatingHours ?? this.operatingHours,
      targetDailyCapacity: targetDailyCapacity,
      requirements: requirements ?? this.requirements,
      houseRules: houseRules ?? this.houseRules,
    );
  }
}

/// The requirement checkboxes offered to the Center Admin.
///
/// Deliberately the SAME ten labels the Super Admin's Add/Edit Center form
/// offers (super_admin_app/lib/pages/center_page.dart,
/// `_commonRequirementOptions`), written against the same `requirements`
/// column. Keeping the wording identical is what lets a requirement the
/// Super Admin ticked come back ticked here, instead of being demoted to
/// a custom row because a word differs.
///
/// Anything stored that is not exactly one of these is preserved as a
/// custom requirement, never dropped.
const List<String> kCommonCenterRequirements = [
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
