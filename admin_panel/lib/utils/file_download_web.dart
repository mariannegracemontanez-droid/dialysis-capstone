import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Saves [content] to the admin's machine as [fileName].
///
/// Everything here happens in the browser: the text becomes an in-memory
/// blob, an off-screen anchor points at it, and clicking that anchor is
/// what opens the browser's own save dialog. Nothing is uploaded, so a
/// patient's history never leaves the machine it was generated on.
///
/// The object URL is revoked straight after the click -- it is only
/// needed for the moment the download starts, and leaving it alive would
/// pin the whole file in memory for the life of the tab.
void downloadTextFile({
  required String fileName,
  required String content,
  String mimeType = 'text/plain',
}) {
  // A BOM, so Excel opens a UTF-8 CSV with accented names intact instead
  // of guessing the local codepage.
  final bytes = utf8.encode('\uFEFF$content');

  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
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
