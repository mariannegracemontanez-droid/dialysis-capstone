import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/center_model.dart';
import '../models/donation_summary.dart';
import '../models/notification_item.dart';

class DashboardService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  String computeStatus(int availableSlots) {
    if (availableSlots == 0) return 'full';
    if (availableSlots <= 2) return 'busy';
    return 'open';
  }

  List<String> _parseRequirements(String requirements) {
    return requirements
        .split(RegExp(r'[,;\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  bool _isVerifiedDonation(Map<String, dynamic> record) {
    final status = record['status']?.toString().toLowerCase().trim() ?? '';
    return status == 'verified';
  }

  int _parseDonationAmount(Map<String, dynamic> record) {
    final amount = double.tryParse(record['amount']?.toString() ?? '0') ?? 0.0;
    return amount.toInt();
  }

  Future<int> fetchVerifiedDonationTotal() async {
    final response = await _supabase.from('donations').select('amount, status');

    final donations = response as List<dynamic>;

    int totalDonations = 0;

    for (final item in donations) {
      final record = item as Map<String, dynamic>;

      if (!_isVerifiedDonation(record)) continue;

      totalDonations += _parseDonationAmount(record);
    }

    return totalDonations;
  }

  Future<Map<String, int>> fetchOverviewStats() async {
    final patients = await _supabase.from('patients').select('id');
    final appointments = await _supabase.from('appointments').select('id');
    final centers = await _supabase.from('clinics').select('id');

    final totalDonations = await fetchVerifiedDonationTotal();

    return {
      'patients': (patients as List).length,
      'appointments': (appointments as List).length,
      'centers': (centers as List).length,
      'donations': totalDonations,
    };
  }

  Future<List<CenterModel>> fetchCenters() async {
    final response = await _supabase
        .from('clinics')
        .select()
        .or('status.is.null,status.neq.closed')
        .order('created_at', ascending: false);

    final list = response as List<dynamic>;

    return list
        .map(
          (postgres) => CenterModel.fromJson(postgres as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<NotificationItem>> fetchNotifications() async {
    final response = await _supabase
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(6);

    final list = response as List<dynamic>;

    return list
        .map((item) => NotificationItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<DonationSummary>> fetchDonationSummary() async {
    final totalDonations = await fetchVerifiedDonationTotal();

    return [
      DonationSummary(
        centerName: 'Total Verified Donations',
        totalAmount: totalDonations.toDouble(),
      ),
    ];
  }

  Future<void> createCenter({
    required String name,
    required String address,
    required String city,
    required String requirements,
    required double latitude,
    required double longitude,
    required int slotAvailable,
    required int machines,
    required int shifts,
    required String operatingHours,
    required String contactNumber,
  }) async {
    final status = computeStatus(slotAvailable);

    await _supabase.from('clinics').insert({
      'name': name,
      'address': address,
      'city': city,
      'requirements': _parseRequirements(requirements),
      'latitude': latitude,
      'longitude': longitude,
      'slots_available': slotAvailable,
      'machine': machines,
      'shifts': shifts,
      'status': status,
      'operating_hours': operatingHours,
      'contact_number': contactNumber,
    });
  }

  Future<void> updateCenter({
    required String centerId,
    required String name,
    required String address,
    required String city,
    required String requirements,
    required double latitude,
    required double longitude,
    required int slotAvailable,
    required int machines,
    required int shifts,
    required String operatingHours,
    required String contactNumber,
  }) async {
    final status = computeStatus(slotAvailable);

    await _supabase
        .from('clinics')
        .update({
          'name': name,
          'address': address,
          'city': city,
          'requirements': _parseRequirements(requirements),
          'latitude': latitude,
          'longitude': longitude,
          'slots_available': slotAvailable,
          'machine': machines,
          'shifts': shifts,
          'status': status,
          'operating_hours': operatingHours,
          'contact_number': contactNumber,
        })
        .eq('id', centerId);
  }

  Future<void> deleteCenter(String centerId) async {
    await _supabase.from('clinics').delete().eq('id', centerId);
  }
}
