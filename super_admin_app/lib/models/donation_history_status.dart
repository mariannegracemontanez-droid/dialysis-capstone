/// How a donation's status reads in the Super Admin donation history.
///
/// Two kinds of `donations` rows exist:
///  * **Donation-app checkouts** (`payment_environment` set): the outcome is
///    in `payment_status`. Their legacy `status` column is not the outcome --
///    a completed simulated payment keeps `status = 'pending'` and a failed
///    or cancelled one gets `status = 'rejected'` -- so it is never used for
///    the label. Labels match the Donation Transactions section.
///  * **Older donations** (`payment_environment` null): verified / rejected /
///    pending by Admin review, exactly as before.
///
/// Only [countsAsReceived] says whether a row is money received; a simulated
/// payment never is.
enum DonationHistoryTone { received, pending, negative, simulated }

bool isCheckoutDonation(String? paymentEnvironment) =>
    paymentEnvironment != null && paymentEnvironment.trim().isNotEmpty;

String donationHistoryStatusLabel({
  required String status,
  String? paymentStatus,
  String? paymentEnvironment,
}) {
  if (!isCheckoutDonation(paymentEnvironment)) {
    switch (status) {
      case 'verified':
        return 'Received';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }
  final sandbox = paymentEnvironment == 'sandbox';
  switch (paymentStatus) {
    case 'simulated_paid':
      return 'Completed (simulated)';
    case 'paid':
      return sandbox ? 'Completed (test mode)' : 'Received';
    case 'processing':
      return 'Processing';
    case 'failed':
      return 'Failed';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Pending';
  }
}

DonationHistoryTone donationHistoryTone({
  required String status,
  String? paymentStatus,
  String? paymentEnvironment,
}) {
  if (countsAsReceived(status: status, paymentEnvironment: paymentEnvironment)) {
    return DonationHistoryTone.received;
  }
  if (!isCheckoutDonation(paymentEnvironment)) {
    return status == 'rejected' ? DonationHistoryTone.negative : DonationHistoryTone.pending;
  }
  switch (paymentStatus) {
    case 'simulated_paid':
    case 'paid':
      return DonationHistoryTone.simulated;
    case 'failed':
    case 'cancelled':
      return DonationHistoryTone.negative;
    default:
      return DonationHistoryTone.pending;
  }
}

/// Money actually received: a verified donation outside the sandbox. The same
/// rule as the Total Donations figure and received-donation exports
/// (`status = 'verified'`; the database never verifies a sandbox payment).
bool countsAsReceived({required String status, String? paymentEnvironment}) =>
    status == 'verified' && paymentEnvironment != 'sandbox';
