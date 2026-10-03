import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [bytes] to the Super Admin's machine as [fileName].
///
/// Everything here happens in the browser: the bytes become an in-memory
/// blob, an off-screen anchor points at it, and clicking that anchor is what
/// starts the browser's own download. Nothing is uploaded, so donor details
/// never leave the machine the report was generated on.
///
/// The object URL is revoked straight after the click -- it is only needed
/// for the moment the download starts, and leaving it alive would pin the
/// whole file in memory for the life of the tab.
void downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );

  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  web.URL.revokeObjectURL(url);
}
