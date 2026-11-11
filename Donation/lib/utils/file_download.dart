/// Saves a generated file on the donor's machine (web only).
///
/// Same approach as the Super Admin portal's `utils/file_download.dart`: the
/// browser builds the file from memory and starts its own download, so
/// nothing is uploaded anywhere.
library;

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
