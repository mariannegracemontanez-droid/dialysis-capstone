/// One row of `donation_purchase_logs` -- the purchases a centre's Admin
/// Panel records against the donations it received. The Admin Panel writes
/// these rows (`clinic_name`, `item_name`, `amount`, `purchase_date`); Super
/// Admin only reads them.
///
/// The table links a log to its centre by `clinic_name` (text), not by a
/// clinic id -- that is how the Admin Panel stores it.
class PurchaseLog {
  final String id;
  final String clinicName;
  final String itemName;
  final double amount;
  final DateTime? purchaseDate;
  final DateTime? createdAt;

  const PurchaseLog({
    required this.id,
    required this.clinicName,
    required this.itemName,
    required this.amount,
    required this.purchaseDate,
    required this.createdAt,
  });

  /// Best date for display and ordering: the purchase date, else the time
  /// the row was created.
  DateTime? get date => purchaseDate ?? createdAt;

  factory PurchaseLog.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

    return PurchaseLog(
      id: json['id']?.toString() ?? '',
      clinicName: json['clinic_name']?.toString().trim() ?? '',
      itemName: json['item_name']?.toString().trim() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      purchaseDate: parseDate(json['purchase_date']),
      createdAt: parseDate(json['created_at']),
    );
  }
}

/// Maps fetched rows to [PurchaseLog]s, newest first, keeping one entry per
/// id. A refresh replaces the whole list with this result, so repeated
/// fetches or realtime events can never duplicate a log, and an updated row
/// always shows its latest saved values. Rows without an id are kept (they
/// cannot collide with anything).
List<PurchaseLog> purchaseLogsFromRows(List<dynamic> rows) {
  final byId = <String, PurchaseLog>{};
  final withoutId = <PurchaseLog>[];

  for (final row in rows) {
    if (row is! Map) continue;
    final log = PurchaseLog.fromJson(Map<String, dynamic>.from(row));
    if (log.id.isEmpty) {
      withoutId.add(log);
    } else {
      byId[log.id] = log;
    }
  }

  final logs = [...byId.values, ...withoutId];
  logs.sort((a, b) {
    final aDate = a.date;
    final bDate = b.date;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  });
  return logs;
}
