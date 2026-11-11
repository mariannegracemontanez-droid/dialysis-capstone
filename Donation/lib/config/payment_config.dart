/// Donor-facing payment channels.
///
/// Bank Transfer is hidden for the GCash sandbox demo. Nothing about bank
/// accounts was deleted -- set this back to `true` to show the Bank Transfer
/// option on the donation page again (see DONATION_SANDBOX_GUIDE.md,
/// "Restoring Bank Transfer", for the server-side half of that change).
const bool kBankTransferEnabled = false;

/// The `donations.payment_method` value GCash donations are recorded with
/// (the same value the page has always written).
const String kGcashMethod = 'GCASH';
const String kBankTransferMethod = 'BANK TRANSFER';

/// Short sandbox notice shown on the donation screens while the server is in
/// sandbox mode: clear, but deliberately small.
const String kDemoBannerText =
    'Payments are simulated — no real money is charged or transferred.';

/// Developer/test-only simulator outcomes (failed / cancelled) on checkout.
/// Off for donors. Enable only for local testing with:
///   flutter run -d edge --dart-define=CURENURTURE_SIMULATOR_TEST_CONTROLS=true
const bool kSimulatorTestControls =
    bool.fromEnvironment('CURENURTURE_SIMULATOR_TEST_CONTROLS');
