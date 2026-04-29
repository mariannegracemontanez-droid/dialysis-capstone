import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/login_history.dart';
import '../../services/login_history_service.dart';
import '../../config/supabase_config.dart';

class LoginHistoryPage extends StatefulWidget {
  const LoginHistoryPage({super.key});

  @override
  State<LoginHistoryPage> createState() => _LoginHistoryPageState();
}

class _LoginHistoryPageState extends State<LoginHistoryPage> {
  late Future<List<LoginHistory>> _loginHistoryFuture;
  final LoginHistoryService _loginHistoryService = LoginHistoryService();
  String _currentDeviceName = 'This device';

  @override
  void initState() {
    super.initState();
    _loadCurrentDeviceInfo();
    _loadLoginHistory();
  }

  Future<void> _loadCurrentDeviceInfo() async {
    try {
      final currentDevice = await _loginHistoryService
          .getCurrentDeviceDisplayName();
      if (mounted) {
        setState(() {
          _currentDeviceName = currentDevice;
        });
      }
    } catch (_) {
      // keep default current device label
    }
  }

  void _loadLoginHistory() {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId != null) {
      _loginHistoryFuture = _loginHistoryService.getLoginHistory(userId);
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('MMM dd, yyyy - hh:mm a').format(dateTime);
  }

  String _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'android':
        return '📱';
      case 'ios':
        return '🍎';
      case 'windows':
        return '🪟';
      case 'macos':
        return '🖥️';
      case 'linux':
        return '🐧';
      default:
        return '💻';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C5F7D),
        title: const Text('Login History'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<LoginHistory>>(
          future: _loginHistoryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load login history',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _loadLoginHistory();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final loginHistory = snapshot.data ?? [];
            final hasSuspiciousActivity = loginHistory.any(
              (login) => login.deviceModel != _currentDeviceName,
            );

            if (loginHistory.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No login history yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: hasSuspiciousActivity
                        ? const Color(0xFFFAE7E6)
                        : const Color(0xFFEAF6F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasSuspiciousActivity
                          ? const Color(0xFFE16A5E)
                          : const Color(0xFF2C5F7D),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hasSuspiciousActivity
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle,
                            color: hasSuspiciousActivity
                                ? const Color(0xFFE16A5E)
                                : const Color(0xFF2C5F7D),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasSuspiciousActivity
                                ? 'Suspicious Activity Detected'
                                : 'No suspicious login activity',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: hasSuspiciousActivity
                                  ? const Color(0xFFE16A5E)
                                  : const Color(0xFF2C5F7D),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hasSuspiciousActivity
                            ? 'Choose a strong password to keep your account secure. Don’t share your password with anyone.'
                            : 'Your recent sign-ins look safe. Review recent activity anytime to stay protected.',
                        style: TextStyle(
                          fontSize: 13,
                          color: hasSuspiciousActivity
                              ? const Color(0xFF7D2B26)
                              : const Color(0xFF2C5F7D),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/change-password');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasSuspiciousActivity
                                ? const Color(0xFFE16A5E)
                                : const Color(0xFF2C5F7D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Change Password'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4FAFE),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.smartphone,
                        color: Color(0xFF2C5F7D),
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Session',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _currentDeviceName,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Log out all devices feature is coming soon.',
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF2C5F7D)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Log out all Devices'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Stay secure by changing your password if needed.',
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF2C5F7D)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Stay Secure'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Recent Activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                ...loginHistory.map((login) {
                  final isToday =
                      DateTime.now().difference(login.loginTime).inDays == 0;
                  final isCurrentDevice =
                      login.deviceModel ==
                      (SupabaseConfig
                              .client
                              .auth
                              .currentUser
                              ?.userMetadata?['device'] ??
                          '');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getDeviceIcon(login.deviceType),
                              style: const TextStyle(fontSize: 32),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          login.deviceBrand,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      if (isCurrentDevice)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: Colors.green,
                                            ),
                                          ),
                                          child: const Text(
                                            'Current',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${login.deviceModel} • ${login.deviceType}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 14,
                                        color: Colors.grey[500],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDateTime(login.loginTime),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isToday)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Text(
                                          'Today',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
