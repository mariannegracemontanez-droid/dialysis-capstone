import 'package:supabase_flutter/supabase_flutter.dart';

/// Readable text for an error shown on screen.
///
/// Services wrap errors more than once ("Exception: Failed to create
/// patient record: Exception: …") and Supabase errors print their full
/// debug form ("AuthApiException(message: …, statusCode: …)"). This keeps
/// the context and the message and drops the rest. Logs should keep using
/// the raw error.
String friendlyError(Object error) {
  if (error is AuthException) return error.message;
  if (error is PostgrestException) return error.message;

  final text = error
      .toString()
      .replaceAllMapped(
        RegExp(r'\w*Exception\(message: ([^,)]*)[^)]*\)'),
        (match) => match.group(1)!.trim(),
      )
      .replaceAll(RegExp(r'\b\w*Exception: '), '')
      .trim();
  return text.isEmpty ? 'Something went wrong. Please try again.' : text;
}
