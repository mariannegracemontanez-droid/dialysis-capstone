import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'landing_page.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;

  String? _errorMessage;
  String? _emailError;
  String? _passwordError;

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
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _errorMessage = null;
      _emailError = null;
      _passwordError = null;
    });

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _emailError = email.isEmpty ? 'Email is required' : null;
        _passwordError = password.isEmpty ? 'Password is required' : null;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user ?? response.session?.user;

      if (user == null) {
        throw const AuthException('Login failed. Please try again.');
      }

      if (!mounted) return;

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = profile?['role'] as String?;

      if (role == 'super_admin' || role == 'admin' || role == 'patient') {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: secondaryColor),
                SizedBox(width: 10),
                Text('Access Denied'),
              ],
            ),
            content: const Text(
              'This login page is only available for donor and supporter accounts. Please go back to login.',
              style: TextStyle(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                },
                child: const Text(
                  'Back to Login',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LandingPage()),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? errorText,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: secondaryColor,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: Icon(icon, color: primaryColor),
        suffixIcon: suffixIcon,
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

  Widget _buildLeftPanel() {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(42),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            secondaryColor.withOpacity(0.96),
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
            'Welcome back to CureNurture.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Sign in to continue supporting dialysis patients and become part of a community that turns compassion into real care.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontSize: 15.5,
              height: 1.75,
            ),
          ),
          const SizedBox(height: 34),
          _buildInfoCard(
            icon: Icons.verified_rounded,
            title: 'Trusted donation experience',
            subtitle: 'Verified activity helps keep the platform transparent.',
          ),
          const SizedBox(height: 14),
          _buildInfoCard(
            icon: Icons.favorite_rounded,
            title: 'Patient-centered mission',
            subtitle: 'Every act of support helps bring hope to families.',
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm({required bool mobile}) {
    return Container(
      padding: EdgeInsets.all(mobile ? 26 : 42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: mobile
            ? const BorderRadius.vertical(bottom: Radius.circular(15))
            : const BorderRadius.horizontal(right: Radius.circular(15)),
      ),
      child: SingleChildScrollView(
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
            Text(
              'Login to your account',
              textAlign: mobile ? TextAlign.center : TextAlign.left,
              style: const TextStyle(
                color: secondaryColor,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Access your donor account and continue helping patients receive the care they need.',
              textAlign: mobile ? TextAlign.center : TextAlign.left,
              style: TextStyle(color: Colors.blueGrey.shade600, height: 1.55),
            ),
            const SizedBox(height: 28),

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
              delay: 80,
              child: _buildTextField(
                controller: _emailController,
                label: 'Email Address',
                hint: 'Enter your email address',
                icon: Icons.email_outlined,
                errorText: _emailError,
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(height: 16),

            _animatedEntry(
              delay: 140,
              child: _buildTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'Enter your password',
                icon: Icons.lock_outline_rounded,
                errorText: _passwordError,
                obscureText: !_showPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: Colors.blueGrey.shade500,
                  ),
                  onPressed: () {
                    setState(() => _showPassword = !_showPassword);
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Secure donor access',
                style: TextStyle(
                  color: Colors.blueGrey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 24),

            _animatedEntry(
              delay: 200,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
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
                                'Login',
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
                    'new here?',
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

            const SizedBox(height: 18),

            Center(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    'Don’t have an account?',
                    style: TextStyle(color: Colors.blueGrey.shade600),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pushReplacement(_smoothRoute(const SignupPage()));
                    },
                    child: const Text(
                      'Create an account',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'By logging in, you continue supporting CureNurture’s mission of compassion, transparency, and patient-centered care.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.blueGrey.shade400,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
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
            'Welcome back.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Continue your role in helping dialysis patients receive care and hope.',
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
                  secondaryColor.withOpacity(0.90),
                  primaryColor.withOpacity(0.50),
                  Colors.white.withOpacity(0.10),
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
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: -90,
          left: -70,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 28,
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: mobile ? 430 : 980),
                      height: mobile ? null : 640,
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
                                _buildLoginForm(mobile: true),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(flex: 5, child: _buildLeftPanel()),
                                Expanded(
                                  flex: 5,
                                  child: _buildLoginForm(mobile: false),
                                ),
                              ],
                            ),
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
