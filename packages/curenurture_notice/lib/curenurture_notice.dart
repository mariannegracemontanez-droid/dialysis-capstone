/// The notice (message) system shared by the CureNurture Admin panel and
/// the Super Admin portal.
///
/// See [AppNotice] for how a notice is layered above an open modal, and
/// [NoticeTheme] for the handful of tokens a portal supplies.
library;

export 'src/app_notice.dart' show AppNotice, NoticeType;
export 'src/notice_theme.dart' show NoticeTheme;
