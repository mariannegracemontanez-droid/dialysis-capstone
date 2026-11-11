import 'package:donation_app/services/auth_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidEmail', () {
    test('accepts normal addresses (including synthetic test domains)', () {
      for (final good in [
        'donor@example.com',
        'first.last+tag@sub.example.org',
        'synthetic-donor@example.invalid',
        '  donor@example.com  ',
      ]) {
        expect(isValidEmail(good), isTrue, reason: good);
      }
    });

    test('rejects malformed addresses', () {
      for (final bad in [
        '', ' ', 'donor', 'donor@', '@example.com', 'donor@example', 'donor@.com',
        'donor@example..com', 'do nor@example.com', 'donor@exam ple.com',
        'donor@@example.com', 'donor.@example..org', '${'a' * 250}@example.com',
      ]) {
        expect(isValidEmail(bad), isFalse, reason: bad);
      }
    });
  });

  group('friendlyAuthError', () {
    test('maps known Auth errors to clear messages', () {
      expect(friendlyAuthError('Invalid login credentials'),
          'Incorrect email or password. Please try again.');
      expect(friendlyAuthError('Email not confirmed'),
          'Please confirm your email address before logging in.');
      expect(friendlyAuthError('User already registered'),
          'This email is already registered. Please log in instead.');
      expect(friendlyAuthError('For security purposes, you can only request this after 30 seconds.'),
          'Too many attempts. Please wait a moment and try again.');
      expect(friendlyAuthError('Password should be at least 6 characters.'),
          'Please choose a stronger password (at least 6 characters).');
      expect(friendlyAuthError('Unable to validate email address: invalid format'),
          'Please enter a valid email address.');
      expect(friendlyAuthError('ClientException: Failed to fetch'),
          'We could not reach the server. Please check your connection and try again.');
    });

    test('never shows raw server text for unknown errors', () {
      const raw = 'relation "auth.users" violates constraint xyz_internal';
      final msg = friendlyAuthError(raw);
      expect(msg, 'Something went wrong. Please try again.');
      expect(msg, isNot(contains('relation')));
    });
  });
}
