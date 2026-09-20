/// Non-web fallback for [downloadTextFile].
///
/// Throwing is deliberate: a download that quietly does nothing looks
/// identical to a download that failed, and the caller already reports a
/// thrown message through AdminNotice.error.
void downloadTextFile({
  required String fileName,
  required String content,
  String mimeType = 'text/plain',
}) {
  throw UnsupportedError(
    'Downloading a file is only available in the browser version of the '
    'Admin panel.',
  );
}
