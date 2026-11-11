/// One event from `donation_audit_logs`, as Super Admin monitors it: what
/// happened to which donation, for which center, by which kind of actor.
///
/// The account that performed an action (`performed_by`, an Auth user id) and
/// free-form `metadata` are deliberately not read: the actor is shown only as
/// a role ("Donor", "Payment simulator", "Super Admin", ...).
class DonationActivity {
  final String id;
  final String action;
  final String? donationId;
  final String? reference;
  final String? clinicId;
  final String clinicName;
  final double? amount;
  final String actor;
  final DateTime? createdAt;

  const DonationActivity({
    required this.id,
    required this.action,
    required this.donationId,
    required this.reference,
    required this.clinicId,
    required this.clinicName,
    required this.amount,
    required this.actor,
    required this.createdAt,
  });

  /// Human-readable activity label.
  String get label => donationActivityLabel(action);

  /// Activities that mean money did not (or will not) arrive.
  bool get isNegative =>
      action == 'PAYMENT_FAILED' || action == 'PAYMENT_CANCELLED' || action.contains('REJECT');
}

const Map<String, String> _labels = {
  'CHECKOUT_CREATED': 'Checkout started',
  'ALLOCATION_PLANNED': 'Allocation planned',
  'PAYMENT_SIMULATED_PAID': 'Simulated payment completed',
  'PAYMENT_PAID': 'Payment confirmed',
  'PAYMENT_FAILED': 'Payment failed',
  'PAYMENT_CANCELLED': 'Donation cancelled',
  'DONATION_RECEIVED': 'Donation received',
  'DONATION_ALLOCATED': 'Donation allocated',
  'DONATION_APPROVED': 'Donation approved',
  'DONATION_REJECTED': 'Donation rejected',
};

/// "PAYMENT_SIMULATED_PAID" -> "Simulated payment completed"; unknown actions
/// become sentence case ("SOME_NEW_EVENT" -> "Some new event").
String donationActivityLabel(String action) {
  final known = _labels[action];
  if (known != null) return known;
  final words = action.toLowerCase().split('_').where((w) => w.isNotEmpty).join(' ');
  return words.isEmpty ? 'Activity' : words[0].toUpperCase() + words.substring(1);
}

/// The kind of actor behind `from_entity` -- never an account identifier.
String donationActorLabel(String? fromEntity) {
  switch ((fromEntity ?? '').trim().toLowerCase()) {
    case 'donor':
      return 'Donor';
    case 'demo_simulator':
      return 'Payment simulator';
    case 'paymongo':
      return 'PayMongo (test)';
    case 'superadmin':
      return 'Super Admin';
    case 'donation_system':
    case 'system':
    case '':
      return 'System';
    default:
      // from_entity sometimes holds a center name for allocation events.
      return 'System';
  }
}

/// Maps audit rows to activities, newest first, one per id. [clinicNames]
/// maps clinic id -> name and [references] donation id -> reference code;
/// both come from separate reads so no donor data is ever joined in.
List<DonationActivity> donationActivityFromRows(
  List<dynamic> rows, {
  Map<String, String> clinicNames = const {},
  Map<String, String> references = const {},
}) {
  final byId = <String, DonationActivity>{};
  final withoutId = <DonationActivity>[];

  for (final row in rows) {
    if (row is! Map) continue;
    final id = row['id']?.toString() ?? '';
    final clinicId = row['clinic_id']?.toString();
    final donationId = row['donation_id']?.toString();
    final activity = DonationActivity(
      id: id,
      action: row['action']?.toString() ?? '',
      donationId: donationId,
      reference: donationId == null ? null : references[donationId],
      clinicId: clinicId,
      clinicName: clinicId == null ? '' : (clinicNames[clinicId] ?? ''),
      amount: double.tryParse(row['amount']?.toString() ?? ''),
      actor: donationActorLabel(row['from_entity']?.toString()),
      createdAt: row['created_at'] == null
          ? null
          : DateTime.tryParse(row['created_at'].toString())?.toLocal(),
    );
    if (id.isEmpty) {
      withoutId.add(activity);
    } else {
      byId[id] = activity;
    }
  }

  final list = [...byId.values, ...withoutId];
  list.sort((a, b) {
    final x = a.createdAt, y = b.createdAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return list;
}
