import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final supabase = Supabase.instance.client;

  List<dynamic> notifications = [];
  bool isLoading = true;

  late final RealtimeChannel _notificationChannel;

  @override
  void initState() {
    super.initState();

    fetchNotifications();
    listenToNotifications();
  }

  Future<void> fetchNotifications() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final response = await supabase
          .from('notifications')
          .select()
          .eq('recipient_id', userId)
          .order('created_at', ascending: false);

      setState(() {
        notifications = response;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Fetch notification error: $e');

      setState(() {
        isLoading = false;
      });
    }
  }

  void listenToNotifications() {
    final userId = supabase.auth.currentUser!.id;

    _notificationChannel = supabase
        .channel('user-notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (payload) async {
            final newNotification = payload.newRecord;

            setState(() {
              notifications.insert(0, newNotification);
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    newNotification['title'] ?? 'New notification received',
                  ),
                ),
              );
            }
          },
        )
        .subscribe();
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);

    setState(() {
      final index = notifications.indexWhere((n) => n['id'] == notificationId);

      if (index != -1) {
        notifications[index]['is_read'] = true;
      }
    });
  }

  @override
  void dispose() {
    supabase.removeChannel(_notificationChannel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF2C5F7D),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : notifications.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        final notification = notifications[index];

                        final isRead = notification['is_read'] ?? false;

                        return GestureDetector(
                          onTap: () async {
                            if (!isRead) {
                              await markNotificationAsRead(notification['id']);
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isRead
                                  ? Colors.white
                                  : const Color(0xFFE8F3FA),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF2C5F7D,
                                    ).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active_rounded,
                                    color: Color(0xFF2C5F7D),
                                  ),
                                ),

                                const SizedBox(width: 14),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notification['title'] ?? 'Notification',
                                        style: TextStyle(
                                          fontWeight: isRead
                                              ? FontWeight.w500
                                              : FontWeight.bold,
                                          fontSize: 15,
                                          color: Colors.black87,
                                        ),
                                      ),

                                      const SizedBox(height: 6),

                                      Text(
                                        notification['message'] ?? '',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                        ),
                                      ),

                                      const SizedBox(height: 10),

                                      Text(
                                        notification['created_at'] != null
                                            ? notification['created_at']
                                                  .toString()
                                            : '',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (!isRead)
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Notifications Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your notifications will appear here once you have updates about your appointments and donations.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
