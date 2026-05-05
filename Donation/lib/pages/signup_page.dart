import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'landing_page.dart';
import 'login_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
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

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

    // VALIDATION
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
        _confirmPasswordError =
            confirmPassword.isEmpty ? 'Confirm your password' : null;
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
      /// 🔥 SIGN UP (AUTH)
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      final user = response.user ?? response.session?.user;

      if (user == null) {
        throw Exception("User creation failed");
      }

      /// 🔥 SAVE TO DONORS TABLE
      await Supabase.instance.client.from('donors').insert({
        'id': user.id,
        'name': fullName,
        'email': email,
        'phone': phone,
      });

      /// 🔥 OPTIONAL: SAVE TO PROFILES
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'email': email,
        'full_name': fullName,
        'phone': phone,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to CureNurture 👋')),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
    }

    /// ❗ FIXED SYNTAX HERE
    on AuthException catch (e) {
      if (!mounted) return;

      final lower = (e.message ?? '').toLowerCase();

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
    }

    catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'An error occurred: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF3B97A2);
    const secondaryColor = Color(0xFF163B56);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'lib/assets/image/gradient_background.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          /// LOGO + TITLE
                          Column(
                            children: [
                              Image.asset(
                                'lib/assets/image/CureNurture_logo.png',
                                width: 72,
                                height: 72,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Cure Nurture',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Create an account to start helping',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),

                          const SizedBox(height: 30),

                          /// INPUTS
                          _buildField(
                              controller: _fullNameController,
                              label: 'Full Name',
                              error: _fullNameError),

                          const SizedBox(height: 16),

                          _buildField(
                              controller: _emailController,
                              label: 'Email',
                              error: _emailError),

                          const SizedBox(height: 16),

                          _buildField(
                              controller: _phoneController,
                              label: 'Phone',
                              error: _phoneError),

                          const SizedBox(height: 16),

                          _buildPasswordField(
                            controller: _passwordController,
                            label: 'Password',
                            error: _passwordError,
                            isVisible: _showPassword,
                            onToggle: () {
                              setState(() {
                                _showPassword = !_showPassword;
                              });
                            },
                          ),

                          const SizedBox(height: 16),

                          _buildPasswordField(
                            controller: _confirmPasswordController,
                            label: 'Confirm Password',
                            error: _confirmPasswordError,
                            isVisible: _showConfirmPassword,
                            onToggle: () {
                              setState(() {
                                _showConfirmPassword =
                                    !_showConfirmPassword;
                              });
                            },
                          ),

                          const SizedBox(height: 24),

                          if (_errorMessage != null)
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),

                          const SizedBox(height: 12),

                          /// BUTTON
                          ElevatedButton(
                            onPressed: _isLoading ? null : _signup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text('Sign Up'),
                          ),

                          const SizedBox(height: 16),

                          /// LOGIN LINK
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Already have an account?'),
                              TextButton(
                                onPressed: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const LoginPage()),
                                  );
                                },
                                child: const Text('Log In'),
                              ),
                            ],
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

  /// 🔧 FIELD BUILDER
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? error,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  /// 🔧 PASSWORD FIELD
  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool isVisible,
    required VoidCallback onToggle,
    String? error,
  }) {
    return TextField(
      controller: controller,
      obscureText: !isVisible,
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        suffixIcon: IconButton(
          icon: Icon(isVisible ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
    );
  }
}