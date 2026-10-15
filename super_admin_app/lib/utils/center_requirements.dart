/// Splits a center's stored `requirements` value back into individual
/// requirement items.
///
/// Data-preservation note: `clinic.requirements` (CenterModel) is always a
/// Dart String by the time it reaches here, but what's *behind* that string
/// differs by how the row was written. When Supabase returns a real
/// array/jsonb column, CenterModel's `.toString()` renders it in Dart's own
/// bracketed "[A, B, C]" form -- there, the commas are guaranteed to be
/// Dart's own List.toString() separators (added by DashboardService's
/// existing write path, not typed by a user), so splitting on them is safe.
/// A row with no brackets, however, has no such guarantee: it may be a
/// legacy value from before the checkbox UI existed, when the field was a
/// plain free-text box with no delimiter contract at all -- a stored value
/// like "ID, Referral" could just as easily be one single item the admin
/// typed as it could be two. mobile-app's clinic_detail_page.dart
/// (_requirementItems) makes the same distinction for the same reason: a
/// non-List value there is treated as one atomic requirement, never split
/// on comma/semicolon. So this only splits an unbracketed value on newline
/// -- the delimiter the centre form intentionally writes. Nothing is ever
/// discarded either way.
///
/// Moved here unchanged from center_page.dart so the centre detail view can
/// list requirements exactly as the edit form reads them.
List<String> parseStoredRequirements(String raw) {
  final trimmed = raw.trim();

  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    final inner = trimmed.substring(1, trimmed.length - 1);
    return inner
        .split(RegExp(r'[,;\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  return trimmed
      .split('\n')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
