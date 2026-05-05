import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import '../config/supabase_config.dart';

class AdminEditPage extends StatefulWidget {
  final Map<String, dynamic> admin;

  const AdminEditPage({super.key, required this.admin});

  @override
  State<AdminEditPage> createState() => _AdminEditPageState();
}

class _AdminEditPageState extends State<AdminEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  

  final ProfileService _service = ProfileService();

  bool _isSaving = false;
  String? _errorMessage;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _changePassword = false; // 🔥 NEW

  List<Map<String, dynamic>> _clinics = [];
  Set<String> _clinicsWithAdmin = {};
  String? selectedClinicId;

  @override
  void initState() {
    super.initState();

    _nameController.text = widget.admin['full_name'] ?? '';
    _phoneController.text = widget.admin['phone'] ?? '';
    selectedClinicId = widget.admin['clinic_id'];

    _loadClinics();
    _loadAdmins();
  }

  Future<void> _loadClinics() async {
    final data =
        await SupabaseConfig.client.from('clinics').select();

    setState(() {
      _clinics = List<Map<String, dynamic>>.from(data);
    });
  }

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

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (_changePassword && password != confirm) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    await ProfileService().logAction(
  action: 'edit_admin',
  targetId: widget.admin['id'],
  targetName: _nameController.text.trim(),
);
    try {
      await _service.updateAdmin(
        adminId: widget.admin['id'],
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        password:
            _changePassword && password.isNotEmpty ? password : null,
        clinicId: selectedClinicId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _errorMessage =
            error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.admin['email'] ?? '-';
    final id = widget.admin['id'] ?? '-';
    final isInactive = widget.admin['status'] == 'inactive';
    final hasClinic = widget.admin['clinic_id'] != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Admin Account'),
        backgroundColor: const Color(0xFF174E71),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 12,
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Edit Account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_errorMessage != null)
                      Text(
                        _errorMessage!,
                        style:
                            const TextStyle(color: Colors.redAccent),
                      ),

                    const SizedBox(height: 10),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // 🔥 CLINIC DROPDOWN WITH REMOVE
                         DropdownButtonFormField<String?>(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            value: selectedClinicId,
                            hint: const Text("Select Clinic"),

                            items: _clinics.map((clinic) {
                              final hasAdmin =
                                  _clinicsWithAdmin.contains(clinic['id']);
                              final isCurrent =
                                  clinic['id'] == widget.admin['clinic_id'];

                              return DropdownMenuItem<String?>(
                                value: clinic['id'],
                                enabled: !hasAdmin || isCurrent,
                                child: Text(
                                  clinic['name'] +
                                      (hasAdmin && !isCurrent
                                          ? " (Has Admin)"
                                          : ""),
                                ),
                              );
                            }).toList(),

                            // 🔥 LOCK LOGIC
                            onChanged: (isInactive || hasClinic)
                                ? null
                                : (value) {
                                    setState(() {
                                      selectedClinicId = value;
                                    });
                                  },
                          ),

                          const SizedBox(height: 14),

                          TextFormField(
                            initialValue: email,
                            readOnly: true,
                            decoration:
                                const InputDecoration(
                                    labelText: 'Email'),
                          ),

                          const SizedBox(height: 14),

                          TextFormField(
                            initialValue: id,
                            readOnly: true,
                            decoration:
                                const InputDecoration(
                                    labelText: 'User ID'),
                          ),

                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                            ),
                            validator: (value) =>
                                value == null || value.isEmpty
                                    ? 'Required'
                                    : null,
                          ),

                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                            ),
                          ),

                          const SizedBox(height: 10),

                          // 🔥 TOGGLE PASSWORD
                          SwitchListTile(
                            title:
                                const Text("Change Password"),
                            value: _changePassword,
                            onChanged: (val) {
                              setState(() {
                                _changePassword = val;
                              });
                            },
                          ),

                          if (_changePassword) ...[
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'New Password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword =
                                          !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller:
                                  _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              decoration: InputDecoration(
                                labelText:
                                    'Confirm Password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirm =
                                          !_obscureConfirm;
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _isSaving ? null : _saveChanges,
                              child: _isSaving
                                  ? const CircularProgressIndicator()
                                  : const Text("Save Changes"),
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