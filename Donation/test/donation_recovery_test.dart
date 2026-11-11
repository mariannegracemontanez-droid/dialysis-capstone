import 'dart:convert';

import 'package:donation_app/pages/checkout_page.dart';
import 'package:donation_app/services/donation_checkout_service.dart';
import 'package:donation_app/widgets/unfinished_donation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DonationCheckout _checkout({String status = 'pending', String mode = 'equal_distribution'}) =>
    DonationCheckout.fromJson({
      'donation_id': 'd-1',
      'reference': 'CN-SBX-REVIEW0001',
      'mode': mode,
      'amount_centavos': 100001,
      'payment_provider': 'internal_simulator',
      'payment_environment': 'sandbox',
      'payment_status': status,
      'payment_confirmed_at': status == 'simulated_paid' ? '2026-11-09T15:30:00Z' : null,
      'allocations': [
        {'clinic_id': 'a', 'clinic_name': 'Alpha Dialysis', 'amount_centavos': 33334, 'allocation_status': 'awaiting_payment'},
        {'clinic_id': 'b', 'clinic_name': 'Beta Dialysis', 'amount_centavos': 33334, 'allocation_status': 'awaiting_payment'},
        {'clinic_id': 'c', 'clinic_name': 'Gamma Dialysis', 'amount_centavos': 33333, 'allocation_status': 'awaiting_payment'},
      ],
    });

class _FakeService implements DonationCheckoutService {
  _FakeService(this.current);
  DonationCheckout current;
  final calls = <String>[];

  @override
  Future<DonationCheckout> fetchCheckout(String id, String secret) async {
    calls.add('fetch');
    return current;
  }

  @override
  Future<DonationCheckout> simulate(String id, String secret, String outcome) async {
    calls.add('simulate:$outcome');
    final status = switch (outcome) { 'success' => 'simulated_paid', 'failure' => 'failed', _ => 'cancelled' };
    return current = _checkout(status: status);
  }

  @override
  Future<DonationCheckout> cancel(String id, String secret) async {
    calls.add('cancel');
    return current = _checkout(status: 'cancelled');
  }

  @override
  Future<void> clearPending() async => calls.add('clear');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('unfinished donation is bound to who started it', () {
    PendingCheckout decode(Map<String, Object?> m) => decodePendingCheckout(jsonEncode(m))!;

    test('owner is stored and read back', () {
      final r = CheckoutRequest(mode: DonationMode.randomCenter, amountCentavos: 5000, anonymous: false);
      final p = decodePendingCheckout(encodePendingCheckout('d-1', r.clientSecret, request: r, owner: 'user-1'))!;
      expect(p.owner, 'user-1');
      final a = CheckoutRequest(mode: DonationMode.randomCenter, amountCentavos: 5000, anonymous: true);
      expect(decodePendingCheckout(encodePendingCheckout('d-2', a.clientSecret, request: a,
          owner: kAnonymousPendingOwner))!.owner, kAnonymousPendingOwner);
    });

    test('a signed-in donor is only offered their own unfinished donation', () {
      final mine = decode({'id': 'd', 'secret': 's', 'owner': 'user-1'});
      expect(pendingBelongsTo(mine, anonymousFlow: false, userId: 'user-1'), isTrue);
      expect(pendingBelongsTo(mine, anonymousFlow: false, userId: 'user-2'), isFalse); // shared browser
      expect(pendingBelongsTo(mine, anonymousFlow: false, userId: null), isFalse);
      expect(pendingBelongsTo(mine, anonymousFlow: true), isFalse);
    });

    test('the anonymous flow is only offered anonymous donations', () {
      final anon = decode({'id': 'd', 'secret': 's', 'owner': kAnonymousPendingOwner});
      expect(pendingBelongsTo(anon, anonymousFlow: true), isTrue);
      expect(pendingBelongsTo(anon, anonymousFlow: false, userId: 'user-1'), isFalse);
    });

    test('older entries: anonymous requests stay anonymous, unknown owners are never offered', () {
      final legacyAnon = decode({'id': 'd', 'secret': 's', 'request': {
        'mode': 'random_center', 'amount_centavos': 5000, 'clinic_id': null,
        'anonymous': true, 'idempotency_key': 'k' * 32}});
      expect(legacyAnon.owner, kAnonymousPendingOwner);
      final legacyRegistered = decode({'id': 'd', 'secret': 's', 'request': {
        'mode': 'random_center', 'amount_centavos': 5000, 'clinic_id': null,
        'anonymous': false, 'idempotency_key': 'k' * 32}});
      expect(legacyRegistered.owner, isNull);
      expect(pendingBelongsTo(legacyRegistered, anonymousFlow: false, userId: 'user-1'), isFalse);
      expect(pendingBelongsTo(legacyRegistered, anonymousFlow: true), isFalse);
      final bare = decode({'id': 'd', 'secret': 's'});
      expect(bare.owner, isNull);
    });
  });

  test('restored amount text reads back to the same centavos', () {
    for (final c in [2000, 25000, 50000, 100000, 100001, 123456, 10000000]) {
      expect(parseAmountToCentavos(centavosToAmountInput(c)), c, reason: '$c');
    }
    expect(centavosToAmountInput(25000), '250');
    expect(centavosToAmountInput(100001), '1000.01');
    expect(centavosToAmountInput(0), '');
  });

  group('continue / start over dialog', () {
    late UnfinishedDonationChoice? dialogResult;
    late bool dialogClosed;

    Future<void> open(WidgetTester tester) async {
      dialogResult = UnfinishedDonationChoice.continueDonation; // sentinel
      dialogClosed = false;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () async {
            dialogResult = await showUnfinishedDonationDialog(context, _checkout());
            dialogClosed = true;
          },
          child: const Text('open'),
        )),
      ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(dialogClosed, isFalse);
      // The server-side details are shown before the donor decides.
      expect(find.text('Continue your donation?'), findsOneWidget);
      expect(find.text('CN-SBX-REVIEW0001'), findsOneWidget);
      expect(find.text('₱1,000.01'), findsOneWidget);
      expect(find.text('Donate to All Centers (equal split)'), findsOneWidget);
      expect(find.text('Gamma Dialysis'), findsOneWidget);
      expect(find.text('₱333.34'), findsNWidgets(2));
      expect(find.text('₱333.33'), findsOneWidget);
    }

    testWidgets('Continue returns continue', (tester) async {
      UnfinishedDonationChoice? r;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: ElevatedButton(onPressed: () async => r = await showUnfinishedDonationDialog(context, _checkout()),
            child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('unfinished-continue')));
      await tester.pumpAndSettle();
      expect(r, UnfinishedDonationChoice.continueDonation);
    });

    testWidgets('Start over needs an explicit second confirmation', (tester) async {
      UnfinishedDonationChoice? r;
      var finished = false;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: ElevatedButton(onPressed: () async {
          r = await showUnfinishedDonationDialog(context, _checkout());
          finished = true;
        }, child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Start over -> confirmation -> "Keep it" goes back to the question.
      await tester.tap(find.byKey(const ValueKey('unfinished-start-over')));
      await tester.pumpAndSettle();
      expect(find.text('Start over?'), findsOneWidget);
      expect(find.textContaining('This cancels your unfinished donation CN-SBX-REVIEW0001'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start-over-keep')));
      await tester.pumpAndSettle();
      expect(finished, isFalse);
      expect(find.text('Continue your donation?'), findsOneWidget);

      // Start over -> confirm -> start over.
      await tester.tap(find.byKey(const ValueKey('unfinished-start-over')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-over-confirm')));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(r, UnfinishedDonationChoice.startOver);
    });

    testWidgets('shows the server-side details, and dismissing decides nothing', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(5, 5)); // outside the dialog
      await tester.pumpAndSettle();
      expect(dialogClosed, isTrue);
      expect(dialogResult, isNull);
      expect(find.text('Continue your donation?'), findsNothing);
    });
  });

  group('final review and completion', () {
    Future<_FakeService> pump(WidgetTester tester, {bool testOutcomes = false, Size size = const Size(1000, 2600)}) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final service = _FakeService(_checkout());
      await tester.pumpWidget(MaterialApp(home: CheckoutPage(
          checkout: service.current, clientSecret: 's', service: service,
          showTestOutcomes: testOutcomes)));
      await tester.pump();
      return service;
    }

    testWidgets('donor view: one primary action, small sandbox notice, no simulator buttons', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('complete-donation')), findsOneWidget);
      expect(find.text('Complete donation'), findsOneWidget);
      expect(find.text('Complete your donation'), findsOneWidget);
      expect(find.byKey(const ValueKey('sandbox-notice')), findsOneWidget);
      expect(find.text('Payments are simulated — no real money is charged or transferred.'), findsOneWidget);
      // Removed from the donor interface:
      for (final gone in ['Simulate successful payment', 'Simulate failed payment', 'Simulate cancelled payment',
          'DEMO MODE — NO REAL MONEY TRANSFERRED', 'Pay with GCash']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(find.textContaining('Demo simulator'), findsNothing);
      expect(find.byKey(const ValueKey('test-outcomes')), findsNothing);
      expect(find.text('Donation Checkout'), findsOneWidget); // not "GCash Checkout"
    });

    testWidgets('checkout lays out on a 320px phone without overflow', (tester) async {
      await pump(tester, size: const Size(320, 2600));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('review-confirm')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel this donation asks first; Keep it does nothing', (tester) async {
      final service = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('cancel-donation')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this donation?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-keep')));
      await tester.pumpAndSettle();
      expect(service.calls, isNot(contains('cancel')));

      await tester.tap(find.byKey(const ValueKey('cancel-donation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-confirm')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('cancel'));
      expect(find.text('Donation cancelled'), findsOneWidget);
      expect(find.text('Thank You!'), findsNothing);
    });

    testWidgets('submission is disabled until the donor confirms the review', (tester) async {
      final service = await pump(tester);
      final success = find.byKey(const ValueKey('complete-donation'));
      expect(tester.widget<ButtonStyleButton>(success).onPressed, isNull);
      await tester.tap(success, warnIfMissed: false);
      await tester.pump();
      expect(service.calls, isNot(contains('simulate:success')));
      expect(find.textContaining('I have reviewed this donation of ₱1,000.01'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('review-confirm')));
      await tester.pump();
      await tester.tap(success);
      await tester.pumpAndSettle();
      expect(service.calls, contains('simulate:success'));
    });

    testWidgets('tapping the confirmation sentence also ticks it', (tester) async {
      final service = await pump(tester);
      await tester.tap(find.textContaining('I have reviewed this donation'));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('review-confirm'))).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('complete-donation')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('simulate:success'));
    });

    testWidgets('developer test outcomes (failed / cancelled) are not presented as success', (tester) async {
      final service = await pump(tester, testOutcomes: true);
      expect(find.byKey(const ValueKey('test-outcomes')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('simulate-cancel')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('simulate:cancel'));
      expect(find.text('Donation cancelled'), findsOneWidget);
      expect(find.text('Thank You!'), findsNothing);
      expect(find.byKey(const ValueKey('donate-again')), findsNothing);
    });

    testWidgets('success shows a thank-you completion screen with the details', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-confirm')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('complete-donation')));
      await tester.pumpAndSettle();

      expect(find.text('Thank You!'), findsOneWidget);
      expect(find.text('Donation complete'), findsOneWidget);
      expect(find.textContaining('no real money was charged'), findsOneWidget);
      final details = tester.widget<Text>(find.byKey(const ValueKey('completion-details'))).data!;
      expect(details, contains('Reference CN-SBX-REVIEW0001'));
      expect(details, contains('₱1,000.01'));
      expect(details, contains('confirmed 2026-11-09'));
      final receipt = find.byKey(const ValueKey('receipt-allocations'));
      expect(find.descendant(of: receipt, matching: find.text('Gamma Dialysis')), findsOneWidget);
      expect(find.descendant(of: receipt, matching: find.text('₱333.34')), findsNWidgets(2));
      expect(find.descendant(of: receipt, matching: find.text('₱333.33')), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);
      expect(find.byKey(const ValueKey('donate-again')), findsOneWidget);
    });
  });
}
