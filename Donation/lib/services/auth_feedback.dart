/// Shared, donor-safe wording for the login and sign-up pages.
library;

final RegExp _emailPattern = RegExp(
  r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
  r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
);

/// A practical email-format check (local part, @, a domain with at least one
/// dot). The server still decides whether the address is accepted.
bool isValidEmail(String email) {
  final value = email.trim();
  if (value.isEmpty || value.length > 254 || value.contains('..')) return false;
  return _emailPattern.hasMatch(value);
}

/// Turns an Auth error message into a clear message the donor can act on.
/// Raw server text is never shown.
String friendlyAuthError(String message) {
  final m = message.toLowerCase();
  if (m.contains('invalid login credentials') || m.contains('invalid_credentials')) {
    return 'Incorrect email or password. Please try again.';
  }
  if (m.contains('email not confirmed')) {
    return 'Please confirm your email address before logging in.';
  }
  if (m.contains('already registered') || m.contains('user already exists') ||
      m.contains('user exists') || m.contains('duplicate')) {
    return 'This email is already registered. Please log in instead.';
  }
  if (m.contains('rate limit') || m.contains('too many') || m.contains('for security purposes')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (m.contains('password should be') || m.contains('weak password') || m.contains('weak_password')) {
    return 'Please choose a stronger password (at least 6 characters).';
  }
  if (m.contains('invalid email') || m.contains('unable to validate email') ||
      m.contains('email address') && m.contains('invalid')) {
    return 'Please enter a valid email address.';
  }
  if (m.contains('failed to fetch') || m.contains('socket') || m.contains('connection') ||
      m.contains('network')) {
    return 'We could not reach the server. Please check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}
