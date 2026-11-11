import 'dart:convert';

import 'package:admin_panel/services/dashboard_service.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Runs the real DashboardService against an in-memory stand-in for PostgREST.
/// The rows mirror what create_donation_checkout / donation_finalize write
/// (Donation/supabase_migration_donation_sandbox.sql). Only the columns a
/// query selects are returned, so a query that forgets to embed a column it
/// depends on fails here too.

const clinicA = 'clinic-a';
const clinicB = 'clinic-b';
const clinicC = 'clinic-c';

class _Backend {
  final tables = <String, List<Map<String, dynamic>>>{
    'donations': [],
    'donation_allocations': [],
    'fund_distributions': [],
  };
  final methods = <String>{};
  int _nextId = 0;

  void reset() {
    tables.forEach((_, rows) => rows.clear());
    methods.clear();
    paths.clear();
  }

  /// Adds a donation and its allocation rows. [shares] maps clinic id to
  /// amount; a single entry with [split] false is a specific/random donation,
  /// which also keeps donations.clinic_id set.
  void addDonation({
    required String status,
    required Map<String, num> shares,
    bool split = false,
    String? paymentStatus,
    String? paymentEnvironment,
    String createdAt = '2026-11-01T00:00:00Z',
  }) {
    final id = 'donation-${_nextId++}';
    tables['donations']!.add({
      'id': id,
      'amount': shares.values.fold<num>(0, (sum, value) => sum + value),
      'status': status,
      'payment_status': paymentStatus,
      'payment_environment': paymentEnvironment,
      'clinic_id': split ? null : shares.keys.single,
      'created_at': createdAt,
    });
    shares.forEach((clinicId, amount) {
      tables['donation_allocations']!.add({
        'donation_id': id,
        'clinic_id': clinicId,
        'amount': amount,
        'created_at': createdAt,
      });
    });
  }

  void addSimulatedPaid(
    Map<String, num> shares, {
    bool split = false,
    String createdAt = '2026-11-01T00:00:00Z',
  }) {
    addDonation(
      status: 'pending',
      paymentStatus: 'simulated_paid',
      paymentEnvironment: 'sandbox',
      shares: shares,
      split: split,
      createdAt: createdAt,
    );
  }

  /// Every table / view the service requested.
  final paths = <String>{};

  /// The privacy-safe center-admin views (Donation v5 migration) over the
  /// in-memory tables: donations as-is; allocations with the parent donation's
  /// status fields flattened in, as center_admin_allocations returns them.
  List<Map<String, dynamic>> _source(String table) {
    switch (table) {
      case 'center_admin_donations':
        return tables['donations']!;
      case 'center_admin_allocations':
        return [
          for (final a in tables['donation_allocations']!)
            () {
              final d = tables['donations']!.firstWhere((x) => x['id'] == a['donation_id']);
              return {
                ...a,
                'donation_status': d['status'],
                'donation_clinic_id': d['clinic_id'],
                'payment_status': d['payment_status'],
                'payment_environment': d['payment_environment'],
              };
            }(),
        ];
      default:
        return tables[table] ?? const <Map<String, dynamic>>[];
    }
  }

  Future<http.Response> handle(http.Request request) async {
    methods.add(request.method);

    final table = request.url.pathSegments.last;
    paths.add(table);
    final params = request.url.queryParameters;

    var rows = _source(table).where((row) {
      return params.entries.every((param) {
        if (const {'select', 'order', 'limit'}.contains(param.key)) return true;
        if (param.key == 'or') return _matchesOr(row, param.value);
        return _matches(row, '${param.key}.${param.value}');
      });
    }).toList();

    final order = params['order'];
    if (order != null) {
      final column = order.split('.').first;
      rows.sort((a, b) => b[column].toString().compareTo(a[column].toString()));
    }

    final limit = int.tryParse(params['limit'] ?? '');
    if (limit != null) rows = rows.take(limit).toList();

    final body = rows.map((row) => _project(row, params['select']!)).toList();
    final wantsObject = (request.headers['accept'] ?? '').contains(
      'vnd.pgrst.object',
    );

    return http.Response(
      jsonEncode(wantsObject ? (body.isEmpty ? null : body.first) : body),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  bool _matches(Map<String, dynamic> row, String filter) {
    final parts = filter.split('.');
    expect(parts[1], 'eq', reason: 'unsupported filter: $filter');
    return row[parts[0]]?.toString() == parts.sublist(2).join('.');
  }

  /// Evaluates or=(a.eq.1,and(b.eq.2,c.eq.3)).
  bool _matchesOr(Map<String, dynamic> row, String value) {
    final inner = value.substring(1, value.length - 1);
    return _splitTopLevel(inner).any((term) {
      if (term.startsWith('and(')) {
        final group = term.substring(4, term.length - 1);
        return _splitTopLevel(group).every((part) => _matches(row, part));
      }
      return _matches(row, term);
    });
  }

  List<String> _splitTopLevel(String value) {
    final terms = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < value.length; i++) {
      if (value[i] == '(') depth++;
      if (value[i] == ')') depth--;
      if (value[i] == ',' && depth == 0) {
        terms.add(value.substring(start, i));
        start = i + 1;
      }
    }
    terms.add(value.substring(start));
    return terms;
  }

  Map<String, dynamic> _project(Map<String, dynamic> row, String select) {
    if (select == '*') return row;

    final embed = RegExp(r'donations\(([^)]*)\)').firstMatch(select);
    final columns = select
        .replaceAll(RegExp(r'donations\([^)]*\)'), '')
        .split(',')
        .where((column) => column.isNotEmpty);

    final result = {for (final column in columns) column: row[column]};

    if (embed != null) {
      final parent = tables['donations']!.firstWhere(
        (donation) => donation['id'] == row['donation_id'],
      );
      result['donations'] = {
        for (final column in embed.group(1)!.split(',')) column: parent[column],
      };
    }

    return result;
  }
}

class _MemoryStorage extends GotrueAsyncStorage {
  final _items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }
}

void main() {
  final backend = _Backend();
  late DashboardService service;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(backend.handle),
      debug: false,
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );

    service = DashboardService();
  });

  setUp(backend.reset);

  group('getAllocatedDonationTotal, verified-only rule', () {
    // A confirmed live checkout: verified, with allocation rows (as
    // donation_finalize writes it for a production payment).
    void addVerifiedCheckout(Map<String, num> shares, {bool split = false, String createdAt = '2026-11-01T00:00:00Z'}) =>
        backend.addDonation(
          status: 'verified',
          paymentStatus: 'paid',
          paymentEnvironment: 'production',
          shares: shares,
          split: split,
          createdAt: createdAt,
        );

    test('a completed simulated payment is never received funds', () async {
      backend.addSimulatedPaid({clinicA: 500});
      backend.addSimulatedPaid({clinicA: 33.34, clinicB: 33.33, clinicC: 33.33}, split: true);

      expect(await service.getAllocatedDonationTotal(clinicA), 0);
      expect(await service.getAllocatedDonationTotal(clinicB), 0);
      expect(await service.getAllocatedDonationTotal(clinicC), 0);
    });

    test('a sandbox row is excluded even if it were marked verified', () async {
      backend.addDonation(
        status: 'verified',
        paymentStatus: 'simulated_paid',
        paymentEnvironment: 'sandbox',
        shares: {clinicA: 50, clinicB: 50},
        split: true,
      );

      expect(await service.getAllocatedDonationTotal(clinicA), 0);
    });

    test('a Specific/Random donation counts exactly once', () async {
      // One parent with clinic_id AND one allocation row for the same money.
      addVerifiedCheckout({clinicA: 500});

      expect(await service.getAllocatedDonationTotal(clinicA), 500);
    });

    test('Donate to All counts each center\'s own share once', () async {
      addVerifiedCheckout({
        clinicA: 33.34,
        clinicB: 33.33,
        clinicC: 33.33,
      }, split: true);

      expect(await service.getAllocatedDonationTotal(clinicA), 33.34);
      expect(await service.getAllocatedDonationTotal(clinicB), 33.33);
      expect(await service.getAllocatedDonationTotal(clinicC), 33.33);
    });

    test('the centavo remainder is not lost across centers', () async {
      addVerifiedCheckout({
        clinicA: 33.34,
        clinicB: 33.33,
        clinicC: 33.33,
      }, split: true);

      var total = 0.0;
      for (final clinic in [clinicA, clinicB, clinicC]) {
        total += await service.getAllocatedDonationTotal(clinic);
      }

      expect(total, closeTo(100, 0.000001));
    });

    test('another center\'s donation is not counted', () async {
      addVerifiedCheckout({clinicB: 250});

      expect(await service.getAllocatedDonationTotal(clinicA), 0);
    });

    for (final paymentStatus in ['failed', 'cancelled']) {
      test('a $paymentStatus donation is excluded', () async {
        backend
          ..addDonation(
            status: 'rejected',
            paymentStatus: paymentStatus,
            paymentEnvironment: 'sandbox',
            shares: {clinicA: 500},
          )
          ..addDonation(
            status: 'rejected',
            paymentStatus: paymentStatus,
            paymentEnvironment: 'sandbox',
            shares: {clinicA: 50, clinicB: 50},
            split: true,
          );

        expect(await service.getAllocatedDonationTotal(clinicA), 0);
      });
    }

    test('an unpaid checkout is excluded', () async {
      backend
        ..addDonation(
          status: 'pending',
          paymentStatus: 'pending',
          paymentEnvironment: 'sandbox',
          shares: {clinicA: 500},
        )
        ..addDonation(
          status: 'pending',
          paymentStatus: 'processing',
          paymentEnvironment: 'sandbox',
          shares: {clinicA: 50, clinicB: 50},
          split: true,
        );

      expect(await service.getAllocatedDonationTotal(clinicA), 0);
    });

    test('a PayMongo test payment is not treated as simulated_paid', () async {
      backend.addDonation(
        status: 'pending',
        paymentStatus: 'paid',
        paymentEnvironment: 'sandbox',
        shares: {clinicA: 500},
      );

      expect(await service.getAllocatedDonationTotal(clinicA), 0);
    });
  });

  group('getAllocatedDonationTotal, existing records', () {
    test('a legacy verified direct donation still counts', () async {
      backend.tables['donations']!.add({
        'id': 'legacy-direct',
        'amount': 300,
        'status': 'verified',
        'clinic_id': clinicA,
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(await service.getAllocatedDonationTotal(clinicA), 300);
    });

    test('a legacy verified equal share still counts', () async {
      backend.addDonation(
        status: 'verified',
        shares: {clinicA: 60, clinicB: 40},
        split: true,
      );

      expect(await service.getAllocatedDonationTotal(clinicA), 60);
    });

    test('a verified donation with an allocation row counts once', () async {
      backend.addDonation(
        status: 'verified',
        paymentStatus: 'paid',
        paymentEnvironment: 'production',
        shares: {clinicA: 700},
      );

      expect(await service.getAllocatedDonationTotal(clinicA), 700);
    });

    test('legacy pending and rejected donations stay excluded', () async {
      backend
        ..addDonation(status: 'pending', shares: {clinicA: 10})
        ..addDonation(status: 'rejected', shares: {clinicA: 20})
        ..addDonation(
          status: 'pending',
          shares: {clinicA: 30, clinicB: 30},
          split: true,
        );

      expect(await service.getAllocatedDonationTotal(clinicA), 0);
    });

    test('manual distributions are unaffected and additive', () async {
      backend.tables['fund_distributions']!.add({
        'center_name': 'Center A',
        'amount': 1000,
        'created_at': '2026-01-01T00:00:00Z',
      });
      backend.addDonation(status: 'verified', shares: {clinicA: 500});
      backend.addSimulatedPaid({clinicA: 300}); // never added

      final manual = await service.getTotalDonations('Center A');
      final allocated = await service.getAllocatedDonationTotal(clinicA);

      expect(manual, 1000);
      expect(allocated, 500);
      expect(manual + allocated, 1500);
    });
  });

  group('getLatestDonation', () {
    test('returns a newer verified donation', () async {
      backend
        ..addDonation(
          status: 'verified',
          shares: {clinicA: 100},
          createdAt: '2026-10-01T00:00:00Z',
        )
        ..addDonation(
          status: 'verified',
          paymentStatus: 'paid',
          paymentEnvironment: 'production',
          shares: {clinicA: 500},
          createdAt: '2026-11-01T00:00:00Z',
        );

      final latest = await service.getLatestDonation(
        centerName: 'Center A',
        clinicId: clinicA,
      );

      expect(latest?['amount'], 500);
    });

    test('a newer simulated payment is never the latest received donation', () async {
      backend
        ..addDonation(
          status: 'verified',
          shares: {clinicA: 100},
          createdAt: '2026-10-01T00:00:00Z',
        )
        ..addSimulatedPaid({clinicA: 500}, createdAt: '2026-11-01T00:00:00Z')
        ..addSimulatedPaid(
          {clinicA: 33.34, clinicB: 33.33, clinicC: 33.33},
          split: true,
          createdAt: '2026-11-02T00:00:00Z',
        );

      final latest = await service.getLatestDonation(
        centerName: 'Center A',
        clinicId: clinicA,
      );

      expect(latest?['amount'], 100);
    });

    test('returns a newer verified Donate to All share', () async {
      backend
        ..addDonation(
          status: 'verified',
          shares: {clinicA: 100},
          createdAt: '2026-10-01T00:00:00Z',
        )
        ..addDonation(
          status: 'verified',
          shares: {clinicA: 33.34, clinicB: 33.33, clinicC: 33.33},
          split: true,
          createdAt: '2026-11-01T00:00:00Z',
        );

      final latest = await service.getLatestDonation(
        centerName: 'Center A',
        clinicId: clinicA,
      );

      expect(latest?['amount'], 33.34);
      expect(latest?['source'], 'donation_allocation');
    });

    test('skips newer failed and cancelled donations', () async {
      backend
        ..addDonation(status: 'verified', shares: {clinicA: 500}, createdAt: '2026-10-01T00:00:00Z')
        ..addDonation(
          status: 'rejected',
          paymentStatus: 'failed',
          paymentEnvironment: 'sandbox',
          shares: {clinicA: 900},
          createdAt: '2026-11-01T00:00:00Z',
        )
        ..addDonation(
          status: 'rejected',
          paymentStatus: 'cancelled',
          paymentEnvironment: 'sandbox',
          shares: {clinicA: 45, clinicB: 45},
          split: true,
          createdAt: '2026-11-02T00:00:00Z',
        );

      final latest = await service.getLatestDonation(
        centerName: 'Center A',
        clinicId: clinicA,
      );

      expect(latest?['amount'], 500);
    });
  });

  test('sandbox donations are only read, never rewritten', () async {
    backend.addSimulatedPaid({clinicA: 500});
    backend.addSimulatedPaid({clinicA: 50, clinicB: 50}, split: true);
    final before = jsonEncode(backend.tables);

    await service.getAllocatedDonationTotal(clinicA);
    await service.getLatestDonation(centerName: 'Center A', clinicId: clinicA);

    expect(backend.methods, {'GET'});
    expect(jsonEncode(backend.tables), before);
    for (final donation in backend.tables['donations']!) {
      expect(donation['payment_status'], 'simulated_paid');
      expect(donation['payment_environment'], 'sandbox');
      expect(donation['status'], isNot('verified'));
    }
  });

  test('center admins read donations only through the privacy-safe views', () async {
    backend.addSimulatedPaid({clinicA: 500});
    backend.addSimulatedPaid({clinicA: 50, clinicB: 50}, split: true);

    await service.getAllocatedDonationTotal(clinicA);
    await service.getLatestDonation(centerName: 'Center A', clinicId: clinicA);

    expect(backend.paths, containsAll(['center_admin_donations', 'center_admin_allocations']));
    expect(backend.paths, isNot(contains('donations')));
    expect(backend.paths, isNot(contains('donation_allocations')));
  });
}
