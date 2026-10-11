import 'package:CureNurture/utils/error_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('drops nested "Exception:" prefixes but keeps the context', () {
    expect(
      friendlyError(
        Exception(
          'Failed to create patient record: '
          'Exception: You already have a pending application for this clinic.',
        ),
      ),
      'Failed to create patient record: You already have a pending '
      'application for this clinic.',
    );
  });

  test('reduces a printed Supabase exception to its message', () {
    expect(
      friendlyError(
        Exception(
          'Sign up error: AuthApiException(message: User already registered, '
          'statusCode: 422, code: user_already_exists)',
        ),
      ),
      'Sign up error: User already registered',
    );
  });

  test('uses the message of Supabase error objects', () {
    expect(
      friendlyError(const AuthException('Invalid login credentials')),
      'Invalid login credentials',
    );
    expect(
      friendlyError(const PostgrestException(message: 'permission denied')),
      'permission denied',
    );
  });

  test('falls back to a generic message when nothing is left', () {
    expect(
      friendlyError(Exception('')),
      'Something went wrong. Please try again.',
    );
  });
}
