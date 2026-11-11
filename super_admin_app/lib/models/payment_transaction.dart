/// A donation created through the server-side GCash checkout workflow
/// (supabase_migration_donation_sandbox.sql), with its recipient
/// allocations. Legacy donations (no payment_environment) are not modelled
/// here; they stay in the existing [DonationRecord] history.
class PaymentTransaction {
  const PaymentTransaction({
    required this.id,
    required this.reference,
    required this.createdAt,
    required this.mode,
    required this.amountCentavos,
    required this.paymentMethod,
    required this.paymentProvider,
    required this.paymentEnvironment,
    required this.paymentStatus,
    required this.allocations,
    this.statusReason,
    this.confirmedAt,
    this.donorLabel,
  });

  final String id;
  final String reference;
  final DateTime createdAt;
  final String? mode;
  final int amountCentavos;
  final String paymentMethod;
  final String paymentProvider;
  final String paymentEnvironment;
  final String paymentStatus;
  final String? statusReason;
  final DateTime? confirmedAt;
  final String? donorLabel;
  final List<PaymentAllocation> allocations;

  bool get isSandbox => paymentEnvironment == 'sandbox';
  bool get isSimulated => paymentProvider == 'internal_simulator';

  /// A real, provider-confirmed payment in production. The ONLY kind that
  /// may ever be counted as collected funds.
  bool get countsAsCollectedFunds =>
      paymentEnvironment == 'production' && paymentStatus == 'paid';

  /// Sandbox payment that completed (simulated, or PayMongo test mode).
  bool get isSandboxCompleted =>
      isSandbox && (paymentStatus == 'simulated_paid' || paymentStatus == 'paid');

  /// The checkout finished successfully: a confirmed live payment or a
  /// completed simulated one. Activity only -- see [countsAsCollectedFunds]
  /// for money.
  bool get isCompleted => paymentStatus == 'simulated_paid' || paymentStatus == 'paid';

  /// How the payment was processed, in donor-facing terms.
  String get paymentTypeLabel {
    if (isSimulated) return 'Simulated payment';
    if (isSandbox) return 'PayMongo test mode';
    return 'Live payment';
  }

  int get allocatedCentavos =>
      allocations.fold(0, (sum, a) => sum + a.amountCentavos);

  String get modeLabel {
    switch (mode) {
      case 'specific_center':
        return 'Specific Center';
      case 'random_center':
        return 'Random Center';
      case 'equal_distribution':
        return 'Donate to All';
      default:
        return 'Not recorded';
    }
  }

  String get environmentLabel => isSandbox ? 'SANDBOX' : 'PRODUCTION';

  String get providerLabel {
    switch (paymentProvider) {
      case 'internal_simulator':
        return 'Payment simulator';
      case 'paymongo':
        return isSandbox ? 'PayMongo (test mode)' : 'PayMongo';
      default:
        return paymentProvider.isEmpty ? '--' : paymentProvider;
    }
  }

  String get paymentStatusLabel {
    switch (paymentStatus) {
      case 'pending':
        return 'Pending';
      case 'processing':
        return 'Processing';
      case 'simulated_paid':
        return 'Completed (simulated)';
      case 'paid':
        return isSandbox ? 'Completed (test mode)' : 'Paid';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return paymentStatus;
    }
  }

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    final rawAllocations = json['donation_allocations'];
    final allocations = rawAllocations is List
        ? [
            for (final item in rawAllocations)
              PaymentAllocation.fromJson(Map<String, dynamic>.from(item as Map)),
          ]
        : <PaymentAllocation>[];
    allocations.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final name = json['name']?.toString();

    return PaymentTransaction(
      id: json['id']?.toString() ?? '',
      reference: json['reference_code']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      mode: json['allocation_type']?.toString(),
      amountCentavos: _asInt(json['amount_centavos']),
      paymentMethod: json['payment_method']?.toString() ?? '',
      paymentProvider: json['payment_provider']?.toString() ?? '',
      paymentEnvironment: json['payment_environment']?.toString() ?? '',
      paymentStatus: json['payment_status']?.toString() ?? '',
      statusReason: json['status_reason']?.toString(),
      confirmedAt:
          DateTime.tryParse(json['payment_confirmed_at']?.toString() ?? '')?.toLocal(),
      donorLabel: json['donor_id'] == null && (name == null || name.trim().isEmpty)
          ? 'Anonymous Donor'
          : name,
      allocations: allocations,
    );
  }
}

class PaymentAllocation {
  const PaymentAllocation({
    required this.clinicId,
    required this.clinicName,
    required this.amountCentavos,
    required this.status,
    required this.sortOrder,
    this.transferRef,
  });

  final String clinicId;
  final String clinicName;
  final int amountCentavos;
  final String status;
  final int sortOrder;
  final String? transferRef;

  /// Never says "paid out" for anything that is not a provider-confirmed
  /// real payout.
  String get statusLabel {
    switch (status) {
      case 'awaiting_payment':
        return 'Awaiting payment';
      case 'simulated':
        return 'Simulated — no funds transferred';
      case 'pending_payout':
        return 'Pending real payout';
      case 'paid_out':
        return 'Paid out (ref ${transferRef ?? '--'})';
      case 'void':
        return 'Void — not allocated';
      default:
        return status;
    }
  }

  factory PaymentAllocation.fromJson(Map<String, dynamic> json) {
    return PaymentAllocation(
      clinicId: json['clinic_id']?.toString() ?? '',
      clinicName: json['clinic_name_snapshot']?.toString() ?? 'Unnamed Center',
      amountCentavos: _asInt(json['amount_centavos']),
      status: json['allocation_status']?.toString() ?? '',
      sortOrder: _asInt(json['sort_order']),
      transferRef: json['provider_transfer_ref']?.toString(),
    );
  }
}

/// Figures for the transaction summary strip.
///
/// [collectedCentavos] is money: confirmed live payments only. Completed
/// checkouts (live or simulated) are activity: [completedCount] /
/// [completedCentavos], with [simulatedCompletedCount] saying how many of
/// them were simulated. A simulated amount is never part of collected funds.
class PaymentTransactionSummary {
  const PaymentTransactionSummary({
    required this.count,
    required this.collectedCentavos,
    required this.completedCount,
    required this.completedCentavos,
    required this.simulatedCompletedCount,
    required this.failedOrCancelledCount,
    required this.openCount,
  });

  final int count;
  final int collectedCentavos;
  final int completedCount;
  final int completedCentavos;
  final int simulatedCompletedCount;
  final int failedOrCancelledCount;
  final int openCount;

  factory PaymentTransactionSummary.of(Iterable<PaymentTransaction> transactions) {
    var count = 0, collected = 0, completed = 0, completedAmount = 0, simulated = 0, closed = 0, open = 0;
    for (final t in transactions) {
      count++;
      if (t.countsAsCollectedFunds) collected += t.amountCentavos;
      if (t.isCompleted) {
        completed++;
        completedAmount += t.amountCentavos;
        if (t.isSandboxCompleted) simulated++;
      }
      if (t.paymentStatus == 'failed' || t.paymentStatus == 'cancelled') closed++;
      if (t.paymentStatus == 'pending' || t.paymentStatus == 'processing') open++;
    }
    return PaymentTransactionSummary(
      count: count,
      collectedCentavos: collected,
      completedCount: completed,
      completedCentavos: completedAmount,
      simulatedCompletedCount: simulated,
      failedOrCancelledCount: closed,
      openCount: open,
    );
  }
}

/// Filters for the transaction list (all optional).
class PaymentTransactionFilter {
  const PaymentTransactionFilter({
    this.from,
    this.to,
    this.mode,
    this.paymentStatus,
    this.environment,
    this.clinicId,
    this.query,
  });

  final DateTime? from;
  final DateTime? to;
  final String? mode;
  final String? paymentStatus;
  final String? environment;
  final String? clinicId;

  /// Free-text search over the reference, donor label and recipient names.
  final String? query;

  bool matches(PaymentTransaction t) {
    final q = query?.trim().toLowerCase() ?? '';
    if (q.isNotEmpty &&
        !t.reference.toLowerCase().contains(q) &&
        !(t.donorLabel ?? '').toLowerCase().contains(q) &&
        !t.allocations.any((a) => a.clinicName.toLowerCase().contains(q))) {
      return false;
    }
    if (from != null && t.createdAt.isBefore(from!)) return false;
    // `to` is inclusive of the whole day.
    if (to != null &&
        !t.createdAt.isBefore(DateTime(to!.year, to!.month, to!.day + 1))) {
      return false;
    }
    if (mode != null && t.mode != mode) return false;
    if (paymentStatus != null && t.paymentStatus != paymentStatus) return false;
    if (environment != null && t.paymentEnvironment != environment) return false;
    if (clinicId != null && !t.allocations.any((a) => a.clinicId == clinicId)) {
      return false;
    }
    return true;
  }
}

String formatCentavosPhp(int centavos) {
  final pesos = (centavos.abs() ~/ 100).toString();
  final cents = (centavos.abs() % 100).toString().padLeft(2, '0');
  final grouped = StringBuffer();
  for (int i = 0; i < pesos.length; i++) {
    if (i > 0 && (pesos.length - i) % 3 == 0) grouped.write(',');
    grouped.write(pesos[i]);
  }
  return '${centavos < 0 ? '-' : ''}₱$grouped.$cents';
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
