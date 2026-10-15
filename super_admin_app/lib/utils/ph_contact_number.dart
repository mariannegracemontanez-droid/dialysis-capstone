// Philippine centre contact numbers: a fixed `+63` prefix followed by the
// 10-digit mobile number without its trunk `0` (`+63 917 123 4567`).
//
// The form keeps only the 10 local digits in its text field; the prefix is
// shown as fixed text and added back on save, so the stored value is always
// `+63` followed by 10 digits.

import 'package:flutter/services.dart';

const String phCountryCode = '+63';
const int phLocalDigitCount = 10;

/// Validation message for the digits typed after `+63`, or null when valid.
String? validatePhLocalDigits(String value) {
  final digits = value.trim();

  if (digits.isEmpty) return 'Enter the contact number.';
  if (!RegExp(r'^\d+$').hasMatch(digits)) {
    return 'Use digits only.';
  }
  if (digits.startsWith('0')) {
    return 'Leave out the leading 0 -- +63 already replaces it.';
  }
  if (digits.length != phLocalDigitCount) {
    return 'Enter exactly $phLocalDigitCount digits after +63 '
        '(e.g. 9171234567).';
  }
  return null;
}

/// The value written to `clinics.contact_number` for valid [localDigits].
String composePhContactNumber(String localDigits) =>
    '$phCountryCode${localDigits.trim()}';

/// The 10 local digits held in a stored contact number, or null when the
/// stored value is not a recognisable Philippine mobile number (blank,
/// `N/A`, a landline, too short or too long). Accepted stored forms:
/// `+639171234567`, `639171234567`, `09171234567`, `9171234567`, with any
/// spaces, dashes, dots or parentheses.
String? phLocalDigitsFromStored(String? stored) {
  if (stored == null) return null;
  final trimmed = stored.trim();
  if (trimmed.isEmpty) return null;
  if (!RegExp(r'^[0-9+\-(). ]+$').hasMatch(trimmed)) return null;

  final digits = trimmed.replaceAll(RegExp(r'\D'), '');

  String? local;
  if (digits.length == 12 && digits.startsWith('63')) {
    local = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    local = digits.substring(1);
  } else if (digits.length == phLocalDigitCount) {
    local = digits;
  }

  return local != null && validatePhLocalDigits(local) == null ? local : null;
}

/// Readable form of a stored contact number: `+63 917 123 4567` when it is
/// a recognisable mobile number, otherwise the stored text as-is.
String formatPhContactForDisplay(String? stored) {
  final local = phLocalDigitsFromStored(stored);
  if (local == null) return stored?.trim() ?? '';

  return '$phCountryCode ${local.substring(0, 3)} '
      '${local.substring(3, 6)} ${local.substring(6)}';
}

/// Input formatter for the digits after `+63`: keeps digits only, drops a
/// leading `0`, turns a pasted full number (`+63...` / `09...`) into its
/// local digits, and caps the length at [phLocalDigitCount].
class PhLocalDigitsInputFormatter extends TextInputFormatter {
  const PhLocalDigitsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > phLocalDigitCount && digits.startsWith('63')) {
      digits = digits.substring(2);
    }
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > phLocalDigitCount) {
      digits = digits.substring(0, phLocalDigitCount);
    }

    if (digits == newValue.text) return newValue;

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
