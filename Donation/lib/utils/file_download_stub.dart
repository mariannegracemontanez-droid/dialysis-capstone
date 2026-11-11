import 'dart:typed_data';

/// Non-web builds (and tests) have no browser download.
void downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  throw UnsupportedError('Downloading a file is only available in the browser.');
}
