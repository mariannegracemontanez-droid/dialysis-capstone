import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/dashboard_page.dart';
import '../config/supabase_config.dart';
import '../theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _message;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const Color primaryColor = AppTheme.blue1;
  static const Color pageBg = AppTheme.canvas;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isSuperAdminRole(dynamic roleValue) {
    if (roleValue == null) return false;
    final roleString = roleValue.toString().toLowerCase().trim();
    return roleString == 'superadmin';
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final res = await SupabaseConfig.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user == null || res.session == null) {
        setState(() {
          _message = 'Incorrect email or password. Please try again.';
        });
        return;
      }

      final profile = await SupabaseConfig.client
          .from('profiles')
          .select('role')
          .eq('id', res.user!.id)
          .maybeSingle();

      final roleFromProfile = profile?['role'];
      final roleFromAppMetadata = res.user!.appMetadata['role'];
      final roleFromUserMetadata = res.user!.userMetadata?['role'];

      final isSuperAdmin =
          _isSuperAdminRole(roleFromProfile) ||
          _isSuperAdminRole(roleFromAppMetadata) ||
          _isSuperAdminRole(roleFromUserMetadata);

      if (!isSuperAdmin) {
        await SupabaseConfig.client.auth.signOut();
        setState(() {
          _message = 'Incorrect email or password. Please try again.';
        });
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    } on AuthException catch (e) {
  setState(() {
    _message = e.message;
  });
} catch (e) {
  setState(() {
    _message = e.toString();
  });
} finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/curenurture_background.jpeg',
              fit: BoxFit.cover,
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Hero(
                          tag: 'curenurture-logo',
                          child: Image.asset(
                            'assets/images/CureNurture_CircleLogo.png',
                            width: 74,
                            height: 74,
                          ),
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          'CureNurture Portal',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.blue3,
                            fontSize: 26,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'Please sign in to continue',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                        const SizedBox(height: 32),

                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(AppTheme.rXl),
                            border: Border.all(color: AppTheme.border),
                            boxShadow: AppTheme.shadowSm,
                          ),
                          child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    _buildInputField(
                                      controller: _emailController,
                                      hintText: 'Email Address',
                                      icon: Icons.alternate_email_rounded,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (value) {
                                        final email = value?.trim() ?? '';

                                        if (email.isEmpty) {
                                          return 'Email is required';
                                        }

                                        if (!email.contains('@')) {
                                          return 'Enter a valid email';
                                        }

                                        return null;
                                      },
                                    ),

                                    const SizedBox(height: 18),

                                    _buildInputField(
                                      controller: _passwordController,
                                      hintText: 'Password',
                                      icon: Icons.lock_outline_rounded,
                                      obscureText: _obscurePassword,
                                      suffixIcon: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: AppTheme.iconMuted,
                                          size: 19,
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'Password is required';
                                        }

                                        return null;
                                      },
                                    ),

                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      child: _message == null
                                          ? const SizedBox.shrink()
                                          : Padding(
                                              key: ValueKey(_message),
                                              padding: const EdgeInsets.only(
                                                top: 16,
                                              ),
                                              child: Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 12,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFFDF2F2,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppTheme.rMd,
                                                      ),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFF3C7C7,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.error_outline,
                                                      color: Color(0xFFB91C1C),
                                                      size: 18,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        _message!,
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFF9F1B1B,
                                                          ),
                                                          fontSize: 12.5,
                                                          height: 1.35,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                    ),

                                    const SizedBox(height: 30),

                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: ElevatedButton(
                                        onPressed: _loading ? null : _signIn,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          disabledBackgroundColor: primaryColor
                                              .withValues(alpha: 0.45),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.rMd,
                                            ),
                                          ),
                                        ),
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          child: _loading
                                              ? const SizedBox(
                                                  key: ValueKey('loading'),
                                                  width: 22,
                                                  height: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.4,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(Colors.white),
                                                  ),
                                                )
                                              : const Text(
                                                  'SIGN IN',
                                                  key: ValueKey('text'),
                                                  style: TextStyle(
                                                    color: AppTheme.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.8,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        const Text(
                          '© 2026 CureNurture',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      enabled: !_loading,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Icon(icon, color: AppTheme.iconMuted, size: 19),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppTheme.surfaceTint,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          borderSide: const BorderSide(color: AppTheme.blue1, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          borderSide: const BorderSide(color: Color(0xFFD48B8B)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          borderSide: const BorderSide(color: Color(0xFFB91C1C), width: 1.4),
        ),
        errorStyle: const TextStyle(
          color: Color(0xFF9F1B1B),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
