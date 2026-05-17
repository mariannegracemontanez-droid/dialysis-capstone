import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'landing_page.dart';
import 'login_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage>
    with SingleTickerProviderStateMixin {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  String? _errorMessage;
  String? _fullNameError;
  String? _emailError;
  String? _phoneError;
  String? _passwordError;
  String? _confirmPasswordError;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  static const Color primaryColor = Color(0xFF3B97A2);
  static const Color secondaryColor = Color(0xFF163B56);
  static const Color surfaceColor = Color(0xFFF6FAFD);
  static const Color softBlue = Color(0xFFEAF7FB);

  Route _smoothRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    setState(() {
      _errorMessage = null;
      _fullNameError = null;
      _emailError = null;
      _phoneError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    if (fullName.isEmpty || email.isEmpty || phone.isEmpty) {
      setState(() {
        _fullNameError = fullName.isEmpty ? 'Full name is required' : null;
        _emailError = email.isEmpty ? 'Email is required' : null;
        _phoneError = phone.isEmpty ? 'Phone number is required' : null;
      });
      return;
    }

    if (password.isEmpty || confirmPassword.isEmpty) {
      setState(() {
        _passwordError = password.isEmpty ? 'Password is required' : null;
        _confirmPasswordError = confirmPassword.isEmpty
            ? 'Confirm your password'
            : null;
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _confirmPasswordError = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      final user = response.user ?? response.session?.user;

      if (user == null) {
        throw Exception("User creation failed");
      }

      await Supabase.instance.client.from('donors').insert({
        'id': user.id,
        'name': fullName,
        'email': email,
        'phone': phone,
      });

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'email': email,
        'full_name': fullName,
        'phone': phone,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Welcome to CureNurture. Your account is ready.'),
          backgroundColor: primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      final lower = e.message.toLowerCase();

      final friendly =
          lower.contains('already registered') ||
              lower.contains('duplicate') ||
              lower.contains('user exists')
          ? 'This email is already registered. Please log in instead.'
          : e.message;

      setState(() {
        _errorMessage = friendly;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'An error occurred: $e';
        _isLoading = false;
      });
    }
  }

  Widget _animatedEntry({required Widget child, int delay = 0}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 550 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 22 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'lib/assets/image/gradient_background.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  secondaryColor.withOpacity(0.92),
                  primaryColor.withOpacity(0.56),
                  Colors.white.withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -70,
          child: Container(
            width: 230,
            height: 230,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(42),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            secondaryColor.withOpacity(0.97),
            primaryColor.withOpacity(0.86),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'lib/assets/image/CureNurture_logo.png',
            width: 68,
            height: 68,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 28),
          const Text(
            'Create an account that helps create hope.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              height: 1.14,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Join CureNurture as a donor and become part of a compassionate community supporting dialysis patients through care, transparency, and generosity.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontSize: 15.5,
              height: 1.75,
            ),
          ),
          const SizedBox(height: 34),
          _buildInfoCard(
            icon: Icons.volunteer_activism_rounded,
            title: 'Start giving with purpose',
            subtitle: 'Support patients who need help with treatment costs.',
          ),
          const SizedBox(height: 14),
          _buildInfoCard(
            icon: Icons.verified_rounded,
            title: 'Transparent donation journey',
            subtitle: 'Verified donation activity helps build donor trust.',
          ),
          const SizedBox(height: 14),
          _buildInfoCard(
            icon: Icons.health_and_safety_rounded,
            title: 'Patient-centered mission',
            subtitle: 'Every contribution helps bring care closer to families.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignupForm({required bool mobile}) {
    return Container(
      padding: EdgeInsets.all(mobile ? 26 : 42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: mobile
            ? const BorderRadius.vertical(bottom: Radius.circular(15))
            : const BorderRadius.horizontal(right: Radius.circular(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mobile) ...[
            Center(
              child: Image.asset(
                'lib/assets/image/CureNurture_logo.png',
                width: 64,
                height: 64,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 18),
          ],
          const Text(
            'Create your donor account',
            style: TextStyle(
              color: secondaryColor,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 24),

          if (_errorMessage != null) ...[
            _animatedEntry(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withOpacity(0.20)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          _animatedEntry(
            delay: 70,
            child: _buildField(
              controller: _fullNameController,
              label: 'Full Name',
              hint: 'Enter your complete name',
              icon: Icons.person_outline_rounded,
              error: _fullNameError,
            ),
          ),
          const SizedBox(height: 14),

          _animatedEntry(
            delay: 110,
            child: _buildField(
              controller: _emailController,
              label: 'Email Address',
              hint: 'Enter your email address',
              icon: Icons.email_outlined,
              error: _emailError,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const SizedBox(height: 14),

          _animatedEntry(
            delay: 150,
            child: _buildField(
              controller: _phoneController,
              label: 'Phone Number',
              hint: 'Enter your contact number',
              icon: Icons.phone_outlined,
              error: _phoneError,
              keyboardType: TextInputType.phone,
            ),
          ),
          const SizedBox(height: 14),

          _animatedEntry(
            delay: 190,
            child: _buildPasswordField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Create a secure password',
              error: _passwordError,
              isVisible: _showPassword,
              onToggle: () {
                setState(() => _showPassword = !_showPassword);
              },
            ),
          ),
          const SizedBox(height: 14),

          _animatedEntry(
            delay: 230,
            child: _buildPasswordField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              error: _confirmPasswordError,
              isVisible: _showConfirmPassword,
              onToggle: () {
                setState(() {
                  _showConfirmPassword = !_showConfirmPassword;
                });
              },
            ),
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: softBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your information is used to manage your donor account and donation activity.',
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _animatedEntry(
            delay: 270,
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _signup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  disabledBackgroundColor: primaryColor.withOpacity(0.55),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _isLoading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          key: ValueKey('text'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Create Account',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 22),

          Row(
            children: [
              Expanded(child: Divider(color: Colors.blueGrey.shade100)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'already joined?',
                  style: TextStyle(
                    color: Colors.blueGrey.shade400,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.blueGrey.shade100)),
            ],
          ),

          const SizedBox(height: 16),

          Center(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                Text(
                  'Already have an account?',
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushReplacement(_smoothRoute(const LoginPage()));
                  },
                  child: const Text(
                    'Log In',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            secondaryColor.withOpacity(0.96),
            primaryColor.withOpacity(0.86),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
      ),
      child: Column(
        children: [
          const Text(
            'Join CureNurture.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Create an account and help bring hope to dialysis patients.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.80),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? error,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: secondaryColor,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        prefixIcon: Icon(icon, color: primaryColor),
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: TextStyle(color: Colors.blueGrey.shade600),
        hintStyle: TextStyle(color: Colors.blueGrey.shade300),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDCE8EE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDCE8EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isVisible,
    required VoidCallback onToggle,
    String? error,
  }) {
    return TextField(
      controller: controller,
      obscureText: !isVisible,
      style: const TextStyle(
        color: secondaryColor,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: primaryColor),
        suffixIcon: IconButton(
          icon: Icon(
            isVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: Colors.blueGrey.shade500,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: TextStyle(color: Colors.blueGrey.shade600),
        hintStyle: TextStyle(color: Colors.blueGrey.shade300),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDCE8EE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDCE8EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mobile = width < 820;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: secondaryColor,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: mobile ? 460 : 1040),
                    height: mobile ? null : 750,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 36,
                          offset: const Offset(0, 24),
                        ),
                      ],
                    ),
                    child: mobile
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildMobileHeader(),
                              _buildSignupForm(mobile: true),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(flex: 5, child: _buildLeftPanel()),
                              Expanded(
                                flex: 5,
                                child: _buildSignupForm(mobile: false),
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
}
