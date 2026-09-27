import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/clinic_announcement.dart';
import 'patient_service.dart';

/// The patient's current clinic, with the information its Center Admin
/// publishes for patients: the house rules and the announcements.
class ClinicInfo {
  final String clinicId;
  final String clinicName;
  final String houseRules;
  final List<ClinicAnnouncement> announcements;

  const ClinicInfo({
    required this.clinicId,
    required this.clinicName,
    required this.houseRules,
    required this.announcements,
  });

  bool get hasHouseRules => houseRules.trim().isNotEmpty;
}

/// Read-only access to what the Center Admin writes for patients.
///
/// Reads existing data only: `clinics.house_rules` (Center Profile page)
/// and `patient_announcements` (Announcements section). RLS already limits
/// announcements to the signed-in patient's own center; the clinic filter
/// here selects the patient's current (active) clinic among them.
class ClinicInfoService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  static const int _announcementLimit = 20;

  /// Returns null when the user has no active clinic.
  Future<ClinicInfo?> getMyClinicInfo() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final patient = await PatientService().getActivePatientRow(user.id);
    final clinicId = patient?['clinic_id']?.toString();
    if (clinicId == null || clinicId.isEmpty) return null;

    // Both requests run in parallel.
    final announcementsFuture = _getAnnouncements(clinicId);
    final Map<String, dynamic>? clinic = await _supabase
        .from('clinics')
        .select('id, name, house_rules')
        .eq('id', clinicId)
        .maybeSingle();

    return ClinicInfo(
      clinicId: clinicId,
      clinicName: clinic?['name']?.toString() ?? 'Your clinic',
      houseRules: clinic?['house_rules']?.toString().trim() ?? '',
      announcements: await announcementsFuture,
    );
  }

  Future<List<ClinicAnnouncement>> _getAnnouncements(String clinicId) async {
    try {
      final rows = await _supabase
          .from('patient_announcements')
          .select('id, title, body, announcement_date, color, created_at')
          .eq('clinic_id', clinicId)
          .order('created_at', ascending: false)
          .limit(_announcementLimit);

      return (rows as List)
          .map(
            (row) => ClinicAnnouncement.fromJson(row as Map<String, dynamic>),
          )
          .where((a) => a.title.isNotEmpty || a.body.isNotEmpty)
          .toList();
    } catch (e) {
      // Keep the house rules usable even if announcements fail to load.
      debugPrint('Get clinic announcements error: $e');
      return [];
    }
  }
}
