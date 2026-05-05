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
        .select()
        .order('created_at', ascending: false);

    final list = response as List<dynamic>;
    return list
        .map((item) => DonationRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<DonationSummary>> fetchDonationSummary() async {
    final response = await _supabase.from('donations').select('center_name, clinic_name, amount');
    final list = response as List<dynamic>;
    final totals = <String, double>{};

    for (final item in list) {
      final record = item as Map<String, dynamic>;
      final centerName = record['center_name']?.toString() ?? record['clinic_name']?.toString() ?? 'Unknown Center';
      final amount = double.tryParse(record['amount']?.toString() ?? '') ?? 0.0;
      totals[centerName] = (totals[centerName] ?? 0) + amount;
    }

    return totals.entries
        .map((entry) => DonationSummary(centerName: entry.key, totalAmount: entry.value))
        .toList();
  }

  Future<int> fetchDonorCount() async {
    final response = await _supabase.from('donors').select('id');
    return (response as List).length;
  }

  Future<List<String>> fetchCenterNames() async {
    final response = await _supabase.from('clinics').select('name');
    final list = response as List<dynamic>;
    return list
        .map((item) => (item as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<List<FundDistribution>> fetchFundDistributions() async {
    final response = await _supabase.from('fund_distributions').select().order('created_at', ascending: false);
    final list = response as List<dynamic>;
    return list
        .map((item) => FundDistribution.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createFundDistribution({
    required String centerName,
    required double amount,
    required String remarks,
  }) async {
    await _supabase.from('fund_distributions').insert({
      'center_name': centerName,
      'amount': amount,
      'remarks': remarks,
      'status': 'Distributed',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

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

  Future<void> deleteDonation(String donationId) async {
    await _supabase.from('donations').delete().eq('id', donationId);
  }
}
