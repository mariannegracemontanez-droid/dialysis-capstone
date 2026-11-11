import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:donation_app/config/payment_config.dart';
import 'package:donation_app/pages/checkout_page.dart';
import 'package:donation_app/services/donation_checkout_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-in for the database functions. It mimics only what the
/// checkout page relies on: statuses come back from "the server".
class FakeCheckoutService implements DonationCheckoutService {
  FakeCheckoutService(this.current);

  DonationCheckout current;
  final List<String> calls = [];

  DonationCheckout _withStatus(String status, {String? reason}) {
    final allocationStatus = switch (status) {
      'simulated_paid' => 'simulated',
      'failed' || 'cancelled' => 'void',
      _ => 'awaiting_payment',
    };
    current = DonationCheckout(
      donationId: current.donationId,
      reference: current.reference,
      mode: current.mode,
      amountCentavos: current.amountCentavos,
      paymentProvider: current.paymentProvider,
      paymentEnvironment: current.paymentEnvironment,
      paymentStatus: status,
      statusReason: reason,
      allocations: [
        for (final a in current.allocations)
          CheckoutAllocation(
            clinicId: a.clinicId,
            clinicName: a.clinicName,
            amountCentavos: a.amountCentavos,
            status: allocationStatus,
          ),
      ],
    );
    return current;
  }

  @override
  Future<DonationCheckout> fetchCheckout(String donationId, String secret) async {
    calls.add('fetch');
    return current;
  }

  @override
  Future<DonationCheckout> simulate(String id, String secret, String outcome) async {
    calls.add('simulate:$outcome');
    return _withStatus(switch (outcome) {
      'success' => 'simulated_paid',
      'failure' => 'failed',
      _ => 'cancelled',
    });
  }

  @override
  Future<DonationCheckout> cancel(String id, String secret) async {
    calls.add('cancel');
    return _withStatus('cancelled', reason: 'Cancelled by donor');
  }

  /// What `paymongo-create-checkout` "returns" in a test (or throws).
  Future<DonationCheckout> Function()? onStartPaymongo;

  @override
  Future<DonationCheckout> startPaymongoCheckout(String id, String secret) async {
    calls.add('paymongo');
    final handler = onStartPaymongo;
    if (handler == null) throw StateError('no PayMongo handler set');
    return current = await handler();
  }

  @override
  Future<void> clearPending() async => calls.add('clear');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DonationCheckout _checkout({
  String provider = 'internal_simulator',
  String status = 'pending',
  DonationMode mode = DonationMode.allCenters,
  String? checkoutUrl,
  String donationId = 'd-1',
}) {
  return DonationCheckout.fromJson({
    'donation_id': donationId,
    'reference': 'CN-SBX-ABCDEF1234',
    'mode': mode.value,
    'amount_centavos': 100000,
    'payment_provider': provider,
    'payment_environment': 'sandbox',
    'payment_status': status,
    'checkout_url': checkoutUrl,
    'allocations': [
      {'clinic_id': 'a', 'clinic_name': 'Alpha Dialysis', 'amount_centavos': 33334, 'allocation_status': 'awaiting_payment'},
      {'clinic_id': 'b', 'clinic_name': 'Beta Dialysis', 'amount_centavos': 33333, 'allocation_status': 'awaiting_payment'},
      {'clinic_id': 'c', 'clinic_name': 'Gamma Dialysis', 'amount_centavos': 33333, 'allocation_status': 'awaiting_payment'},
    ],
  });
}

Future<void> _pumpCheckout(
  WidgetTester tester,
  FakeCheckoutService service, {
  CheckoutUrlLauncher? launcher,
  bool testOutcomes = false,
  ReceiptDownloader? downloader,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1000, 2400);
  addTearDown(tester.view.reset);

  final download = downloader ?? (String _, Uint8List _, String _) {};
  await tester.pumpWidget(MaterialApp(
    home: launcher == null
        ? CheckoutPage(
            checkout: service.current,
            clientSecret: 'secret',
            service: service,
            showTestOutcomes: testOutcomes,
            downloadFile: download,
          )
        : CheckoutPage(
            checkout: service.current,
            clientSecret: 'secret',
            service: service,
            launchCheckout: launcher,
            showTestOutcomes: testOutcomes,
            downloadFile: download,
          ),
  ));
  await tester.pump();
}

/// Ticks the final-review confirmation (once; it is a checkbox).
Future<void> _confirmReview(WidgetTester tester) async {
  final box = find.byKey(const ValueKey('review-confirm'));
  if (tester.widget<Checkbox>(box).value == true) return;
  await tester.ensureVisible(box);
  await tester.tap(box);
  await tester.pump();
}

void main() {
  group('parseAmountToCentavos', () {
    test('parses whole and centavo amounts exactly', () {
      expect(parseAmountToCentavos('1000'), 100000);
      expect(parseAmountToCentavos(' 1250.50 '), 125050);
      expect(parseAmountToCentavos('99.9'), 9990);
      expect(parseAmountToCentavos('0.29'), 29); // 0.29 * 100 != 29 in floating point
      expect(parseAmountToCentavos('.75'), 75);
      expect(parseAmountToCentavos('0'), 0); // rejected later as below minimum
    });

    test('rejects negative, invalid and oversized input', () {
      for (final input in [
        '', ' ', '-5', '10.555', '1,000', 'abc', '.', 'NaN', 'Infinity', '1e3',
        '0x10', '1234567890123', // 13-digit pesos: excessively large
      ]) {
        expect(parseAmountToCentavos(input), isNull, reason: input);
      }
    });
  });

  group('splitCentavosEqually', () {
    int sum(List<int> xs) => xs.fold(0, (a, b) => a + b);

    test('one eligible center receives everything', () {
      expect(splitCentavosEqually(100000, 1), [100000]);
    });

    test('PHP 1,000 to four centers is PHP 250.00 each', () {
      expect(splitCentavosEqually(100000, 4), [25000, 25000, 25000, 25000]);
    });

    test('PHP 1,000 to three centers: leftover centavo goes to the first', () {
      final shares = splitCentavosEqually(100000, 3);
      expect(shares, [33334, 33333, 33333]);
      expect(sum(shares), 100000);
    });

    test('remainders are distributed deterministically and always sum exactly', () {
      for (final total in [2000, 2001, 9999, 100001, 123457, 10000000]) {
        for (final count in [1, 2, 3, 6, 7, 11, 13]) {
          final shares = splitCentavosEqually(total, count);
          expect(sum(shares), total, reason: '$total/$count');
          expect(shares.reduce((a, b) => a > b ? a : b) -
              shares.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(1));
          // Larger shares first, so the order is stable.
          for (int i = 1; i < shares.length; i++) {
            expect(shares[i], lessThanOrEqualTo(shares[i - 1]));
          }
          expect(splitCentavosEqually(total, count), shares); // deterministic
        }
      }
    });

    test('no recipients, zero/negative amounts, or less than 1 centavo each', () {
      expect(splitCentavosEqually(100000, 0), isEmpty);
      expect(splitCentavosEqually(0, 3), isEmpty);
      expect(splitCentavosEqually(-500, 3), isEmpty);
      expect(splitCentavosEqually(2, 3), isEmpty);
    });
  });

  test('sortCentersForAllocation matches the server order (name, then id)', () {
    final sorted = sortCentersForAllocation([
      {'id': '2', 'name': 'Beta'},
      {'id': '9', 'name': 'Alpha'},
      {'id': '1', 'name': 'Alpha'},
    ]);
    expect(sorted.map((c) => c['id']), ['1', '9', '2']);
  });

  test('formatCentavos', () {
    expect(formatCentavos(100000), '₱1,000.00');
    expect(formatCentavos(33334), '₱333.34');
    expect(formatCentavos(5), '₱0.05');
    expect(formatCentavos(123456789), '₱1,234,567.89');
  });

  group('mapCheckoutError', () {
    test('maps server codes to donor-safe messages', () {
      final e = mapCheckoutError(const PostgrestException(
        message: 'CENTER_NOT_ELIGIBLE: the selected centre is not currently accepting donations.',
      ));
      expect(e.code, 'CENTER_NOT_ELIGIBLE');
      expect(e.message, contains('no longer accepting'));

      expect(mapCheckoutError(const PostgrestException(
        message: 'NO_ELIGIBLE_CENTERS: none',
      )).code, 'NO_ELIGIBLE_CENTERS');
    });

    test('never leaks raw database errors', () {
      final e = mapCheckoutError(Exception('relation "x" does not exist'));
      expect(e.code, 'UNKNOWN');
      expect(e.message, isNot(contains('relation')));
    });
  });

  group('CheckoutRequest', () {
    test('each attempt gets fresh, long random keys', () {
      final a = CheckoutRequest(mode: DonationMode.randomCenter, amountCentavos: 5000, anonymous: true);
      final b = CheckoutRequest(mode: DonationMode.randomCenter, amountCentavos: 5000, anonymous: true);
      expect(a.idempotencyKey, isNot(b.idempotencyKey));
      expect(a.clientSecret.length, greaterThanOrEqualTo(32));
      expect(a.idempotencyKey.length, inInclusiveRange(16, 100));
    });

    test('sameAs only matches an identical donation (retry reuses keys)', () {
      final a = CheckoutRequest(
        mode: DonationMode.specificCenter, amountCentavos: 5000, anonymous: false, clinicId: 'c1');
      expect(a.sameAs(mode: DonationMode.specificCenter, amountCentavos: 5000,
          clinicId: 'c1', anonymous: false, donorName: null), isTrue);
      expect(a.sameAs(mode: DonationMode.specificCenter, amountCentavos: 5001,
          clinicId: 'c1', anonymous: false, donorName: null), isFalse);
      expect(a.sameAs(mode: DonationMode.specificCenter, amountCentavos: 5000,
          clinicId: 'c2', anonymous: false, donorName: null), isFalse);
    });
  });

  group('pending checkout (never re-randomise / re-split)', () {
    test('the original request survives a refresh with the same keys', () {
      for (final original in [
        CheckoutRequest(mode: DonationMode.randomCenter, amountCentavos: 50000, anonymous: true),
        CheckoutRequest(mode: DonationMode.allCenters, amountCentavos: 100000, anonymous: false, donorName: 'Synthetic Donor'),
        CheckoutRequest(mode: DonationMode.specificCenter, amountCentavos: 25000, anonymous: true, clinicId: 'c-1'),
      ]) {
        final raw = encodePendingCheckout('d-1', original.clientSecret, request: original);
        final restored = decodePendingCheckout(raw)!;
        expect(restored.id, 'd-1');
        expect(restored.secret, original.clientSecret);
        final r = restored.request!;
        // Same keys => the server returns the SAME donation (same random
        // centre / same split) instead of creating a new one.
        expect(r.idempotencyKey, original.idempotencyKey);
        expect(r.clientSecret, original.clientSecret);
        expect(r.sameAs(mode: original.mode, amountCentavos: original.amountCentavos,
            clinicId: original.clinicId, anonymous: original.anonymous,
            donorName: original.donorName), isTrue);
        // The client secret is stored once, not duplicated inside the request.
        expect(RegExp(RegExp.escape(original.clientSecret)).allMatches(raw).length, 1);
        // The donor's name is never written to browser storage.
        expect(raw, isNot(contains('donor_name')));
        expect(raw, isNot(contains('Synthetic Donor')));
        expect(r.donorName, isNull);
        expect(r.donorNameUnknown, isTrue);
      }
    });

    test('anonymous donor: refresh + same details reuses the same request', () {
      final original = CheckoutRequest(
          mode: DonationMode.randomCenter, amountCentavos: 50000, anonymous: true);
      final r = decodePendingCheckout(
          encodePendingCheckout('d-1', original.clientSecret, request: original))!.request!;
      expect(r.idempotencyKey, original.idempotencyKey);
      // The page passes donorName: null for anonymous donations.
      expect(r.sameAs(mode: DonationMode.randomCenter, amountCentavos: 50000,
          clinicId: null, anonymous: true, donorName: null), isTrue);
      // Different details are a different donation.
      expect(r.sameAs(mode: DonationMode.randomCenter, amountCentavos: 50001,
          clinicId: null, anonymous: true, donorName: null), isFalse);
      expect(r.sameAs(mode: DonationMode.allCenters, amountCentavos: 50000,
          clinicId: null, anonymous: true, donorName: null), isFalse);
      expect(r.sameAs(mode: DonationMode.randomCenter, amountCentavos: 50000,
          clinicId: null, anonymous: false, donorName: null), isFalse);
    });

    test('registered donor: name is not stored, yet the same request is reused', () {
      final original = CheckoutRequest(
          mode: DonationMode.specificCenter, amountCentavos: 25000, anonymous: false,
          clinicId: 'c-1', donorName: 'Synthetic Registered Donor');
      final raw = encodePendingCheckout('d-2', original.clientSecret, request: original);
      expect(raw, isNot(contains('Synthetic Registered Donor')));
      expect(raw, isNot(contains('donor_name')));

      final r = decodePendingCheckout(raw)!.request!;
      expect(r.idempotencyKey, original.idempotencyKey);
      expect(r.donorName, isNull);
      // After a refresh the donor re-enters (or the form refills) the name;
      // the request is still recognised, so its keys are replayed and the
      // server returns the existing donation with its ORIGINAL name.
      for (final typed in ['Synthetic Registered Donor', 'Another Synthetic Name', null]) {
        expect(r.sameAs(mode: DonationMode.specificCenter, amountCentavos: 25000,
            clinicId: 'c-1', anonymous: false, donorName: typed), isTrue, reason: '$typed');
      }
      // Only the name is ignored: a different centre is a different donation.
      expect(r.sameAs(mode: DonationMode.specificCenter, amountCentavos: 25000,
          clinicId: 'c-2', anonymous: false, donorName: 'Synthetic Registered Donor'), isFalse);
    });

    test('a request made in this session still compares the donor name', () {
      final live = CheckoutRequest(
          mode: DonationMode.randomCenter, amountCentavos: 5000, anonymous: false,
          donorName: 'Synthetic Name A');
      expect(live.donorNameUnknown, isFalse);
      expect(live.sameAs(mode: DonationMode.randomCenter, amountCentavos: 5000,
          clinicId: null, anonymous: false, donorName: 'Synthetic Name A'), isTrue);
      expect(live.sameAs(mode: DonationMode.randomCenter, amountCentavos: 5000,
          clinicId: null, anonymous: false, donorName: 'Synthetic Name B'), isFalse);
    });

    test('older entries that still contain donor_name are read safely and flagged for rewrite', () {
      final legacy = jsonEncode({
        'id': 'd-3',
        'secret': 's' * 43,
        'request': {
          'mode': 'random_center', 'amount_centavos': 50000, 'clinic_id': null,
          'anonymous': false, 'donor_name': 'Synthetic Legacy Name', 'idempotency_key': 'k' * 32,
        },
      });
      expect(pendingCheckoutStoresDonorName(legacy), isTrue);
      final p = decodePendingCheckout(legacy)!;
      expect(p.request!.idempotencyKey, 'k' * 32);
      expect(p.request!.donorName, isNull); // never read back
      // What loadPending writes back in its place:
      final rewritten = encodePendingCheckout(p.id, p.secret, request: p.request);
      expect(rewritten, isNot(contains('Synthetic Legacy Name')));
      expect(pendingCheckoutStoresDonorName(rewritten), isFalse);
      expect(decodePendingCheckout(rewritten)!.request!.idempotencyKey, 'k' * 32);

      // A legacy donor_name of any type is ignored rather than trusted.
      final odd = jsonEncode({'id': 'd-4', 'secret': 's', 'request': {
        'mode': 'random_center', 'amount_centavos': 50000, 'clinic_id': null,
        'anonymous': true, 'donor_name': 7, 'idempotency_key': 'k' * 32}});
      expect(decodePendingCheckout(odd)!.request, isNotNull);
      expect(pendingCheckoutStoresDonorName('{"id":"d","secret":"s"}'), isFalse);
      expect(pendingCheckoutStoresDonorName('not json'), isFalse);
    });

    test('loadPending/savePending never leave a donor name in browser storage', () async {
      const key = 'curenurture.pending_checkout';
      final legacy = jsonEncode({
        'id': 'd-5',
        'secret': 's' * 43,
        'request': {
          'mode': 'equal_distribution', 'amount_centavos': 100001, 'clinic_id': null,
          'anonymous': false, 'donor_name': 'Synthetic Legacy Name', 'idempotency_key': 'k' * 32,
        },
      });
      SharedPreferences.setMockInitialValues({key: legacy});
      // Local placeholder client: these calls only use browser storage.
      final service = DonationCheckoutService(SupabaseClient('http://127.0.0.1:1', 'test-key'));

      final p = (await service.loadPending())!;
      expect(p.id, 'd-5');
      expect(p.request!.idempotencyKey, 'k' * 32);
      final stored = (await SharedPreferences.getInstance()).getString(key)!;
      expect(stored, isNot(contains('Synthetic Legacy Name')));
      expect(stored, isNot(contains('donor_name')));
      expect(decodePendingCheckout(stored)!.request!.idempotencyKey, 'k' * 32);

      // A new registered-donor request saved now is stored without the name too.
      final fresh = CheckoutRequest(mode: DonationMode.randomCenter, amountCentavos: 5000,
          anonymous: false, donorName: 'Synthetic Registered Donor');
      await service.savePending('d-6', fresh.clientSecret, request: fresh);
      final saved = (await SharedPreferences.getInstance()).getString(key)!;
      expect(saved, isNot(contains('Synthetic Registered Donor')));
      expect(saved, isNot(contains('donor_name')));
      expect((await service.loadPending())!.request!.idempotencyKey, fresh.idempotencyKey);
    });

    test('older {id, secret} entries still resume, without a request', () {
      final p = decodePendingCheckout('{"id":"d-1","secret":"s"}')!;
      expect((p.id, p.secret, p.request), ('d-1', 's', null));
    });

    test('malformed entries are ignored', () {
      for (final raw in ['', 'not json', '[]', '{}', '{"id":"d-1"}', '{"id":"","secret":"s"}',
          '{"id":"d-1","secret":""}', '{"id":5,"secret":"s"}']) {
        expect(decodePendingCheckout(raw), isNull, reason: raw);
      }
    });

    test('a tampered or inconsistent request part is dropped, not trusted', () {
      Map<String, Object?> req(Map<String, Object?> o) => {
            'mode': 'random_center', 'amount_centavos': 50000, 'clinic_id': null,
            'anonymous': true, 'idempotency_key': 'k' * 32, ...o};
      for (final bad in [
        req({'mode': 'whatever'}),
        req({'amount_centavos': '50000'}),
        req({'amount_centavos': 0}),
        req({'idempotency_key': 'short'}),
        req({'anonymous': 'yes'}),
        req({'clinic_id': 'c-1'}), // random mode never carries a centre
        req({'mode': 'specific_center'}), // specific mode needs one
      ]) {
        final p = decodePendingCheckout(jsonEncode({'id': 'd-1', 'secret': 's', 'request': bad}))!;
        expect(p.id, 'd-1');
        expect(p.request, isNull, reason: '$bad');
      }
    });

    test('a request with a different secret is never stored', () {
      final r = CheckoutRequest(mode: DonationMode.randomCenter, amountCentavos: 50000, anonymous: true);
      final p = decodePendingCheckout(encodePendingCheckout('d-1', 'other-secret', request: r))!;
      expect(p.request, isNull);
    });
  });

  test('Bank Transfer is hidden for the demo', () {
    expect(kBankTransferEnabled, isFalse);
  });

  group('CheckoutPage', () {
    testWidgets('shows demo banner, recipients and the server-side split', (tester) async {
      final service = FakeCheckoutService(_checkout());
      await _pumpCheckout(tester, service);

      expect(find.text(kDemoBannerText), findsOneWidget);
      expect(find.text('CN-SBX-ABCDEF1234'), findsOneWidget);
      expect(find.text('Alpha Dialysis'), findsOneWidget);
      expect(find.text('₱333.34'), findsOneWidget);
      expect(find.text('₱333.33'), findsNWidgets(2));
      expect(find.text('Total allocated: ₱1,000.00'), findsOneWidget);
      expect(find.text('Payment type'), findsOneWidget);
      expect(find.text('Simulated payment'), findsOneWidget);
      // The old technical / repeated sandbox notes are gone.
      expect(find.textContaining('Sandbox'), findsNothing);
      expect(find.textContaining('intended distribution'), findsNothing);
      expect(find.textContaining('chosen by the server'), findsNothing);
      expect(service.calls, contains('fetch')); // state is re-read from the server
    });

    testWidgets('simulated success is labelled as simulated, never as real funds', (tester) async {
      final service = FakeCheckoutService(_checkout());
      await _pumpCheckout(tester, service);

      await _confirmReview(tester);
      await tester.tap(find.byKey(const ValueKey('complete-donation')));
      await tester.pumpAndSettle();

      expect(service.calls, contains('simulate:success'));
      expect(find.text('Donation complete'), findsOneWidget);
      expect(find.textContaining('no real money was charged'), findsOneWidget);
      expect(find.text('Simulated payment'), findsOneWidget);
      // Never worded as money received or paid out.
      expect(find.textContaining('received funds'), findsNothing);
      expect(find.textContaining('Paid out'), findsNothing);
      expect(find.byKey(const ValueKey('complete-donation')), findsNothing);
      expect(service.calls, contains('clear'));
    });

    testWidgets('completed simulated donation offers an honest downloadable acknowledgement', (tester) async {
      final service = FakeCheckoutService(_checkout());
      final saved = <(String, String, String)>[];
      await _pumpCheckout(tester, service,
          downloader: (name, bytes, mime) => saved.add((name, utf8.decode(bytes), mime)));

      expect(find.byKey(const ValueKey('download-receipt')), findsNothing); // not before payment

      await _confirmReview(tester);
      await tester.tap(find.byKey(const ValueKey('complete-donation')));
      await tester.pumpAndSettle();

      expect(find.text('Download acknowledgement'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('download-receipt')));
      await tester.tap(find.byKey(const ValueKey('download-receipt')));
      await tester.pump();

      expect(saved, hasLength(1));
      final (name, html, mime) = saved.single;
      expect(name, 'CureNurture-acknowledgement-CN-SBX-ABCDEF1234.html');
      expect(mime, startsWith('text/html'));
      expect(html, contains('Donation Acknowledgement'));
      expect(html, contains('CN-SBX-ABCDEF1234'));
      expect(html, contains('₱1,000.00'));
      expect(html, contains('Alpha Dialysis'));
      expect(html, contains('₱333.34'));
      expect(html, contains('This is not a payment receipt'));
      expect(html, contains('no money was charged'));
      expect(html, isNot(contains('Donation Receipt')));
      expect(html, isNot(contains('Payment confirmed')));
    });

    testWidgets('failed and cancelled donations offer no receipt', (tester) async {
      for (final outcome in ['simulate-failure', 'simulate-cancel']) {
        await tester.pumpWidget(const SizedBox()); // fresh page state for each outcome
        final service = FakeCheckoutService(_checkout());
        await _pumpCheckout(tester, service, testOutcomes: true);
        await tester.tap(find.byKey(ValueKey(outcome)));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('download-receipt')), findsNothing, reason: outcome);
      }
    });

    testWidgets('simulated failure (developer test outcome)', (tester) async {
      final service = FakeCheckoutService(_checkout(mode: DonationMode.randomCenter));
      await _pumpCheckout(tester, service, testOutcomes: true);

      await tester.tap(find.byKey(const ValueKey('simulate-failure')));
      await tester.pumpAndSettle();

      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.text('Not allocated'), findsNWidgets(3));
    });

    testWidgets('simulated cancellation (developer test outcome)', (tester) async {
      final service = FakeCheckoutService(_checkout());
      await _pumpCheckout(tester, service, testOutcomes: true);

      await tester.tap(find.byKey(const ValueKey('simulate-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Donation cancelled'), findsOneWidget);
    });

    testWidgets('PayMongo checkout shows no simulator buttons', (tester) async {
      final service = FakeCheckoutService(_checkout(provider: 'paymongo'));
      await _pumpCheckout(tester, service);

      expect(find.byKey(const ValueKey('complete-donation')), findsNothing);
      expect(find.text('Continue to GCash (PayMongo test)'), findsOneWidget);
      expect(find.text('PayMongo test mode'), findsOneWidget);
    });

    testWidgets('lays out on a 320px phone without overflow', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 2400);
      addTearDown(tester.view.reset);
      final service = FakeCheckoutService(_checkout());
      await tester.pumpWidget(MaterialApp(
        home: CheckoutPage(checkout: service.current, clientSecret: 's', service: service),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('trustedPaymongoCheckoutUri', () {
    test('accepts genuine PayMongo checkout URLs', () {
      for (final good in [
        'https://checkout.paymongo.com/cs_abc123',
        'https://checkout.paymongo.com/cs_abc123#Y2lkPWNz',
        'https://checkout.paymongo.com:443/cs_abc123',
        'https://CHECKOUT.paymongo.com/cs_abc123',
      ]) {
        expect(trustedPaymongoCheckoutUri(good), isNotNull, reason: good);
      }
    });

    test('rejects untrusted, malformed or empty URLs', () {
      for (final bad in <String?>[
        null, '', 'not a url', '/cs_1', '//checkout.paymongo.com/cs_1',
        'http://checkout.paymongo.com/cs_1',
        'javascript:alert(1)',
        'https://evil.example/cs_1',
        'https://paymongo.com/cs_1',
        'https://evil.checkout.paymongo.com/cs_1',
        'https://checkout.paymongo.com.evil.example/cs_1',
        'https://user:pass@checkout.paymongo.com/cs_1',
        'https://checkout.paymongo.com@evil.example/cs_1',
        'https://checkout.paymongo.com:8443/cs_1',
        r'https://checkout.paymongo.com\@evil.example/',
        ' https://checkout.paymongo.com/cs_1',
        'https://checkout.paymongo.com/cs_1\n',
      ]) {
        expect(trustedPaymongoCheckoutUri(bad), isNull, reason: '$bad');
      }
    });
  });

  group('parsePaymongoCheckoutResponse', () {
    Map<String, dynamic> body({String id = 'd-1', String? url}) => {
          'donation_id': id,
          'reference': 'CN-SBX-ABCDEF1234',
          'payment_provider': 'paymongo',
          'payment_environment': 'sandbox',
          'payment_status': 'processing',
          'checkout_url': url,
          'allocations': [],
        };

    test('accepts a well-formed response for the same donation', () {
      final c = parsePaymongoCheckoutResponse(
          body(url: 'https://checkout.paymongo.com/cs_1'), 'd-1');
      expect(c.checkoutUrl, 'https://checkout.paymongo.com/cs_1');
    });

    test('fails closed on malformed, mismatched or untrusted responses', () {
      for (final data in <Object?>[
        null,
        'oops',
        [1, 2],
        {'error': 'Could not create PayMongo checkout'},
        body(id: 'other-donation', url: 'https://checkout.paymongo.com/cs_1'),
        body(url: 'https://evil.example/cs_1'),
        body(url: 'http://checkout.paymongo.com/cs_1'),
        {...body(), 'allocations': ['not a map']},
      ]) {
        expect(() => parsePaymongoCheckoutResponse(data, 'd-1'),
            throwsA(anything), reason: '$data');
      }
    });
  });

  group('CheckoutPage PayMongo launch', () {
    const goodUrl = 'https://checkout.paymongo.com/cs_new123';
    const staleUrl = 'https://checkout.paymongo.com/cs_stale999';

    late List<Uri> launched;
    Future<bool> launcher(Uri uri) async {
      launched.add(uri);
      return true;
    }

    setUp(() => launched = []);

    int fetches(FakeCheckoutService s) => s.calls.where((c) => c == 'fetch').length;

    Future<void> tapContinue(WidgetTester tester) async {
      // The donor confirms the final review before continuing to GCash.
      await _confirmReview(tester);
      await tester.tap(find.byIcon(Icons.open_in_new_rounded));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('successful checkout launches the new URL and starts polling', (tester) async {
      final service = FakeCheckoutService(_checkout(provider: 'paymongo'));
      service.onStartPaymongo = () async =>
          _checkout(provider: 'paymongo', status: 'processing', checkoutUrl: goodUrl);
      await _pumpCheckout(tester, service, launcher: launcher);

      final before = fetches(service);
      await tester.pump(const Duration(seconds: 10));
      expect(fetches(service), before, reason: 'no polling before a session exists');

      await tapContinue(tester);
      expect(launched, [Uri.parse(goodUrl)]);
      expect(find.textContaining('Could not open'), findsNothing);

      final afterLaunch = fetches(service);
      await tester.pump(const Duration(seconds: 9));
      expect(fetches(service), greaterThan(afterLaunch), reason: 'polls the server');

      await tester.pumpWidget(const SizedBox()); // dispose: cancels the poll timer
    });

    testWidgets('failed checkout shows the error, launches nothing, never polls', (tester) async {
      final service = FakeCheckoutService(_checkout(provider: 'paymongo'));
      service.onStartPaymongo = () async => throw const DonationCheckoutException(
          'PAYMONGO_UNAVAILABLE',
          'The PayMongo test checkout could not be opened. Please try again.');
      await _pumpCheckout(tester, service, launcher: launcher);

      await tapContinue(tester);
      expect(launched, isEmpty);
      expect(find.text('The PayMongo test checkout could not be opened. Please try again.'),
          findsOneWidget);

      final afterFailure = fetches(service);
      await tester.pump(const Duration(seconds: 20));
      expect(fetches(service), afterFailure, reason: 'polling must not start after failure');
      // The button is usable again (loading state cleared).
      final button = tester.widget<ElevatedButton>(find.ancestor(
          of: find.byIcon(Icons.open_in_new_rounded), matching: find.byType(ElevatedButton)));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('a stale URL is never launched after a failed request', (tester) async {
      // The page already holds an older checkout URL (e.g. from a previous
      // load); the new request fails, so that old URL must not be opened.
      final service = FakeCheckoutService(
          _checkout(provider: 'paymongo', checkoutUrl: staleUrl));
      service.onStartPaymongo = () async =>
          throw const DonationCheckoutException('PAYMONGO_UNAVAILABLE', 'failed');
      await _pumpCheckout(tester, service, launcher: launcher);
      expect(find.text('Reopen PayMongo test checkout'), findsOneWidget);

      await tapContinue(tester);
      final afterFailure = fetches(service);
      await tester.pump(const Duration(seconds: 20));
      expect(launched, isEmpty);
      expect(find.text('failed'), findsOneWidget);
      expect(fetches(service), afterFailure, reason: 'no polling after a failed request');
    });

    testWidgets('nothing is launched if the page closes while the request is in flight',
        (tester) async {
      final service = FakeCheckoutService(_checkout(provider: 'paymongo'));
      final pending = Completer<DonationCheckout>();
      service.onStartPaymongo = () => pending.future;
      await _pumpCheckout(tester, service, launcher: launcher);

      await tapContinue(tester);
      await tester.pumpWidget(const SizedBox()); // page disposed mid-request
      pending.complete(
          _checkout(provider: 'paymongo', status: 'processing', checkoutUrl: goodUrl));
      await tester.pump(const Duration(seconds: 10));
      expect(launched, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an untrusted URL from the server is rejected, not launched', (tester) async {
      for (final bad in [
        'https://evil.example/cs_1',
        'http://checkout.paymongo.com/cs_1',
        'https://checkout.paymongo.com.evil.example/cs_1',
        'javascript:alert(1)',
      ]) {
        final service = FakeCheckoutService(_checkout(provider: 'paymongo'));
        service.onStartPaymongo = () async =>
            _checkout(provider: 'paymongo', status: 'processing', checkoutUrl: bad);
        await _pumpCheckout(tester, service, launcher: launcher);

        await tapContinue(tester);
        final afterReject = fetches(service);
        await tester.pump(const Duration(seconds: 10));
        expect(launched, isEmpty, reason: bad);
        expect(find.textContaining('link was not valid'), findsOneWidget, reason: bad);
        expect(fetches(service), afterReject, reason: 'no polling for $bad');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a launcher failure is reported but the session is still followed', (tester) async {
      final service = FakeCheckoutService(_checkout(provider: 'paymongo'));
      service.onStartPaymongo = () async =>
          _checkout(provider: 'paymongo', status: 'processing', checkoutUrl: goodUrl);
      await _pumpCheckout(tester, service, launcher: (uri) async => false);

      await tapContinue(tester);
      expect(find.text('Could not open the PayMongo test checkout.'), findsOneWidget);
      final afterLaunch = fetches(service);
      await tester.pump(const Duration(seconds: 9));
      expect(fetches(service), greaterThan(afterLaunch));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a resumed processing checkout keeps polling the server', (tester) async {
      final service = FakeCheckoutService(
          _checkout(provider: 'paymongo', status: 'processing', checkoutUrl: goodUrl));
      await _pumpCheckout(tester, service, launcher: launcher);
      final start = fetches(service);
      await tester.pump(const Duration(seconds: 9));
      expect(fetches(service), greaterThan(start));
      expect(launched, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
