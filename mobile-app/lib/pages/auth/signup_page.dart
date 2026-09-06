import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/signup_data.dart';
import '../../services/auth/auth_service.dart';
import '../../theme/auth_theme_controller.dart';
import '../../utils/validators.dart';
import 'dart:ui';

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
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  bool _isLoading = false;

  String? _errorMessage;
  String? _nameError;
  String? _emailError;
  String? _phoneError;
  String? _passwordFieldError;
  String? _confirmPasswordError;
  // Tracks whether the user has left each field at least once — an error
  // for these is only ever shown after that, never while first typing.
  bool _emailTouched = false;
  bool _passwordTouched = false;
  bool _confirmPasswordTouched = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _showPasswordRequirements = false;
  Map<String, bool> _passwordValidation = AuthService.passwordRequirements('');

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(() {
      if (!_emailFocusNode.hasFocus) {
        setState(() {
          _emailTouched = true;
          _emailError = Validators.validateEmail(_emailController.text);
        });
      }
    });
    _passwordFocusNode.addListener(() {
      setState(() {
        _showPasswordRequirements =
            _passwordFocusNode.hasFocus || _passwordController.text.isNotEmpty;
        if (!_passwordFocusNode.hasFocus) {
          _passwordTouched = true;
          _passwordFieldError = _passwordController.text.isEmpty
              ? null
              : AuthService.validatePassword(_passwordController.text);
        }
      });
    });
    _confirmPasswordFocusNode.addListener(() {
      if (!_confirmPasswordFocusNode.hasFocus) {
        setState(() {
          _confirmPasswordTouched = true;
          _confirmPasswordError = _confirmPasswordController.text.isEmpty
              ? null
              : (_confirmPasswordController.text != _passwordController.text
                    ? 'Passwords do not match'
                    : null);
        });
      }
    });
  }

  void _onNameChanged(String value) {
    setState(() {
      _nameError = value.isEmpty
          ? null
          : Validators.validateName(value, fieldLabel: 'Patient name');
    });
  }

  void _onEmailChanged(String value) {
    if (!_emailTouched) return;
    setState(() {
      _emailError = value.isEmpty ? null : Validators.validateEmail(value);
    });
  }

  void _onPhoneChanged(String value) {
    setState(() {
      _phoneError = value.isEmpty ? null : Validators.validatePhone(value);
    });
  }

  void _onConfirmPasswordChanged(String value) {
    if (!_confirmPasswordTouched) return;
    setState(() {
      _confirmPasswordError = value.isEmpty
          ? null
          : (value != _passwordController.text
                ? 'Passwords do not match'
                : null);
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  void _updatePasswordRequirements(String password) {
    setState(() {
      _passwordValidation = AuthService.passwordRequirements(password);
      _showPasswordRequirements =
          _passwordFocusNode.hasFocus || password.isNotEmpty;
      if (_passwordTouched) {
        _passwordFieldError = password.isEmpty
            ? null
            : AuthService.validatePassword(password);
      }
      if (_confirmPasswordTouched && _confirmPasswordController.text.isNotEmpty) {
        _confirmPasswordError =
            _confirmPasswordController.text != password
            ? 'Passwords do not match'
            : null;
      }
    });
  }

  Future<void> _handleSignupNext() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final passwordError = AuthService.validatePassword(password);

    final nameError = Validators.validateName(
      _fullNameController.text,
      fieldLabel: 'Patient name',
    );
    final emailError = Validators.validateEmail(_emailController.text);
    final phoneError = Validators.validatePhone(_phoneController.text);
    final confirmError = password.isEmpty
        ? null
        : (password != confirmPassword ? 'Passwords do not match' : null);

    setState(() {
      _nameError = nameError;
      _emailError = emailError;
      _emailTouched = true;
      _phoneError = phoneError;
      _passwordFieldError = password.isEmpty ? 'Password is required' : passwordError;
      _passwordTouched = true;
      _confirmPasswordError = confirmError;
      _confirmPasswordTouched = true;
    });

    if (nameError != null) {
      setState(() => _errorMessage = nameError);
      return;
    }
    if (emailError != null) {
      setState(() => _errorMessage = emailError);
      return;
    }
    if (phoneError != null) {
      setState(() => _errorMessage = phoneError);
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Password is required');
      return;
    }
    if (passwordError != null) {
      setState(() => _errorMessage = passwordError);
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final createdUser = await AuthService().signUp(
        email: _emailController.text.trim(),
        password: password,
        fullName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      final signupData = SignupData(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: password,
        profileId: createdUser.id,
      );

      if (mounted) {
        Navigator.of(context).pushNamed('/setup', arguments: signupData);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
                    vertical: 28,
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: AuthThemeToggleButton(colors: colors),
                      ),

                      const SizedBox(height: 12),

                      Container(
                        width: 100,
                        height: 100,
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(
                          'lib/asset/Image/CureNurture_CircleLogo.png',
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        'Create Account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.title,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Start your healthcare journey with CureNurture',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.subtitle,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 30),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            margin: const EdgeInsets.only(bottom: 22),
                            decoration: BoxDecoration(
                              color: colors.glassTint.withOpacity(0.72),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: colors.glassTint.withOpacity(0.50),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 18,
                                      color: Color.fromARGB(255, 130, 27, 27),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Take note:',
                                      style: TextStyle(
                                        color: Color.fromARGB(255, 23, 78, 104),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),

                                SizedBox(height: 10),

                                Text(
                                  '• Save your email and password after creating your account.',
                                  style: TextStyle(
                                    color: Color.fromARGB(255, 37, 71, 84),
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),

                                SizedBox(height: 6),

                                Text(
                                  '• Your account will be accessible once approved by your chosen clinic or admin.',
                                  style: TextStyle(
                                    color: Color.fromARGB(255, 37, 71, 84),
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),

                                SizedBox(height: 6),

                                Text(
                                  '• For security, do not share your password with anyone.',
                                  style: TextStyle(
                                    color: Color.fromARGB(255, 37, 71, 84),
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                            decoration: BoxDecoration(
                              color: colors.glassTint.withOpacity(0.78),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colors.glassTint.withOpacity(0.55),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildSignupField(
                                  controller: _fullNameController,
                                  hint: 'Patient Name',
                                  icon: Icons.person_outline,
                                  errorText: _nameError,
                                  onChanged: _onNameChanged,
                                ),

                                const SizedBox(height: 16),

                                _buildSignupField(
                                  controller: _emailController,
                                  focusNode: _emailFocusNode,
                                  hint: 'Email Address',
                                  icon: Icons.alternate_email,
                                  keyboardType: TextInputType.emailAddress,
                                  errorText: _emailError,
                                  onChanged: _onEmailChanged,
                                ),

                                const SizedBox(height: 16),

                                _buildSignupField(
                                  controller: _phoneController,
                                  hint: 'Phone Number',
                                  icon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 11,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  errorText: _phoneError,
                                  onChanged: _onPhoneChanged,
                                ),

                                const SizedBox(height: 16),

                                TextField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocusNode,
                                  obscureText: _obscurePassword,
                                  onChanged: _updatePasswordRequirements,
                                  decoration: _inputDecoration(
                                    hint: 'Create Password',
                                    icon: Icons.lock_outline,
                                    errorText: _passwordFieldError,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: const Color(0xFF5F7280),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                ),

                                if (_showPasswordRequirements) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: colors.glassTint.withOpacity(
                                        0.55,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFFD7E8EE),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Password must include:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF2C5F7D),
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        ..._passwordValidation.entries.map((
                                          entry,
                                        ) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 9,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  entry.value
                                                      ? Icons.check_circle
                                                      : Icons
                                                            .radio_button_unchecked,
                                                  size: 17,
                                                  color: entry.value
                                                      ? const Color(0xFF3BB54A)
                                                      : const Color(0xFF8B9AA6),
                                                ),
                                                const SizedBox(width: 9),
                                                Expanded(
                                                  child: Text(
                                                    entry.key,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: entry.value
                                                          ? const Color(
                                                              0xFF2C5F7D,
                                                            )
                                                          : const Color(
                                                              0xFF60717D,
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 16),

                                TextField(
                                  controller: _confirmPasswordController,
                                  focusNode: _confirmPasswordFocusNode,
                                  obscureText: _obscureConfirmPassword,
                                  onChanged: _onConfirmPasswordChanged,
                                  decoration: _inputDecoration(
                                    hint: 'Confirm Password',
                                    icon: Icons.lock_outline,
                                    errorText: _confirmPasswordError,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConfirmPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: const Color(0xFF5F7280),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscureConfirmPassword =
                                              !_obscureConfirmPassword;
                                        });
                                      },
                                    ),
                                  ),
                                ),

                                if (_errorMessage != null) ...[
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.all(13),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.red.withOpacity(0.25),
                                      ),
                                    ),
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 24),

                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _handleSignupNext,
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      backgroundColor: const Color(0xFF2C5F7D),
                                      disabledBackgroundColor: const Color(
                                        0xFF2C5F7D,
                                      ).withOpacity(0.55),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
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
                                            'NEXT',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 22),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Already have an account? ',
                                      style: TextStyle(
                                        color: Color(0xFF4B5E68),
                                        fontSize: 13,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.of(
                                          context,
                                        ).pushReplacementNamed('/login');
                                      },
                                      child: const Text(
                                        'Sign In',
                                        style: TextStyle(
                                          color: Color(0xFF2C5F7D),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),
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

  Widget _buildSignupField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    FocusNode? focusNode,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      decoration: _inputDecoration(
        hint: hint,
        icon: icon,
        showCounter: maxLength == null,
        errorText: errorText,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
    bool showCounter = true,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF6F7F89),
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF5F7280)),
      suffixIcon: suffixIcon,
      errorText: errorText,
      counterText: showCounter ? null : '',
      filled: true,
      fillColor: Colors.white.withOpacity(0.62),
      contentPadding: const EdgeInsets.symmetric(vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.70)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.70)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2C5F7D), width: 1.2),
      ),
    );
  }
}
