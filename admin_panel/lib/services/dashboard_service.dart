import 'package:admin_panel/features/dashboard/dashboard_page.dart'
    show supabase;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/patient.dart';
import 'supabase_config.dart';

class DashboardService {
  final SupabaseClient client = SupabaseConfig.client;

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

  Future<int> getTotalPatients() async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return 0;

    final response = await client
        .from('patients')
        .select('id')
        .eq('clinic_id', clinicId);

    return (response as List).length;
  }

  Future<int> getPendingPatientsCount() async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return 0;

    final response = await client
        .from('patients')
        .select('id')
        .eq('clinic_id', clinicId)
        .eq('status', 'pending');

    return (response as List).length;
  }

  Future<Map<String, dynamic>?> getCurrentAdminInfo() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final response = await client
        .from('profiles')
        .select('full_name, clinics(name)')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) return null;

    return {
      'adminName': response['full_name'] ?? 'Admin',
      'clinicName': response['clinics']?['name'] ?? 'No clinic assigned',
    };
  }

  Future<List<Patient>> getPatientsByStatus(String status) async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return [];

    final response = await client
        .from('patients')
        .select('*, profiles(*)')
        .eq('clinic_id', clinicId)
        .eq('status', status)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Patient.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getMonthlyPatientData() async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return [];

    final now = DateTime.now();
    final data = <Map<String, dynamic>>[];

    for (int i = 4; i >= 0; i--) {
      final monthStart = DateTime(now.year, now.month - i, 1);
      final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);

      final response = await client
          .from('patients')
          .select('id')
          .eq('clinic_id', clinicId)
          .gte('created_at', monthStart.toIso8601String())
          .lt('created_at', nextMonth.toIso8601String());

      data.add({
        'month': _getMonthName(monthStart.month),
        'count': (response as List).length,
      });
    }

    return data;
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return months[month - 1];
  }

  Future<List<Map<String, dynamic>>> getTodaySchedules({
    required String clinicId,
  }) async {
    final today = DateTime.now();
    final weekday = _getWeekdayName(today.weekday);

    final weekly = await supabase
        .from('weekly_schedules')
        .select('patient_id')
        .eq('clinic_id', clinicId)
        .contains('scheduled_days', [weekday]);

    if (weekly.isEmpty) return [];

    final patientIds = weekly.map((e) => e['patient_id']).toList();

    final response = await supabase
        .from('patients')
        .select()
        .inFilter('id', patientIds);

    return List<Map<String, dynamic>>.from(response);
  }

  String _getWeekdayName(int weekday) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[weekday - 1];
  }

  // Recurring schedule creation now lives in CenterScheduleService
  // (setPatientRecurringSchedule -> set_patient_recurring_schedule), since
  // a schedule always carries a default shift per day and CenterScheduleService
  // owns the shift/capacity data needed to validate that.

  // Removing a patient from a day's schedule lives in
  // CenterScheduleService.cancelDateOccurrence. It must never be a DELETE:
  // generateTodayDefaultSchedule re-creates a deleted row from the
  // patient's recurring schedule on the next refresh, so the row is
  // cancelled in place instead and acts as that date's one-day override.

  /// The center's most recent *received* donation, across every source the
  /// "Received" total is built from: the Super Admin's manual
  /// fund_distributions ledger, verified donations sent directly to this
  /// clinic (specific/random allocation), and this clinic's share of
  /// verified equal-distribution donations.
  ///
  /// This used to read fund_distributions alone, so a donor-driven donation
  /// moved the Received total without ever becoming the "Latest Donation" --
  /// the card then reported an older manual distribution and that row's
  /// distribution_date as the date received. Each source is matched here the
  /// same way getTotalDonations / getAllocatedDonationTotal match it
  /// (center_name for the manual ledger, clinic_id for the donor flow), so
  /// "latest" is always the newest of exactly what the total counts.
  ///
  /// Pending and rejected donations are excluded for the same reason they
  /// are excluded from the total: the center has not received them.
  ///
  /// Returns a normalized row -- amount, received_at, remarks, source -- or
  /// null when the center has received nothing yet.
  Future<Map<String, dynamic>?> getLatestDonation({
    required String centerName,
    String? clinicId,
  }) async {
    final candidates = <Map<String, dynamic>>[];

    void addCandidate({
      required dynamic amount,
      required dynamic receivedAt,
      required String source,
      dynamic remarks,
    }) {
      final parsedDate = DateTime.tryParse(receivedAt?.toString() ?? '');
      if (parsedDate == null) return;

      // Sources store this differently -- timestamptz comes back UTC, a
      // plain date comes back local -- so ordering compares UTC instants
      // while the returned value is local, which is the wall-clock date the
      // center actually received the funds on.
      candidates.add({
        'amount': _toNum(amount),
        'received_at': parsedDate.toLocal().toIso8601String(),
        'remarks': remarks,
        'source': source,
        '_sort_at': parsedDate.toUtc(),
      });
    }

    // 1. Manual Super Admin distribution.
    //
    //    Ordered by created_at, NOT distribution_date: distribution_date is
    //    null on every ledger row written before that column was added to
    //    the Super Admin insert, and Postgres orders DESC as NULLS FIRST --
    //    so "order by distribution_date desc, limit 1" handed back one of
    //    those null-dated rows as the "latest", which is what made this card
    //    show an old amount with an N/A date. created_at is populated on
    //    every row and is what the Super Admin app orders this ledger by.
    final manual = await client
        .from('fund_distributions')
        .select('amount, distribution_date, created_at, remarks')
        .eq('center_name', centerName)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (manual != null) {
      addCandidate(
        amount: manual['amount'],
        // distribution_date is the real "pushed to the center" moment when
        // it is set; created_at stands in for the older rows that lack it.
        receivedAt: manual['distribution_date'] ?? manual['created_at'],
        source: 'fund_distribution',
        remarks: manual['remarks'],
      );
    }

    if (clinicId != null) {
      // 2. Specific / random donations, which resolve to this clinic_id
      //    directly. created_at is the received timestamp: the donor flow
      //    writes the row at submission time and the status column is what
      //    marks it as usable by the center.
      final direct = await client
          .from('donations')
          .select('amount, created_at')
          .eq('clinic_id', clinicId)
          .eq('status', 'verified')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (direct != null) {
        addCandidate(
          amount: direct['amount'],
          receivedAt: direct['created_at'],
          source: 'donation',
        );
      }

      // 3. This clinic's share of an equal-distribution donation. The share
      //    row itself carries no status, so the parent donation's status is
      //    what decides whether it counts -- same join and same in-Dart
      //    status check getAllocatedDonationTotal already uses.
      final shares = await client
          .from('donation_allocations')
          .select('amount, created_at, donations(status)')
          .eq('clinic_id', clinicId)
          .order('created_at', ascending: false);

      for (final item in shares) {
        final parent = item['donations'];
        final parentStatus = parent is Map ? parent['status'] : null;

        if (parentStatus != 'verified') continue;

        addCandidate(
          amount: item['amount'],
          receivedAt: item['created_at'],
          source: 'donation_allocation',
        );
        break;
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort(
      (a, b) => (b['_sort_at'] as DateTime).compareTo(a['_sort_at'] as DateTime),
    );

    final latest = Map<String, dynamic>.from(candidates.first)
      ..remove('_sort_at');

    return latest;
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<num> getTotalDonations(String centerName) async {
    final response = await client
        .from('fund_distributions')
        .select('amount')
        .eq('center_name', centerName);

    num total = 0;

    for (final item in response) {
      total += item['amount'] ?? 0;
    }

    return total;
  }

  Future<List<Map<String, dynamic>>> getDonationHistory(
    String centerName,
  ) async {
    final response = await client
        .from('fund_distributions')
        .select()
        .eq('center_name', centerName)
        .order('distribution_date', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// The center's real received total from the donor-driven donation flow:
  /// verified donations sent directly to this clinic (specific/random
  /// allocation) plus this clinic's share of verified equal-distribution
  /// donations. This is separate from -- and additive with -- the manual
  /// fund_distributions ledger above, so existing manually-distributed
  /// amounts are never dropped from the center's total.
  Future<num> getAllocatedDonationTotal(String clinicId) async {
    num total = 0;

    final direct = await client
        .from('donations')
        .select('amount')
        .eq('clinic_id', clinicId)
        .eq('status', 'verified');

    for (final item in direct) {
      total += (item['amount'] as num?) ?? 0;
    }

    final shares = await client
        .from('donation_allocations')
        .select('amount, donations(status)')
        .eq('clinic_id', clinicId);

    for (final item in shares) {
      final parent = item['donations'];
      final parentStatus = parent is Map ? parent['status'] : null;

      if (parentStatus == 'verified') {
        total += (item['amount'] as num?) ?? 0;
      }
    }

    return total;
  }
}
