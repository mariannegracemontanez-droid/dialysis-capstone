import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// What the public landing page may show about donations, and nothing more.
///
/// Anonymous visitors cannot read the `donations` table (it holds donor
/// emails and payment details). These two database functions return only
/// the display name ('Anonymous' for anonymous gifts), date and amount of
/// verified donations, and the verified totals -- see section 13 of
/// supabase_migration_donation_sandbox.sql.
class PublicDonationService {
  PublicDonationService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// How often the landing page refreshes. The page used to listen to the
  /// table in realtime, which required public read access to every row.
  static const refreshEvery = Duration(seconds: 20);

  Future<List<Map<String, String>>> fetchRecentDonations({int limit = 5}) async {
    final rows = await _client.rpc(
      'public_donation_feed',
      params: {'p_limit': limit},
    );
    return publicFeedToDisplay(List<Map<String, dynamic>>.from(rows as List));
  }

  Future<({int count, double total})> fetchTotals() async {
    final rows = await _client.rpc('public_donation_totals');
    final list = List<Map<String, dynamic>>.from(rows as List);
    return publicTotalsFromRows(list);
  }

  Stream<List<Map<String, String>>> recentDonations({int limit = 5}) =>
      pollEvery(refreshEvery, () => fetchRecentDonations(limit: limit));

  Stream<({int count, double total})> totals() =>
      pollEvery(refreshEvery, fetchTotals);
}

/// Same shape the landing page has always rendered.
List<Map<String, String>> publicFeedToDisplay(List<Map<String, dynamic>> rows) {
  return [
    for (final item in rows)
      {
        'name': (item['display_name'] as String?)?.trim().isNotEmpty == true
            ? item['display_name'] as String
            : 'Anonymous',
        'date': item['donated_at'] != null
            ? DateTime.parse(item['donated_at'].toString())
                .toLocal()
                .toString()
                .split(' ')[0]
            : '',
        'amount': '₱ ${item['amount'] ?? 0}',
        'status': 'Verified',
      },
  ];
}

({int count, double total}) publicTotalsFromRows(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return (count: 0, total: 0);
  final row = rows.first;
  return (
    count: int.tryParse(row['donation_count']?.toString() ?? '0') ?? 0,
    total: double.tryParse(row['total_amount']?.toString() ?? '0') ?? 0,
  );
}

/// Emits [fetch]'s result now and then every [every]. A failed fetch is
/// reported as a stream error and polling carries on.
Stream<T> pollEvery<T>(Duration every, Future<T> Function() fetch) async* {
  while (true) {
    try {
      yield await fetch();
    } catch (e, s) {
      yield* Stream<T>.error(e, s);
    }
    await Future<void>.delayed(every);
  }
}
