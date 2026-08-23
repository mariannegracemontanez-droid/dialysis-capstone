class Validators {
  static String? validatePhone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Phone number is required.';
    if (!RegExp(r'^\d{11}$').hasMatch(trimmed)) {
      return 'Phone number must be exactly 11 digits.';
    }
    return null;
  }

  static String? validateEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Email address is required.';
    if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(trimmed)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  static String? validateName(String value, {String fieldLabel = 'Name'}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '$fieldLabel is required.';
    if (!RegExp(r"^[a-zA-Z\s.'-]+$").hasMatch(trimmed)) {
      return '$fieldLabel must only contain letters.';
    }
    return null;
  }

  static String? validateAddress(String value, {String fieldLabel = 'Address'}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '$fieldLabel is required.';
    return null;
  }

  static String? validateRequired(String value, String fieldLabel) {
    if (value.trim().isEmpty) return '$fieldLabel is required.';
    return null;
  }

  static String? validateNumeric(
    String value,
    String fieldLabel, {
    double? min,
    double? max,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '$fieldLabel is required.';
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return '$fieldLabel must be a valid number.';
    if (min != null && parsed < min) {
      return '$fieldLabel must be at least $min.';
    }
    if (max != null && parsed > max) {
      return '$fieldLabel must be at most $max.';
    }
    return null;
  }
}
