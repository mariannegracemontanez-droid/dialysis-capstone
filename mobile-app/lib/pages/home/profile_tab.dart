import 'package:flutter/material.dart';
import '../profile/help_support_page.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  String? _profileImageUrl;

  final ImagePicker _picker = ImagePicker();
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _profileImageUrl = widget.user?.profileImageUrl;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPatientProfileImage();
    });
  }

  Future<void> _refreshUser() async {
    final refreshed = await _authService.getCurrentUser();
    if (mounted && refreshed != null) {
      setState(() {
        _currentUser = refreshed;
      });
    }
  }

  Future<void> _loadPatientProfileImage() async {
    final user = _currentUser;
    if (user == null) return;

    try {
      final supabase = Supabase.instance.client;

      final data = await supabase
          .from('patients')
          .select('profile_image_url')
          .eq('email', user.email)
          .eq('status', 'active')
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _profileImageUrl = data?['profile_image_url'];
      });
    } catch (e) {
      debugPrint('Failed to load profile image: $e');
    }
  }

  void _openProfilePhotoViewer() {
    final imageUrl = _profileImageUrl;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  color: Colors.white,
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            height: 260,
                            child: Center(child: Icon(Icons.person, size: 70)),
                          ),
                        )
                      : const SizedBox(
                          height: 260,
                          child: Center(
                            child: Icon(
                              Icons.person_rounded,
                              size: 90,
                              color: Color(0xFF225E72),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showProfileImageOptions();
                      },
                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                      label: const Text('Change'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showProfileImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take a photo'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickCropCompressAndUpload(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickCropCompressAndUpload(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCropCompressAndUpload(ImageSource source) async {
    try {
      final pickedImage = await _picker.pickImage(source: source);
      if (pickedImage == null) return;

      final croppedImage = await ImageCropper().cropImage(
        sourcePath: pickedImage.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Photo',
            toolbarColor: const Color(0xFF225E72),
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop Profile Photo',
            aspectRatioLockEnabled: true,
          ),
        ],
      );

      if (croppedImage == null) return;

      final compressedFile = await _compressImage(File(croppedImage.path));
      final confirm = await _showImagePreview(compressedFile);

      if (confirm == true) {
        await _uploadProfileImage(compressedFile);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image process failed: $e')));
    }
  }

  Future<File> _compressImage(File file) async {
    final targetPath =
        '${file.parent.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final compressed = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 65,
      minWidth: 500,
      minHeight: 500,
      format: CompressFormat.jpeg,
    );

    return compressed != null ? File(compressed.path) : file;
  }

  Future<bool?> _showImagePreview(File imageFile) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Use this photo?'),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              imageFile,
              height: 260,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Choose Again'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use Photo'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _uploadProfileImage(File imageFile) async {
    final user = _currentUser;
    if (user == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final supabase = Supabase.instance.client;

      final fileName =
          '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = 'patients/$fileName';

      await supabase.storage
          .from('patient_profiles')
          .upload(
            filePath,
            imageFile,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final imageUrl = supabase.storage
          .from('patient_profiles')
          .getPublicUrl(filePath);

      await supabase
          .from('patients')
          .update({'profile_image_url': imageUrl})
          .eq('email', user.email)
          .eq('status', 'active');

      if (!mounted) return;

      setState(() {
        _profileImageUrl = imageUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
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
                    GestureDetector(
                      onTap: _isUploadingImage ? null : _openProfilePhotoViewer,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _isUploadingImage
                                ? Shimmer.fromColors(
                                    baseColor: const Color(0xFFE8F1F5),
                                    highlightColor: Colors.white,
                                    child: Container(color: Colors.white),
                                  )
                                : (_profileImageUrl != null &&
                                      _profileImageUrl!.isNotEmpty)
                                ? Image.network(
                                    _profileImageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        _defaultProfileIcon(),
                                  )
                                : _defaultProfileIcon(),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 17,
                                color: Color(0xFF225E72),
                              ),
                            ),
                          ),
                        ],
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
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const HelpSupportPage(),
                        ),
                      ),
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

  Widget _defaultProfileIcon() {
    return Container(
      color: Colors.white,
      child: const Icon(
        Icons.person_rounded,
        size: 46,
        color: Color(0xFF225E72),
      ),
    );
  }
}
