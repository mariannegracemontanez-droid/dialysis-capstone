import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/center_donation_history_entry.dart';
import '../models/donation_record.dart';
import '../models/donation_summary.dart';
import '../models/fund_distribution.dart';
import '../models/received_donation_record.dart';

class DonationService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<List<DonationRecord>> fetchDonations() async {
    final response = await _supabase
        .from('donations')
        .select('*, clinics(name)')
        .order('created_at', ascending: false);

    final list = response as List<dynamic>;

    return list
        .map((item) => DonationRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// The per-center breakdown for an equal-distribution donation. Empty for
  /// specific/random donations, which resolve to a single
  /// donations.clinic_id instead.
  Future<List<DonationAllocation>> fetchAllocationsForDonation(
    String donationId,
  ) async {
    final response = await _supabase
        .from('donation_allocations')
        .select('*, clinics(name)')
        .eq('donation_id', donationId)
        .order('amount', ascending: false);

    return (response as List<dynamic>)
        .map((item) => DonationAllocation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// A single center's donation history: every specific/random donation
  /// sent directly to it, plus its share of every equal-distribution
  /// donation -- normalized into one list for the Center Donation History
  /// section.
  Future<List<CenterDonationHistoryEntry>> fetchCenterDonationHistory(
    String clinicId,
  ) async {
    final direct = await _supabase
        .from('donations')
        .select('id, amount, allocation_type, status, created_at, name, email')
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: false);

    final shares = await _supabase
        .from('donation_allocations')
        .select('donation_id, amount, created_at, donations(status, name, email)')
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: false);

    final entries = <CenterDonationHistoryEntry>[
      for (final item in (direct as List<dynamic>))
        CenterDonationHistoryEntry(
          donationId: item['id'].toString(),
          amount: double.tryParse(item['amount'].toString()) ?? 0.0,
          allocationType: item['allocation_type']?.toString() ?? 'specific_center',
          status: item['status']?.toString() ?? 'pending',
          date: DateTime.tryParse(item['created_at'].toString()) ?? DateTime.now(),
          donorName: item['name']?.toString(),
          donorEmail: item['email']?.toString(),
        ),
      for (final item in (shares as List<dynamic>))
        CenterDonationHistoryEntry(
          donationId: item['donation_id'].toString(),
          amount: double.tryParse(item['amount'].toString()) ?? 0.0,
          allocationType: 'equal_distribution',
          status: (item['donations'] is Map
                  ? item['donations']['status']?.toString()
                  : null) ??
              'pending',
          date: DateTime.tryParse(item['created_at'].toString()) ?? DateTime.now(),
          donorName: item['donations'] is Map
              ? item['donations']['name']?.toString()
              : null,
          donorEmail: item['donations'] is Map
              ? item['donations']['email']?.toString()
              : null,
        ),
    ];

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  /// Every amount a center has actually RECEIVED, i.e. exactly the records
  /// behind the Admin Dashboard's "Donation Funds" total
  /// (admin_panel DashboardService.getTotalDonations +
  /// getAllocatedDonationTotal), using the same three sources and the same
  /// matching:
  ///
  ///   1. fund_distributions  -- matched by center_name
  ///   2. donations           -- status 'verified', matched by clinic_id
  ///   3. donation_allocations -- parent donation status 'verified',
  ///                              matched by clinic_id
  ///
  /// Pending and rejected donations are excluded, as they are on the
  /// dashboard: the center has not received them. Donations with no center
  /// (legacy rows before allocation tracking) are not part of any center's
  /// total, so they are not returned either.
  ///
  /// Pass [clinicId] and [centerName] for one center; omit both for every
  /// center, in which case each center's records are returned side by side
  /// (an equal-distribution donation appears once per center, at that
  /// center's share), so the grand total is the sum of the center totals.
  Future<List<ReceivedDonationRecord>> fetchReceivedDonations({
    String? clinicId,
    String? centerName,
  }) async {
    assert(
      (clinicId == null) == (centerName == null),
      'Pass both clinicId and centerName for one center, or neither.',
    );

    var directQuery = _supabase
        .from('donations')
        .select('*, clinics(name)')
        .eq('status', 'verified')
        .not('clinic_id', 'is', null);
    if (clinicId != null) directQuery = directQuery.eq('clinic_id', clinicId);

    var sharesQuery = _supabase.from('donation_allocations').select(
          'donation_id, clinic_id, amount, created_at, clinics(name), '
          'donations(status, donor_id, name, email)',
        );
    if (clinicId != null) sharesQuery = sharesQuery.eq('clinic_id', clinicId);

    var manualQuery = _supabase.from('fund_distributions').select();
    if (centerName != null) {
      manualQuery = manualQuery.eq('center_name', centerName);
    }

    final results = await Future.wait([directQuery, sharesQuery, manualQuery]);

    final records = <ReceivedDonationRecord>[];

    // 1. Direct specific/random donations. DonationRecord.fromJson applies
    //    the existing anonymous-donor rule.
    for (final item in results[0]) {
      final donation = DonationRecord.fromJson(item);
      records.add(
        ReceivedDonationRecord(
          sourceId: donation.id,
          source: ReceivedDonationSource.direct,
          date: donation.createdAt,
          amount: donation.amount,
          centerName: donation.clinicName ?? centerName ?? 'Unnamed Center',
          allocationType: donation.allocationType,
          donorName: donation.isAnonymous ? null : donation.donorName,
          donorEmail: donation.email,
          isAnonymous: donation.isAnonymous,
        ),
      );
    }

    // 2. Equal-distribution shares. The share row has no status of its own,
    //    so the parent donation's status decides -- the same in-Dart check
    //    the Admin Dashboard makes.
    for (final item in results[1]) {
      final parent = item['donations'];
      if (parent is! Map || parent['status'] != 'verified') continue;

      final name = parent['name']?.toString();
      final email = parent['email']?.toString();
      final anonymous = DonationRecord.isAnonymousDonor(
        donorId: parent['donor_id'],
        name: name,
        email: email,
      );
      final clinic = item['clinics'];

      records.add(
        ReceivedDonationRecord(
          sourceId: item['donation_id']?.toString() ?? '',
          source: ReceivedDonationSource.equalShare,
          date: DateTime.tryParse(item['created_at']?.toString() ?? '') ??
              DateTime.now(),
          amount: double.tryParse(item['amount'].toString()) ?? 0.0,
          centerName: (clinic is Map ? clinic['name']?.toString() : null) ??
              centerName ??
              'Unnamed Center',
          allocationType: 'equal_distribution',
          donorName: anonymous ? null : name,
          donorEmail: anonymous ? null : email,
          isAnonymous: anonymous,
        ),
      );
    }

    // 3. Super Admin manual distributions.
    for (final item in results[2]) {
      final distribution = FundDistribution.fromJson(item);
      records.add(
        ReceivedDonationRecord(
          sourceId: distribution.id,
          source: ReceivedDonationSource.manualDistribution,
          date: distribution.receivedAt,
          amount: distribution.amount,
          centerName: distribution.centerName,
        ),
      );
    }

    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
  }

  Future<double> fetchTotalDonations() async {
    final data = await _supabase
        .from('donations')
        .select('amount')
        .eq('status', 'verified');

    double total = 0;

    for (final item in data) {
      final amount = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
      total += amount;
    }

    return total;
  }

  Future<double> fetchTotalDistributed() async {
    final data = await _supabase.from('fund_distributions').select('amount');

    double total = 0;

    for (final item in data) {
      final amount = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
      total += amount;
    }

    return total;
  }

  Future<List<DonationSummary>> fetchDonationSummary() async {
    final totalDonations = await fetchTotalDonations();
    final totalDistributed = await fetchTotalDistributed();
    final remaining = (totalDonations - totalDistributed)
        .clamp(0, double.infinity)
        .toDouble();

    return [
      DonationSummary(centerName: 'Available Funds', totalAmount: remaining),
    ];
  }

  Future<int> fetchDonorCount() async {
    final response = await _supabase.from('donors').select('id');
    return (response as List).length;
  }

  /// Centers offered by the Super Admin donation-history SELECTORS.
  ///
  /// Soft-closed centers are excluded, using the same filter every other
  /// clinic query in this app already applies -- this was the only live one
  /// still missing it, so a closed center could be picked from the history
  /// selectors and could even become the default selection.
  ///
  /// This does NOT hide any donation. The Overall Donation History "All
  /// Centers" view builds from the donation records themselves, and each
  /// row's center name comes from the clinics join on the donation, so a
  /// closed center's donations stay visible and correctly attributed there.
  /// Only the center-picker lists stop offering closed centers.
  Future<List<Map<String, dynamic>>> fetchCenters() async {
    final response = await _supabase
        .from('clinics')
        .select('id, name')
        .or('status.is.null,status.neq.closed')
        .order('name', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<FundDistribution>> fetchFundDistributions() async {
    final response = await _supabase
        .from('fund_distributions')
        .select()
        .order('created_at', ascending: false);

    final list = response as List<dynamic>;

    return list
        .map((item) => FundDistribution.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createFundDistribution({
    required String clinicId,
    required String centerName,
    required double amount,
    required String remarks,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    final now = DateTime.now().toIso8601String();

    await _supabase.from('fund_distributions').insert({
      'clinic_id': clinicId,
      'center_name': centerName,
      'amount': amount,
      'remarks': remarks,
      'status': 'Distributed',
      'distributed_by': adminId,
      'distribution_date': now,
      'created_at': now,
    });
  }

  Future<void> createDonation({
    required String donorName,
    required String clinicName,
    required double amount,
    required String status,
  }) async {
    await _supabase.from('donations').insert({
      'name': donorName,
      'amount': amount,
      'status': status,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
