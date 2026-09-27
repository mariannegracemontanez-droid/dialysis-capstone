/// One clinic announcement, as stored in the `patient_announcements` table
/// that the Center Admin writes from the admin panel
/// (admin_panel/supabase/patient_announcements.sql).
class ClinicAnnouncement {
  final String id;
  final String title;
  final String body;

  /// Optional. Set only when the notice is about a specific day (an event,
  /// a closure). It is not the publish date; that is [createdAt].
  final DateTime? announcementDate;

  /// A theme token (`blue`, `light_blue`, `green`, `orange`, `purple`,
  /// `red`), never a hex value, so each client renders it in its own
  /// palette.
  final String color;

  final DateTime? createdAt;

  const ClinicAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.color,
    this.announcementDate,
    this.createdAt,
  });

  factory ClinicAnnouncement.fromJson(Map<String, dynamic> json) {
    return ClinicAnnouncement(
      id: json['id'].toString(),
      title: json['title']?.toString().trim() ?? '',
      body: json['body']?.toString().trim() ?? '',
      announcementDate: _date(json['announcement_date']),
      color: json['color']?.toString().trim().toLowerCase() ?? 'blue',
      createdAt: _date(json['created_at'])?.toLocal(),
    );
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
