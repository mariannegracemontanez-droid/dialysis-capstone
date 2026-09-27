import 'package:flutter/material.dart';

import '../pages/notifications/notification_page.dart';

/// The header bell that opens the Notifications page.
///
/// Shared by the approved-patient Home header and the pending-account
/// Home header so both open the same page the same way.
class NotificationButton extends StatelessWidget {
  const NotificationButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const NotificationPage()),
          );
        },
        icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
      ),
    );
  }
}
