/// Hands the Super Admin a generated file to save.
///
/// The Super Admin portal is run as a Flutter **web** app (see `web/`), where
/// "download" means handing the browser a blob and clicking a link at it.
/// That code cannot be compiled for the native targets the project also
/// carries, so the real implementation lives behind a conditional import and
/// the other platforms get a stub that says so out loud rather than silently
/// producing nothing.
///
/// Same approach as admin_panel's `utils/file_download.dart`, but for binary
/// files (PDF / .xlsx) instead of text. Callers only ever see [downloadBytes].
library;

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
