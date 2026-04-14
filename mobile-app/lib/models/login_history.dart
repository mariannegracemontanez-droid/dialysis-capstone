class LoginHistory {
  final String id;
  final String userId;
  final DateTime loginTime;
  final String deviceBrand;
  final String deviceModel;
  final String deviceType;
  final String? ipAddress;

  LoginHistory({
    required this.id,
    required this.userId,
    required this.loginTime,
    required this.deviceBrand,
    required this.deviceModel,
    required this.deviceType,
    this.ipAddress,
  });

  factory LoginHistory.fromJson(Map<String, dynamic> json) {
    return LoginHistory(
      id: json['id'],
      userId: json['user_id'],
      loginTime: DateTime.parse(json['login_time']),
      deviceBrand: json['device_brand'] ?? 'Unknown',
      deviceModel: json['device_model'] ?? 'Unknown',
      deviceType: json['device_type'] ?? 'Unknown',
      ipAddress: json['ip_address'],
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'login_time': loginTime.toIso8601String(),
    'device_brand': deviceBrand,
    'device_model': deviceModel,
    'device_type': deviceType,
    'ip_address': ipAddress,
  };
}
