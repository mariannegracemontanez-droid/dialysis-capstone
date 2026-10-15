/// Whether an edit form's [current] values differ from the [original] values
/// it was opened with.
///
/// Compared by value, not by whether a field was touched: changing a field
/// and then restoring its original value is "no changes" again. Strings are
/// compared trimmed (surrounding whitespace is never saved); every other
/// value with `==`. Keys present in only one map count as a change.
bool hasFormChanges(
  Map<String, Object?> original,
  Map<String, Object?> current,
) {
  if (original.length != current.length) return true;

  for (final entry in original.entries) {
    if (!current.containsKey(entry.key)) return true;
    if (_normalize(entry.value) != _normalize(current[entry.key])) return true;
  }
  return false;
}

Object? _normalize(Object? value) => value is String ? value.trim() : value;
