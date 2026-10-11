/// Shared handling for the patient's separated name columns
/// (`first_name`, `middle_name`, `last_name`).
///
/// Legacy rows created before the columns existed only have `full_name`.
/// Those are never split automatically (compound first names and surnames
/// make that unreliable), so [fromRow] keeps the legacy value in
/// [legacyFullName] and [displayName] falls back to it.
class PatientName {
  final String firstName;
  final String? middleName;
  final String lastName;
  final String legacyFullName;

  const PatientName({
    this.firstName = '',
    this.middleName,
    this.lastName = '',
    this.legacyFullName = '',
  });

  factory PatientName.fromRow(Map<String, dynamic>? row) {
    String clean(Object? value) => normalize(value?.toString() ?? '');

    final middle = clean(row?['middle_name']);
    return PatientName(
      firstName: clean(row?['first_name']),
      middleName: middle.isEmpty ? null : middle,
      lastName: clean(row?['last_name']),
      legacyFullName: clean(row?['full_name']),
    );
  }

  /// True once both required components are stored separately.
  bool get hasComponents => firstName.isNotEmpty && lastName.isNotEmpty;

  bool get hasMiddleName => (middleName ?? '').isNotEmpty;

  /// `First Middle Last`, or `First Last` without a middle name. Falls back
  /// to the legacy `full_name` for records that haven't been separated yet.
  String get displayName {
    if (!hasComponents) return legacyFullName;
    return format(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
  }

  /// Name for greetings ("Hi, Juan"). Legacy names keep the previous
  /// first-word behaviour for display only; nothing is stored from it.
  String get givenName =>
      firstName.isNotEmpty ? firstName : legacyFullName.split(' ').first;

  /// Columns to write for a name. `middle_name` is stored as NULL (never an
  /// empty string) when the patient has no middle name; `full_name` keeps
  /// being written so screens that still read it stay correct. A legacy
  /// name without components only carries `full_name`, so it can never
  /// blank out separated columns.
  Map<String, Object?> toColumns() => hasComponents
      ? {
          'first_name': firstName,
          'middle_name': hasMiddleName ? middleName : null,
          'last_name': lastName,
          'full_name': displayName,
        }
      : {'full_name': legacyFullName};

  static String format({
    required String firstName,
    String? middleName,
    required String lastName,
  }) {
    return [
      firstName,
      middleName ?? '',
      lastName,
    ].map(normalize).where((part) => part.isNotEmpty).join(' ');
  }

  /// Trims and collapses internal whitespace.
  static String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
