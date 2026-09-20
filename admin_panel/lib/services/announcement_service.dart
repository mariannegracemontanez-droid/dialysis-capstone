import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/announcement.dart';

/// Center Admin side of Patient Announcements.
///
/// Reads and writes the `patient_announcements` table only. It never
/// touches patients, schedules, donations or any other existing table,
/// and holds no logic that another part of the app depends on.
///
/// RLS scopes every statement to the signed-in admin's own clinic, and a
/// database trigger fills `clinic_id` and `created_by` on insert -- so the
/// clinic id passed in here is a read filter, never the security boundary.
class AnnouncementService {
  final SupabaseClient supabase = Supabase.instance.client;

  static const String table = 'patient_announcements';

  /// The columns both this panel and the mobile app read. Listed
  /// explicitly rather than `*` so a column added later doesn't silently
  /// widen the payload.
  static const String _columns =
      'id, clinic_id, title, body, announcement_date, color, '
      'created_at, updated_at';

  /// This center's announcements, newest first -- the same order the
  /// mobile app feed uses.
  Future<List<Announcement>> getAnnouncements({
    required String clinicId,
    int limit = 50,
  }) async {
    final rows = await supabase
        .from(table)
        .select(_columns)
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((row) => Announcement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Creates one announcement and returns it as stored.
  ///
  /// [date] is optional: pass null for a notice that isn't about a
  /// particular day. Only the date part is kept -- an announcement is
  /// never about a time of day.
  Future<Announcement> createAnnouncement({
    required String clinicId,
    required String title,
    required String body,
    DateTime? date,
    required String color,
  }) async {
    final row = await supabase
        .from(table)
        .insert({
          'clinic_id': clinicId,
          'title': title.trim(),
          'body': body.trim(),
          'announcement_date': _isoDate(date),
          'color': AnnouncementColor.normalize(color),
        })
        .select(_columns)
        .single();

    return Announcement.fromJson(row);
  }

  /// Updates one announcement. [clearDate] removes a date that was set
  /// before, which a plain null [date] cannot express.
  Future<Announcement> updateAnnouncement({
    required String id,
    required String title,
    required String body,
    DateTime? date,
    bool clearDate = false,
    required String color,
  }) async {
    final row = await supabase
        .from(table)
        .update({
          'title': title.trim(),
          'body': body.trim(),
          'announcement_date': clearDate ? null : _isoDate(date),
          'color': AnnouncementColor.normalize(color),
        })
        .eq('id', id)
        .select(_columns)
        .single();

    return Announcement.fromJson(row);
  }

  Future<void> deleteAnnouncement(String id) async {
    await supabase.from(table).delete().eq('id', id);
  }

  static String? _isoDate(DateTime? date) {
    if (date == null) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().split('T')[0];
  }
}
