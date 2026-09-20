/// Hands the admin a generated file to save.
///
/// The Admin panel ships as a Flutter **web** app (see `web/`), where
/// "download" means handing the browser a blob and clicking a link at it.
/// That code cannot be compiled for the native targets the repo also
/// carries, so the real implementation lives behind a conditional import
/// and the other platforms get a stub that says so out loud rather than
/// silently producing nothing.
///
/// Callers only ever see [downloadTextFile].
library;

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
