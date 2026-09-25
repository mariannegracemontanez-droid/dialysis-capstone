# curenurture_notice

The single notice/message system for the CureNurture web portals.

Both the Center Admin panel (`admin_panel`) and the Super Admin portal
(`super_admin_app`) depend on this package by path, so a message raised in
either one behaves and looks identical.

## Why a package and not a copied file

The two portals are separate Flutter applications. Before this package the
notice widget lived only in `admin_panel/lib/widgets/admin_notice.dart`, and
Super Admin still used `SnackBar`s -- which the `ScaffoldMessenger` paints
*inside* the page, so a message raised from inside a dialog landed underneath
it, unread. Copying the widget across would have left two implementations to
keep in step; this package leaves one.

## What each app supplies

Only colours and radii, through [NoticeTheme]. Each portal keeps its own
`AppTheme`, builds one `NoticeTheme` from it, and exposes a thin, named
facade over [AppNotice]:

| app               | facade                      | theme source           |
|-------------------|-----------------------------|------------------------|
| `admin_panel`     | `AdminNotice`               | `admin_panel` AppTheme |
| `super_admin_app` | `SuperAdminNotice`          | `super_admin_app` AppTheme |

No behaviour lives in either facade -- every timer, barrier, animation and
button is here.
