import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../utils/admin_validators.dart';
import '../../widgets/admin_title.dart';
import '../dashboard/dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _message;
  bool _isError = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
        );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------
  // Authentication -- unchanged. Same Supabase sign-in, same `profiles`
  // role check, same messages, same navigation on success.
  // --------------------------------------------------------------------
  Future<void> _signIn() async {
    // Checked before the request goes out. A blank password used to be
    // sent to Supabase and come back as "Invalid login credentials",
    // which reads as a wrong password rather than an empty field.
    final validationError = AdminValidators.firstError([
      () => AdminValidators.email(_emailController.text),
      () => AdminValidators.requiredText(
        _passwordController.text,
        label: 'password',
        maxLength: 200,
      ),
    ]);

    if (validationError != null) {
      setState(() {
        _isError = true;
        _message = validationError;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user == null) throw const AuthException('User not found');

      final profile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', res.user!.id)
          .maybeSingle();

      if (profile?['role'] != 'admin') {
        await Supabase.instance.client.auth.signOut();
        setState(() {
          _isError = true;
          _message = 'Access denied. Administrator privileges required.';
        });
        return;
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const DashboardPage()),
        );
      }
    } on AuthException catch (e) {
      setState(() {
        _isError = true;
        _message = e.message;
      });
    } catch (e) {
      setState(() {
        _isError = true;
        _message = 'An unexpected error occurred.';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminTitle(
      page: 'Admin Sign In',
      child: Scaffold(
        backgroundColor: AppTheme.canvas,
        body: Stack(
          children: [
            // A very light healthcare-inspired ground: a soft blue wash with
            // a few abstract shapes and a faint pulse line. No photograph,
            // no dark overlay.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.white,
                      Color(0xFFF2F7FB),
                      Color(0xFFE8F1F7),
                    ],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: const _LoginBackdropPainter()),
              ),
            ),

            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.border),
                              boxShadow: AppTheme.shadowSm,
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/CureNurture_CircleLogo.png',
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: Icon(
                                        Icons.local_hospital_rounded,
                                        color: AppTheme.blue1,
                                        size: 36,
                                      ),
                                    ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          const Text(
                            'CureNurture Center Portal',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.blue3,
                              fontSize: 24,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
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

                          const SizedBox(height: 30),

                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(AppTheme.rXl),
                              border: Border.all(color: AppTheme.border),
                              boxShadow: AppTheme.shadowSm,
                            ),
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildTextField(
                                  controller: _emailController,
                                  hint: 'Email Address',
                                  icon: Icons.alternate_email_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 18),
                                _buildTextField(
                                  controller: _passwordController,
                                  hint: 'Password',
                                  icon: Icons.lock_outline_rounded,
                                  isPassword: true,
                                  obscure: _obscurePassword,
                                  onSuffixTap: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  onSubmitted: (_) {
                                    if (!_loading) _signIn();
                                  },
                                ),

                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: _message == null
                                      ? const SizedBox.shrink()
                                      : Padding(
                                          key: ValueKey(_message),
                                          padding: const EdgeInsets.only(
                                            top: 16,
                                          ),
                                          child: _messageBox(),
                                        ),
                                ),

                                const SizedBox(height: 28),

                                SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _signIn,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.blue1,
                                      disabledBackgroundColor: AppTheme.blue1
                                          .withValues(alpha: 0.45),
                                      foregroundColor: AppTheme.white,
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
                                              height: 22,
                                              width: 22,
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
      ),
    );
  }

  Widget _messageBox() {
    final color = _isError ? AppTheme.danger : AppTheme.accentGreen;
    final background = _isError
        ? AppTheme.dangerSoft
        : AppTheme.accentGreenSoft;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onSuffixTap,
    TextInputType? keyboardType,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: !_loading,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: AppTheme.fieldTextStyle.copyWith(fontSize: 14),
      decoration:
          AppTheme.field(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppTheme.iconMuted, size: 19),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppTheme.iconMuted,
                      size: 19,
                    ),
                    onPressed: onSuffixTap,
                  )
                : null,
          ).copyWith(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
    );
  }
}

/// Soft abstract shapes behind the login card: two blue washes, a faint
/// ring, and a minimal ECG trace along the lower edge. Static, cheap to
/// paint, and deliberately low contrast so the form stays the subject.
class _LoginBackdropPainter extends CustomPainter {
  const _LoginBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final blob = Paint()..style = PaintingStyle.fill;

    // Top-left wash.
    blob.color = AppTheme.blue1.withValues(alpha: 0.05);
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.1),
      size.shortestSide * 0.42,
      blob,
    );

    // Bottom-right wash, slightly cooler.
    blob.color = AppTheme.blue2.withValues(alpha: 0.06);
    canvas.drawCircle(
      Offset(size.width * 0.94, size.height * 0.88),
      size.shortestSide * 0.38,
      blob,
    );

    // A third, smaller accent so the two washes don't read as symmetrical.
    blob.color = AppTheme.accentTeal.withValues(alpha: 0.04);
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.12),
      size.shortestSide * 0.16,
      blob,
    );

    // Concentric rings, top-right.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppTheme.blue1.withValues(alpha: 0.07);

    final ringCenter = Offset(size.width * 0.88, size.height * 0.3);
    for (final radius in [0.10, 0.16, 0.23]) {
      canvas.drawCircle(ringCenter, size.shortestSide * radius, ring);
    }

    // Minimal pulse line across the lower third.
    final pulse = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppTheme.blue1.withValues(alpha: 0.08);

    final baseline = size.height * 0.80;
    final step = math.max(size.width / 7, 90.0);
    final path = Path()..moveTo(-20, baseline);

    for (var x = -20.0; x < size.width + step; x += step) {
      path
        ..lineTo(x + step * 0.28, baseline)
        ..lineTo(x + step * 0.38, baseline - 26)
        ..lineTo(x + step * 0.48, baseline + 18)
        ..lineTo(x + step * 0.58, baseline)
        ..lineTo(x + step, baseline);
    }

    canvas.drawPath(path, pulse);
  }

  @override
  bool shouldRepaint(covariant _LoginBackdropPainter oldDelegate) => false;
}
