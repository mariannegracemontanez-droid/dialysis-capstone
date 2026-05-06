import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/donation_record.dart';
import '../models/donation_summary.dart';
import '../models/fund_distribution.dart';

class DonationService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  // 🔥 FETCH ALL DONATIONS
  Future<List<DonationRecord>> fetchDonations() async {
    final response = await _supabase
        .from('donations')
        .select('*')
        .order('created_at', ascending: false);

    final list = response as List<dynamic>;

    return list
        .map((e) => DonationRecord.fromJson(e))
        .toList();
  }

  // 🔥 TOTAL VERIFIED DONATIONS
  Future<double> fetchTotalDonations() async {
    final data = await _supabase
        .from('donations')
        .select('amount')
        .eq('status', 'verified');

    double total = 0;

    for (final item in data) {
      total += double.tryParse(item['amount'].toString()) ?? 0;
    }

    return total;
  }

  // 🔥 TOTAL DISTRIBUTED
  Future<double> fetchTotalDistributed() async {
    final data = await _supabase
        .from('fund_distributions')
        .select('amount');

    double total = 0;

    for (final item in data) {
      total += double.tryParse(item['amount'].toString()) ?? 0;
    }

    return total;
  }

  // 🔥 SUMMARY (FOR GRAPH / UI)
  Future<List<DonationSummary>> fetchDonationSummary() async {
    final totalDonations = await fetchTotalDonations();
    final totalDistributed = await fetchTotalDistributed();

    final remaining = totalDonations - totalDistributed;

    return [
      DonationSummary(
        centerName: 'Available Funds',
        totalAmount: remaining,
      ),
    ];
  }

  // 🔥 DONOR COUNT
  Future<int> fetchDonorCount() async {
    final response = await _supabase.from('donors').select('id');
    return (response as List).length;
  }

  // 🔥 FETCH CENTER NAMES
  Future<List<Map<String, dynamic>>> fetchCenters() async {
  final response = await _supabase
      .from('clinics')
      .select('id, name');

  return List<Map<String, dynamic>>.from(response);
}

  // 🔥 FETCH DISTRIBUTIONS (AUDIT LOG)
  Future<List<FundDistribution>> fetchFundDistributions() async {
    final response = await _supabase
        .from('fund_distributions')
        .select()
        .order('created_at', ascending: false);

    final list = response as List<dynamic>;

    return list
        .map((item) =>
            FundDistribution.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // 🔥 CREATE DISTRIBUTION
  Future<void> createFundDistribution({
  required String clinicId,
  required String centerName,
  required double amount,
  required String remarks,
}) async {
  await _supabase.from('fund_distributions').insert({
    'clinic_id': clinicId,
    'center_name': centerName,
    'amount': amount,
    'remarks': remarks,
    'status': 'Distributed',
    'created_at': DateTime.now().toIso8601String(),
  });
}

  // 🔥 CREATE DONATION (OPTIONAL)
  Future<void> createDonation({
    required String donorName,
    required String clinicName,
    required double amount,
    required String status,
  }) async {
    await _supabase.from('donations').insert({
      'donor_name': donorName,
      'clinic_name': clinicName,
      'amount': amount,
      'status': status,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // 🔥 DELETE DONATION
  Future<void> deleteDonation(String donationId) async {
    await _supabase.from('donations').delete().eq('id', donationId);
  }
}