/// Donation KPIs and monthly trends for the Super Admin dashboard, computed
/// from `donations` rows only (no new tables, no stored totals).
///
/// The categories follow the database's own rules:
///  * **Collected funds** -- `status = 'verified'`. That is an Admin-verified
///    donation, or a live checkout whose payment the provider confirmed
///    (`donation_finalize()` sets `verified` only for production payments).
///    A simulated payment can never be `verified`
///    (constraint `donations_sandbox_never_verified`), and is excluded here
///    a second time on purpose.
///  * **Awaiting verification** -- donations recorded outside the checkout
///    workflow (`payment_environment` null) that are still `pending`.
///  * **Simulated payments** -- completed checkouts in the sandbox. They are
///    activity only: never money, never part of collected funds.
///  * **Open / failed / cancelled checkouts** -- the checkout's
///    `payment_status`.
///
/// Amounts are kept in centavos (integers) so totals never drift.
class DonationOverview {
  const DonationOverview({
    required this.collectedCentavos,
    required this.collectedCount,
    required this.awaitingVerificationCentavos,
    required this.awaitingVerificationCount,
    required this.simulatedCompletedCentavos,
    required this.simulatedCompletedCount,
    required this.openCheckoutCount,
    required this.failedOrCancelledCount,
    required this.rejectedCount,
    required this.transactionCount,
    required this.trend,
  });

  final int collectedCentavos;
  final int collectedCount;
  final int awaitingVerificationCentavos;
  final int awaitingVerificationCount;
  final int simulatedCompletedCentavos;
  final int simulatedCompletedCount;
  final int openCheckoutCount;
  final int failedOrCancelledCount;
  final int rejectedCount;

  /// Every donation record (all states).
  final int transactionCount;

  /// One point per calendar month, oldest first, ending with the current month.
  final List<DonationTrendPoint> trend;

  /// Builds the overview from `donations` rows. [now] fixes "the current
  /// month" (injectable for tests); [months] is the trend length.
  factory DonationOverview.fromRows(
    Iterable<Map<String, dynamic>> rows, {
    required DateTime now,
    int months = 6,
  }) {
    final firstMonth = DateTime(now.year, now.month - (months - 1));
    final points = [
      for (var i = 0; i < months; i++)
        _MutablePoint(DateTime(firstMonth.year, firstMonth.month + i)),
    ];

    var collected = 0, collectedCount = 0;
    var awaiting = 0, awaitingCount = 0;
    var simulated = 0, simulatedCount = 0;
    var open = 0, failed = 0, rejected = 0, total = 0;

    for (final row in rows) {
      final kind = classifyDonationRow(row);
      final centavos = donationRowCentavos(row);
      total++;

      switch (kind) {
        case DonationRowKind.collected:
          collected += centavos;
          collectedCount++;
        case DonationRowKind.awaitingVerification:
          awaiting += centavos;
          awaitingCount++;
        case DonationRowKind.simulatedCompleted:
          simulated += centavos;
          simulatedCount++;
        case DonationRowKind.openCheckout:
          open++;
        case DonationRowKind.failedOrCancelled:
          failed++;
        case DonationRowKind.rejected:
          rejected++;
        case DonationRowKind.other:
          break;
      }

      final created = DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal();
      if (created == null) continue;
      final index = (created.year - firstMonth.year) * 12 + created.month - firstMonth.month;
      if (index < 0 || index >= points.length) continue;
      final p = points[index];
      p.transactions++;
      if (kind == DonationRowKind.collected) {
        p.collectedCentavos += centavos;
        p.collectedCount++;
      } else if (kind == DonationRowKind.simulatedCompleted) {
        p.simulatedCentavos += centavos;
        p.simulatedCount++;
      }
    }

    return DonationOverview(
      collectedCentavos: collected,
      collectedCount: collectedCount,
      awaitingVerificationCentavos: awaiting,
      awaitingVerificationCount: awaitingCount,
      simulatedCompletedCentavos: simulated,
      simulatedCompletedCount: simulatedCount,
      openCheckoutCount: open,
      failedOrCancelledCount: failed,
      rejectedCount: rejected,
      transactionCount: total,
      trend: [for (final p in points) p.freeze()],
    );
  }
}

class DonationTrendPoint {
  const DonationTrendPoint({
    required this.month,
    required this.collectedCentavos,
    required this.collectedCount,
    required this.simulatedCentavos,
    required this.simulatedCount,
    required this.transactions,
  });

  /// First day of the month (local time).
  final DateTime month;
  final int collectedCentavos;
  final int collectedCount;
  final int simulatedCentavos;
  final int simulatedCount;

  /// Every donation record created in the month, whatever its state.
  final int transactions;

  /// Records that are neither collected nor completed simulated payments
  /// (pending, awaiting verification, failed, cancelled, rejected).
  int get otherCount => transactions - collectedCount - simulatedCount;
}

class _MutablePoint {
  _MutablePoint(this.month);
  final DateTime month;
  int collectedCentavos = 0, collectedCount = 0;
  int simulatedCentavos = 0, simulatedCount = 0, transactions = 0;

  DonationTrendPoint freeze() => DonationTrendPoint(
        month: month,
        collectedCentavos: collectedCentavos,
        collectedCount: collectedCount,
        simulatedCentavos: simulatedCentavos,
        simulatedCount: simulatedCount,
        transactions: transactions,
      );
}

enum DonationRowKind {
  collected,
  awaitingVerification,
  simulatedCompleted,
  openCheckout,
  failedOrCancelled,
  rejected,
  other,
}

/// Which bucket a `donations` row belongs to (see [DonationOverview]).
DonationRowKind classifyDonationRow(Map<String, dynamic> row) {
  final status = row['status']?.toString().trim().toLowerCase() ?? '';
  final environment = row['payment_environment']?.toString();
  final paymentStatus = row['payment_status']?.toString() ?? '';
  final isSimulatedEnvironment = environment == 'sandbox';

  if (status == 'verified' && !isSimulatedEnvironment) return DonationRowKind.collected;

  if (environment == null) {
    if (status == 'pending') return DonationRowKind.awaitingVerification;
    if (status == 'rejected') return DonationRowKind.rejected;
    return DonationRowKind.other;
  }

  switch (paymentStatus) {
    case 'simulated_paid':
      return DonationRowKind.simulatedCompleted;
    case 'paid':
      return isSimulatedEnvironment ? DonationRowKind.simulatedCompleted : DonationRowKind.other;
    case 'pending':
    case 'processing':
      return DonationRowKind.openCheckout;
    case 'failed':
    case 'cancelled':
      return DonationRowKind.failedOrCancelled;
    default:
      return DonationRowKind.other;
  }
}

/// The row's amount in centavos: `amount_centavos` when recorded, otherwise
/// the peso `amount` (older rows) rounded to the centavo.
int donationRowCentavos(Map<String, dynamic> row) {
  final centavos = row['amount_centavos'];
  if (centavos is int) return centavos;
  if (centavos is num) return centavos.round();
  final parsed = int.tryParse(centavos?.toString() ?? '');
  if (parsed != null) return parsed;
  final pesos = double.tryParse(row['amount']?.toString() ?? '') ?? 0;
  return (pesos * 100).round();
}
