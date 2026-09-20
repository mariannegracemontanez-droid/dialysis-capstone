/// One patient-facing announcement, as stored in the
/// `patient_announcements` table (admin_panel/supabase/patient_announcements.sql).
///
/// The same rows the CureNurture mobile app reads for the patient's own
/// center, so the shape here is deliberately plain: no admin-only fields,
/// no derived state that a second client would have to recompute.
class Announcement {
  final String id;
  final String clinicId;
  final String title;
  final String body;

  /// Optional. Set only when the notice is about a specific day -- an
  /// event, a closure, a schedule change. Null for a general notice.
  ///
  /// This is not the publish date; that is [createdAt].
  final DateTime? announcementDate;

  /// A theme token, not a colour value. See [AnnouncementColor].
  final String color;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Announcement({
    required this.id,
    required this.clinicId,
    required this.title,
    required this.body,
    required this.color,
    this.announcementDate,
    this.createdAt,
    this.updatedAt,
  });

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'].toString(),
      clinicId: json['clinic_id']?.toString() ?? '',
      title: _text(json['title']),
      body: _text(json['body']),
      announcementDate: _date(json['announcement_date']),
      color: AnnouncementColor.normalize(json['color']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  /// True when the announcement carries a date that has not passed yet.
  /// Presentation only -- nothing is hidden or expired on the strength of
  /// it, since a past-dated notice may still be worth reading.
  bool get isUpcoming {
    final date = announcementDate;
    if (date == null) return false;

    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return !date.isBefore(startOfToday);
  }

  Announcement copyWith({
    String? title,
    String? body,
    DateTime? announcementDate,
    bool clearDate = false,
    String? color,
  }) {
    return Announcement(
      id: id,
      clinicId: clinicId,
      title: title ?? this.title,
      body: body ?? this.body,
      announcementDate: clearDate
          ? null
          : (announcementDate ?? this.announcementDate),
      color: color ?? this.color,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// The announcement colour vocabulary.
///
/// These tokens are the contract with the database check constraint and
/// with the mobile app -- the stored value is a name, never a hex string,
/// so each client renders it from its own palette.
class AnnouncementColor {
  const AnnouncementColor._();

  static const String blue = 'blue';
  static const String lightBlue = 'light_blue';
  static const String green = 'green';
  static const String orange = 'orange';
  static const String purple = 'purple';
  static const String red = 'red';

  /// Every token the database accepts, in the order the picker shows them.
  static const List<String> all = [lightBlue, blue, green, orange, purple, red];

  /// Short human label for the picker.
  static String label(String token) {
    switch (token) {
      case lightBlue:
        return 'Light blue';
      case blue:
        return 'Blue';
      case green:
        return 'Green';
      case orange:
        return 'Orange';
      case purple:
        return 'Purple';
      case red:
        return 'Urgent';
      default:
        return 'Blue';
    }
  }

  /// What each colour is meant to say, shown under the picker so the
  /// choice is about meaning rather than taste.
  static String meaning(String token) {
    switch (token) {
      case lightBlue:
        return 'A gentle, general notice.';
      case blue:
        return 'General center information.';
      case green:
        return 'Positive or confirmed news.';
      case orange:
        return 'A reminder that needs attention.';
      case purple:
        return 'Administrative information.';
      case red:
        return 'Urgent — closures and emergencies.';
      default:
        return 'General center information.';
    }
  }

  /// Falls back to [blue] for anything unrecognised, so a token added by a
  /// newer build never renders as a broken card here.
  static String normalize(dynamic value) {
    final token = value?.toString().trim().toLowerCase();
    if (token == null || !all.contains(token)) return blue;
    return token;
  }
}
