// Input rules for the Shifts and Available Slots fields of the centre form.
// Both are stored as whole numbers (`clinics.shifts`, `clinics.slots_available`);
// a manually entered Available Slots value is saved exactly as entered.

/// A non-negative whole number typed into a form field, or null when the
/// text is blank, not a number, fractional or negative.
int? parseWholeNumberInput(String text) {
  final parsed = double.tryParse(text.trim());
  if (parsed == null || parsed < 0 || parsed != parsed.truncateToDouble()) {
    return null;
  }
  return parsed.round();
}

/// Validation message for Shifts (a whole number, at least 1 per day), or
/// null when valid.
String? validateShiftsInput(String text) {
  final value = text.trim();
  if (value.isEmpty) return 'This field is required';
  final shifts = parseWholeNumberInput(value);
  if (shifts == null) return 'Please enter a whole number';
  if (shifts < 1) return 'At least 1 shift is required';
  return null;
}

/// The Available Slots value suggested for [machinesText] × [shiftsText],
/// or null when either is not a valid whole number.
int? suggestedAvailableSlots(String machinesText, String shiftsText) {
  final machines = parseWholeNumberInput(machinesText);
  final shifts = parseWholeNumberInput(shiftsText);
  if (machines == null || shifts == null) return null;
  return machines * shifts;
}
