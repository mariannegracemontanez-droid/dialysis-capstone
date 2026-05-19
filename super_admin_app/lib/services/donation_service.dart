import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/donation_record.dart';
import '../models/donation_summary.dart';
import '../models/fund_distribution.dart';

class DonationService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<List<DonationRecord>> fetchDonations() async {
    final response = await _supabase
        .from('donations')
        .select('*')
        .order('created_at', ascending: false);

    final list = response as List<dynamic>;

    return list
        .map((item) => DonationRecord.fromJson(item as Map<String, dynamic>))
        .toList();
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
