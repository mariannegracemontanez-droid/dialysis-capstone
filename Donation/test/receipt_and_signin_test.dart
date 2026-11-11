import 'package:donation_app/pages/donation_option_page.dart';
import 'package:donation_app/services/donation_checkout_service.dart';
import 'package:donation_app/services/donation_receipt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DonationCheckout _checkout({
  String status = 'simulated_paid',
  String environment = 'sandbox',
  String provider = 'internal_simulator',
  String reference = 'CN-SBX-0123456789',
  List<Map<String, dynamic>>? allocations,
}) =>
    DonationCheckout.fromJson({
      'donation_id': 'd-1',
      'reference': reference,
      'mode': 'equal_distribution',
      'amount_centavos': 100000,
      'payment_provider': provider,
      'payment_environment': environment,
      'payment_status': status,
      'created_at': '2026-11-10T02:00:00Z',
      'payment_confirmed_at': '2026-11-10T02:01:00Z',
      'allocations': allocations ??
          [
            {'clinic_id': 'a', 'clinic_name': 'Alpha <Center> & Co', 'amount_centavos': 33334, 'allocation_status': 'simulated'},
            {'clinic_id': 'b', 'clinic_name': 'Beta', 'amount_centavos': 33333, 'allocation_status': 'simulated'},
            {'clinic_id': 'c', 'clinic_name': 'Gamma', 'amount_centavos': 33333, 'allocation_status': 'simulated'},
          ],
    });

void main() {
  group('DonationReceipt', () {
    test('simulated donation: acknowledgement, never a payment receipt', () {
      final r = DonationReceipt(_checkout(), generatedAt: DateTime(2026, 11, 10, 10, 5));
      expect(r.isLivePayment, isFalse);
      expect(r.title, 'Donation Acknowledgement');
      expect(r.fileName, 'CureNurture-acknowledgement-CN-SBX-0123456789.html');
      final html = r.toHtml();
      expect(html, contains('Donation Acknowledgement'));
      expect(html, contains('Completed with a simulated payment (no real money)'));
      expect(html, contains('no money was charged and no funds were transferred to any center'));
      expect(html, isNot(contains('Donation Receipt')));
      expect(html, isNot(contains('Payment confirmed')));
    });

    test('carries the server-recorded reference, dates, amount, mode and allocation', () {
      final r = DonationReceipt(_checkout());
      final details = {for (final (k, v) in r.details) k: v};
      expect(details['Reference'], 'CN-SBX-0123456789');
      expect(details['Amount'], '₱1,000.00');
      expect(details['Donation option'], 'Shared equally among all centers');
      expect(details['Payment method'], 'GCash');
      expect(details.containsKey('Donation date'), isTrue);
      expect(details.containsKey('Completed'), isTrue);
      expect(r.allocatedCentavos, 100000);
      final html = r.toHtml();
      expect(html, contains('₱333.34'));
      expect(html, contains('₱333.33'));
      expect(html, contains('Total</td><td class="num">₱1,000.00'));
      // Centre names are escaped, never injected as markup.
      expect(html, contains('Alpha &lt;Center&gt; &amp; Co'));
      expect(html, isNot(contains('<Center>')));
    });

    test('PayMongo test mode is still not a payment receipt', () {
      final r = DonationReceipt(_checkout(status: 'paid', provider: 'paymongo'));
      expect(r.isLivePayment, isFalse);
      expect(r.title, 'Donation Acknowledgement');
      expect(r.paymentStatusText, contains('test mode'));
      expect(r.toHtml(), contains('This is not a payment receipt'));
    });

    test('a confirmed live payment gets a real receipt', () {
      final r = DonationReceipt(_checkout(status: 'paid', environment: 'production', provider: 'paymongo', reference: 'CN-LIVE-1'));
      expect(r.isLivePayment, isTrue);
      expect(r.title, 'Donation Receipt');
      expect(r.paymentStatusText, 'Payment confirmed');
      expect(r.disclosure, isEmpty);
      expect(r.fileName, 'CureNurture-receipt-CN-LIVE-1.html');
      expect(r.toHtml(), isNot(contains('not a payment receipt')));
    });

    test('pending, failed and cancelled donations get no document', () {
      for (final status in ['pending', 'processing', 'failed', 'cancelled']) {
        expect(() => DonationReceipt(_checkout(status: status)), throwsStateError, reason: status);
      }
    });
  });

  group('Registered donation sign-in', () {
    test('a signed-in donor goes straight to the form; only a signed-out one is sent to log in', () {
      expect(registeredDonationStep(signedIn: true), RegisteredDonationStep.donationForm);
      expect(registeredDonationStep(signedIn: false), RegisteredDonationStep.login);
    });

    Future<void> pump(WidgetTester tester, {required bool signedIn}) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: DonationOptionPage(isSignedIn: () => signedIn)));
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('signed-in donors are not asked to log in again', (tester) async {
      await pump(tester, signedIn: true);
      expect(find.textContaining('You are already signed in'), findsOneWidget);
      expect(find.textContaining('Log in to your donor account'), findsNothing);
    });

    testWidgets('signed-out donors are told a login comes next', (tester) async {
      await pump(tester, signedIn: false);
      expect(find.textContaining('Log in to your donor account'), findsOneWidget);
      expect(find.textContaining('You are already signed in'), findsNothing);
    });
  });
}
