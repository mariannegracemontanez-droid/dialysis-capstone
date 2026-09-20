import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Names the page in the browser tab (and in the OS task switcher).
///
/// The panel navigates with plain `Navigator.push`, not named routes, so
/// there is no route table to hang titles off. Flutter's own `Title`
/// widget is the convention for that case: whichever one is currently
/// built wins, which is exactly the top-most page. Wrapping each page's
/// `Scaffold` in [AdminTitle] therefore keeps the title correct as the
/// admin moves between pages, and on the way back too.
///
/// Every title reads `CureNurture | <page>`; [page] is just the second
/// half, so the product name is written in one place.
class AdminTitle extends StatelessWidget {
  /// The page's own name, e.g. `Admin Dashboard`.
  final String page;

  final Widget child;

  const AdminTitle({super.key, required this.page, required this.child});

  /// The full string shown in the tab.
  static String titleFor(String page) => 'CureNurture | $page';

  @override
  Widget build(BuildContext context) {
    return Title(title: titleFor(page), color: AppTheme.blue1, child: child);
  }
}
