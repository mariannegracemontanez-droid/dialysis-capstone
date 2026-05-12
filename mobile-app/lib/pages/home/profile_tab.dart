import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/auth/auth_service.dart';
import '../notifications/notification_page.dart';
import 'edit_profile_page.dart';
import 'medical_info_page.dart';
import 'privacy_security_page.dart';

class ProfileTab extends StatefulWidget {
  final UserModel? user;

  const ProfileTab({super.key, this.user});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late UserModel? _currentUser;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  Future<void> _refreshUser() async {
    final refreshed = await _authService.getCurrentUser();
    if (mounted && refreshed != null) {
      setState(() {
        _currentUser = refreshed;
      });
    }
  }

  void _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await AuthService().signOut();
      if (!mounted) return;
      navigator.pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                decoration: BoxDecoration(
                  color: const Color(0xFF225E72),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    const Text(
                      'My Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 22),

                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 46,
                        color: Color(0xFF225E72),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      _currentUser?.fullName ?? 'Patient Name',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _currentUser?.email ?? 'No email',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFD9EDF3),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _buildSectionCard(
                title: 'Contact Information',
                child: Column(
                  children: [
                    _buildInfoRow(
                      Icons.person_outline,
                      'Full Name',
                      _currentUser?.fullName ?? 'Not set',
                    ),
                    _buildInfoRow(
                      Icons.email_outlined,
                      'Email',
                      _currentUser?.email ?? 'Not set',
                    ),
                    _buildInfoRow(
                      Icons.phone_outlined,
                      'Phone',
                      _currentUser?.phone ?? 'Not set',
                    ),
                    _buildInfoRow(
                      Icons.location_on_outlined,
                      'Location',
                      _currentUser?.location ?? 'No location set',
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          final updated = await Navigator.of(context)
                              .push<bool>(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      EditProfilePage(user: _currentUser),
                                ),
                              );

                          if (updated == true) {
                            await _refreshUser();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xFF225E72),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'EDIT INFORMATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              _buildSectionCard(
                title: 'Medical Information',
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildStatCard(
                          'Blood Type',
                          _currentUser?.bloodType ?? 'Not set',
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Weight',
                          _currentUser?.weight != null
                              ? '${_currentUser!.weight} kg'
                              : 'Not set',
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        _buildStatCard(
                          'Height',
                          _currentUser?.height != null
                              ? '${_currentUser!.height} cm'
                              : 'Not set',
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Last Dialysis',
                          _currentUser?.lastDialysisDate != null
                              ? '${_currentUser!.lastDialysisDate!.month}/${_currentUser!.lastDialysisDate!.day}/${_currentUser!.lastDialysisDate!.year}'
                              : 'Not set',
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  MedicalInfoPage(user: _currentUser),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xFF225E72),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'EDIT MEDICAL INFO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              _buildSectionCard(
                title: 'Quick Actions',
                child: Column(
                  children: [
                    _buildLinkTile(
                      context,
                      'Medical Records',
                      Icons.folder_open_outlined,
                      () {},
                    ),
                    _buildLinkTile(
                      context,
                      'Notifications',
                      Icons.notifications_outlined,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const NotificationPage(),
                          ),
                        );
                      },
                    ),
                    _buildLinkTile(
                      context,
                      'Privacy & Security',
                      Icons.privacy_tip_outlined,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const PrivacySecurityPage(),
                          ),
                        );
                      },
                    ),
                    _buildLinkTile(
                      context,
                      'Help & Support',
                      Icons.help_outline,
                      () {},
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _logout(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE15252)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'LOGOUT',
                    style: TextStyle(
                      color: Color(0xFFE15252),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF173B4F),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EDF2)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF225E72), size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF7A8A94),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF173B4F),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFD),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3EDF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7A8A94),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF173B4F),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkTile(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EDF2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF225E72), size: 21),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF173B4F),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFF7A8A94),
        ),
        onTap: onTap,
      ),
    );
  }
}
