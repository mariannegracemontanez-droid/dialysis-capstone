import 'dart:typed_data';

/// Non-web fallback for [downloadBytes].
///
/// Throwing is deliberate: a download that quietly does nothing looks
/// identical to a download that failed, and the caller already reports a
/// thrown message through SuperAdminNotice.error.
void downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  throw UnsupportedError(
    'Downloading a file is only available in the browser version of the '
    'Super Admin portal.',
  );
}
