import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/center_donation_history_entry.dart';
import '../models/donation_record.dart';
import '../models/donation_summary.dart';
import '../models/fund_distribution.dart';

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

  /// Approves a donation via the approve_donation RPC: atomically flips its
  /// status, refuses to run if it isn't still pending (prevents a double
  /// click from double-processing it), and writes the audit trail -- all in
  /// one backend transaction rather than separate client-side requests.
  Future<void> approveDonation(String donationId) async {
    await _supabase.rpc('approve_donation', params: {'p_donation_id': donationId});
  }

  /// Rejects a donation via the reject_donation RPC. Same idempotency
  /// guard and audit trail as [approveDonation].
  Future<void> rejectDonation(String donationId) async {
    await _supabase.rpc('reject_donation', params: {'p_donation_id': donationId});
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
        .select('id, amount, allocation_type, status, created_at')
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: false);

    final shares = await _supabase
        .from('donation_allocations')
        .select('donation_id, amount, created_at, donations(status)')
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
        ),
    ];

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
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

  Future<List<Map<String, dynamic>>> fetchCenters() async {
    final response = await _supabase
        .from('clinics')
        .select('id, name')
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

  Future<void> deleteDonation(String donationId) async {
    await _supabase.from('donations').delete().eq('id', donationId);
  }
}
