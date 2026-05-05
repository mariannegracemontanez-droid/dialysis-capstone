import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import '../models/center_model.dart';
import '../config/supabase_config.dart';

class AdminCreatePage extends StatefulWidget {
  const AdminCreatePage({super.key});

  @override
  State<AdminCreatePage> createState() => _AdminCreatePageState();
}

class _AdminCreatePageState extends State<AdminCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final ProfileService _service = ProfileService();

  List<CenterModel> _clinics = [];
  Set<String> _clinicsWithAdmin = {};
  String? selectedClinicId;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _loadClinics();
    _loadAdmins();
  }

  // 🔥 LOAD CLINICS (REALTIME)
  void _loadClinics() {
    SupabaseConfig.client
        .from('clinics')
        .stream(primaryKey: ['id'])
        .listen((data) {
      setState(() {
        _clinics =
            data.map((e) => CenterModel.fromJson(e)).toList();
      });
    });
  }

  // 🔥 LOAD ADMINS
  Future<void> _loadAdmins() async {
    final data = await SupabaseConfig.client
        .from('profiles')
        .select('clinic_id')
        .eq('role', 'admin');

    setState(() {
      _clinicsWithAdmin =
          data.map((e) => e['clinic_id'].toString()).toSet();
    });
  }

 Future<void> _createAccount() async {
  if (!_formKey.currentState!.validate()) return;

  if (_passwordController.text != _confirmPasswordController.text) {
    setState(() {
      _errorMessage = "Passwords do not match";
    });
    return;
  }

  if (selectedClinicId == null) {
    setState(() {
      _errorMessage = "Please select a clinic";
    });
    return;
  }

  setState(() {
    _isSubmitting = true;
    _errorMessage = null;
  });

  try {
    // ✅ STEP 1: CREATE AUTH USER
    final authResponse = await SupabaseConfig.client.auth.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    final user = authResponse.user;

    if (user == null) {
      throw Exception("User creation failed");
    }

    // ✅ STEP 2: INSERT TO PROFILES (WITH ID 🔥)
    await SupabaseConfig.client.from('profiles').insert({
      'id': user.id, // 🔥 CRITICAL
      'full_name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'role': 'admin',
      'phone': _phoneController.text.trim(),
      'clinic_id': selectedClinicId!,
      'status': 'active',
    });

    // 🔥 AUDIT LOG
    await ProfileService().logAction(
      action: 'admin_created',
      targetId: user.id,
      targetName: _nameController.text.trim(),
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);

  } catch (error) {
    setState(() {
      _errorMessage =
          error.toString().replaceFirst('Exception: ', '');
    });
  } finally {
    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
    }
  }
  
}

  Widget _buildClinicDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedClinicId,
      hint: const Text("Select Clinic"),
      items: _clinics.map((clinic) {
        final hasAdmin = _clinicsWithAdmin.contains(clinic.id);

        return DropdownMenuItem<String>(
          value: hasAdmin ? null : clinic.id,
          enabled: !hasAdmin,
          child: Text(
            clinic.name + (hasAdmin ? " (Has Admin)" : ""),
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          selectedClinicId = value;
        });
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Admin Account'),
        backgroundColor: const Color(0xFF174E71),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 12,
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Account Creation',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    if (_errorMessage != null)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: Colors.redAccent),
                        ),
                      ),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildClinicDropdown(), // 🔥 ADDED
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _nameController,
                            decoration:
                                const InputDecoration(
                                    labelText:
                                        'Enter Full Name'),
                            validator: (value) =>
                                value!.isEmpty
                                    ? 'Enter full name'
                                    : null,
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _emailController,
                            decoration:
                                const InputDecoration(
                                    labelText: 'Enter Email'),
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _phoneController,
                            decoration:
                                const InputDecoration(
                                    labelText:
                                        'Enter Phone Number'),
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: !_isConfirmPasswordVisible,
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isConfirmPasswordVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isConfirmPasswordVisible =
                                        !_isConfirmPasswordVisible;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Confirm your password';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),  
                          const SizedBox(height: 20),

                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : _createAccount,
                              child: _isSubmitting
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : const Text('Create'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}