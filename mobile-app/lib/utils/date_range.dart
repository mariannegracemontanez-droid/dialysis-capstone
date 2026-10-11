/// Whether [dateValue] (a `YYYY-MM-DD` date or a timestamp) falls within the
/// most recent [days] calendar days, today included. Records without a
/// readable date can't be placed in a range, so they are excluded.
bool isWithinLastDays(String? dateValue, int days, {DateTime? now}) {
  final parsed = DateTime.tryParse(dateValue ?? '');
  if (parsed == null) return false;

  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  final date = DateTime(local.year, local.month, local.day);
  final reference = now ?? DateTime.now();
  final cutoff = DateTime(
    reference.year,
    reference.month,
    reference.day,
  ).subtract(Duration(days: days - 1));
  return !date.isBefore(cutoff);
}
