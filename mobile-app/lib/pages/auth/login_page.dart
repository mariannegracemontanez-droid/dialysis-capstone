import 'package:CureNurture/services/fcm_service.dart';
import 'package:CureNurture/services/notification_service.dart';
import 'package:flutter/material.dart';
import '../../services/auth/auth_service.dart';
import '../../theme/auth_theme_controller.dart';
import '../../utils/validators.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final FocusNode _emailFocusNode = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  String? _emailError;
  bool _emailTouched = false;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(() {
      // Only start showing a format error once the user has left the
      // field — never while they're still in the middle of typing it.
      if (!_emailFocusNode.hasFocus) {
        setState(() {
          _emailTouched = true;
          _emailError = Validators.validateEmail(_emailController.text);
        });
      }
    });
  }

  void _onEmailChanged(String value) {
    if (!_emailTouched) return;
    setState(() {
      _emailError = value.isEmpty ? null : Validators.validateEmail(value);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final emailError = Validators.validateEmail(email);
    setState(() {
      _emailTouched = true;
      _emailError = emailError;
    });
    if (emailError != null) {
      setState(() => _errorMessage = emailError);
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signIn(email: email, password: password);

      if (!mounted) return;

      Navigator.of(context).pushReplacementNamed('/home');

      Future.microtask(() async {
        try {
          await FcmService().initialize();

          await NotificationService().createNotification(
            title: 'Account Login',
            message: 'Your account was accessed just now.',
            type: 'security',
          );
        } catch (e) {
          debugPrint('Notification setup error: $e');
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          final error = e.toString().toLowerCase();

          if (error.contains('invalid login credentials')) {
            _errorMessage = 'Incorrect email or password.';
          } else {
            _errorMessage = 'Something went wrong. Please try again.';
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AuthThemeController.mode,
      builder: (context, mode, _) {
        final colors = AuthColors(mode == ThemeMode.dark);

        return Scaffold(
          backgroundColor: colors.backgroundSolid,
          body: Stack(
            children: [
              if (colors.useImageBackground)
                Positioned.fill(
                  child: Image.asset(
                    'lib/asset/Image/image 4.png',
                    fit: BoxFit.cover,
                  ),
                ),

              Positioned.fill(
                child: Container(color: colors.overlay),
              ),

              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          MediaQuery.of(context).size.height -
                          MediaQuery.of(context).padding.top -
                          MediaQuery.of(context).padding.bottom,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 40,
                      ),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: AuthThemeToggleButton(colors: colors),
                          ),

                          const SizedBox(height: 20),

                          Container(
                            width: 104,
                            height: 104,
                            padding: const EdgeInsets.all(10),
                            child: Image.asset(
                              'lib/asset/Image/CureNurture_CircleLogo.png',
                            ),
                          ),

                          const SizedBox(height: 26),

                          Text(
                            'Welcome Back',
                            style: TextStyle(
                              color: colors.title,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Log in to continue your healthcare journey',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.subtitle,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),

                          const SizedBox(height: 42),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(26, 42, 26, 28),
                            decoration: BoxDecoration(
                              color: colors.cardFill,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: colors.cardBorder,
                                width: 1.1,
                              ),
                              boxShadow: colors.isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _emailController,
                                  focusNode: _emailFocusNode,
                                  keyboardType: TextInputType.emailAddress,
                                  onChanged: _onEmailChanged,
                                  style: TextStyle(
                                    color: colors.fieldText,
                                    fontSize: 15,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Email Address',
                                    hintStyle: TextStyle(
                                      color: colors.fieldHint,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.alternate_email,
                                      color: colors.fieldIcon,
                                    ),
                                    errorText: _emailError,
                                    errorStyle: TextStyle(
                                      color: colors.errorText,
                                    ),
                                    filled: true,
                                    fillColor: colors.fieldFill,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 22,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: colors.fieldBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: colors.fieldBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: colors.fieldFocusedBorder,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                TextField(
                                  controller: _passwordController,
                                  obscureText: !_isPasswordVisible,
                                  style: TextStyle(
                                    color: colors.fieldText,
                                    fontSize: 15,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Password',
                                    hintStyle: TextStyle(
                                      color: colors.fieldHint,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.lock_outline,
                                      color: colors.fieldIcon,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _isPasswordVisible
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: colors.fieldIcon,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isPasswordVisible =
                                              !_isPasswordVisible;
                                        });
                                      },
                                    ),
                                    filled: true,
                                    fillColor: colors.fieldFill,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 22,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: colors.fieldBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: colors.fieldBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: colors.fieldFocusedBorder,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 8),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.of(
                                        context,
                                      ).pushNamed('/forgot-password');
                                    },
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(10, 10),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: colors.link.withOpacity(0.78),
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),

                                if (_errorMessage != null) ...[
                                  const SizedBox(height: 14),

                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.red.withOpacity(0.25),
                                      ),
                                    ),
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: colors.errorText,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 34),

                                SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      backgroundColor: colors.primaryButton,
                                      disabledBackgroundColor:
                                          colors.primaryButton.withOpacity(
                                            0.55,
                                          ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          14,
                                        ),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.4,
                                            ),
                                          )
                                        : const Text(
                                            'Log In',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 26),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Don’t have an account? ',
                                      style: TextStyle(
                                        color: colors.mutedText,
                                        fontSize: 13,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.of(
                                          context,
                                        ).pushNamed('/signup');
                                      },
                                      child: Text(
                                        'Create Account',
                                        style: TextStyle(
                                          color: colors.link,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
