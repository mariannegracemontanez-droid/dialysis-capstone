class NotificationItem {
  final String id;
  final String message;
  final DateTime timestamp;
  final String source;

  NotificationItem({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.source,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at']?.toString();
    return NotificationItem(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      message: json['message']?.toString() ?? 'Updated schedule available.',
      source: json['source']?.toString() ?? 'System',
      timestamp: createdAt != null
          ? DateTime.tryParse(createdAt) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
