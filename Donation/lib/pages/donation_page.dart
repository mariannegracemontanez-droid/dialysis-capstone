import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import 'proof_page.dart';

class DonationPage extends StatefulWidget {
  const DonationPage({super.key});

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _customAmountController = TextEditingController();
  String? _selectedPaymentChannel;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  final Color _darkTeal = const Color(0xFF1F5E7D);
  final Color _lightGray = const Color(0xFFF2F5F8);



  @override
  void initState() {
    super.initState();

    final user = Supabase.instance.client.auth.currentUser;

    if (user != null) {
      _emailController.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _customAmountController.dispose();
    super.dispose();
  }

  void _selectAmount(String amount) {
    setState(() {
      _customAmountController.text = amount.replaceAll('P', '');
      _errorMessage = null;
    });
  }

  void _selectPaymentChannel(String channel) {
    setState(() {
      _selectedPaymentChannel = channel;
      _errorMessage = null;
    });
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  double? _parseAmount() {
    final value = _customAmountController.text.trim();
    if (value.isEmpty) {
      return null;
    }
    return double.tryParse(value);
  }

  Future<void> _goToPayment() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final amount = _parseAmount();
    final paymentMethod = _selectedPaymentChannel;

    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your name or organization name.';
        _successMessage = null;
      });
      return;
    }

    if (email.isEmpty || !_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
        _successMessage = null;
      });
      return;
    }

    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Please choose or enter a valid donation amount.';
        _successMessage = null;
      });
      return;
    }

    if (paymentMethod == null) {
      setState(() {
        _errorMessage = 'Please select a payment channel.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }
  Widget _buildTextField({
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    Widget? prefixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: _lightGray,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(40),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        prefixIcon: prefixIcon,
      ),
    );
  }

  Widget _buildAmountButton(String label) {
    final isSelected = _customAmountController.text.trim() == label.replaceAll('P', '');
    return OutlinedButton(
      onPressed: () => _selectAmount(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? _darkTeal : Colors.white,
        foregroundColor: isSelected ? Colors.white : _darkTeal,
        side: BorderSide(color: _darkTeal.withOpacity(0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      child: Text(label),
    );
  }
Widget _paymentButton(String method) {
  final isSelected = _selectedPaymentChannel == method;

  return GestureDetector(
    onTap: () {
      setState(() => _selectedPaymentChannel = method);
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF2F6D85) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isSelected ? const Color(0xFF2F6D85) : Colors.grey.shade300,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ]
            : [],
      ),
      child: Center(
        child: Text(
          method,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _darkTeal,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: const Column(
        children: [
          Text(
            'Clinic Contact Information',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.email, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('support@curenurture.org', style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('1925 Enterprise Road, Cure Nurture', style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
         backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        title: Row(
          children: [
            Image.asset('lib/assets/image/CureNurture_logo.png', width: 34, height: 34),
            const SizedBox(width: 12),
            const Text('Cure Nurture', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
     body: Center(
  child: ConstrainedBox(
   constraints: const BoxConstraints(maxWidth: 520),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 10),

          const Text(
            'Donor Contribution',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'You may edit your details if needed',
            style: TextStyle(color: Colors.grey),
          ),

          const SizedBox(height: 24),

          /// 🔒 NOT LOGGED IN
          if (user == null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Please log in to donate',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sign in or create an account first.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _darkTeal,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("Go to Login"),
                  )
                ],
              ),
            ),

          /// ✅ FORM
          if (user != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // NAME
                  _buildTextField(
                    hint: 'Full Name / Organization',
                    controller: _nameController,
                  ),
                  const SizedBox(height: 16),

                  // EMAIL
                  _buildTextField(
                    hint: 'Email Address',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 32, thickness: 0.8),

                  const Text(
                    'Choose Amount',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 150,
                        child: _buildTextField(
                          hint: 'Custom Amount',
                          controller: _customAmountController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      _buildAmountButton('P50'),
                      _buildAmountButton('P100'),
                      _buildAmountButton('P500'),
                      _buildAmountButton('P1000'),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 32, thickness: 0.8),

                  const Text(
                    'Payment Method',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(child: _paymentButton('GCASH')),
                      const SizedBox(width: 16),
                      Expanded(child: _paymentButton('BANK TRANSFER')),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),

                  if (_successMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),

                  /// 🔥 DONATE BUTTON
                  SizedBox(
                    height: 55,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final user = Supabase
                                  .instance.client.auth.currentUser;

                              if (user == null) return;

                              final amount = _parseAmount();

                              if (amount == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text("Enter valid amount")),
                                );
                                return;
                              }

                              if (_selectedPaymentChannel == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Select payment method")),
                                );
                                return;
                              }

                              try {
                                final response = await Supabase
                                    .instance.client
                                    .from('donations')
                                    .insert({
                                  'donor_id': user.id,
                                  'name': _nameController.text,
                                  'email': _emailController.text,
                                  'amount': amount,
                                  'payment_method':
                                      _selectedPaymentChannel,
                                  'status': 'pending',
                                }).select().single();

                                final donationId = response['id'];

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProofUploadPage(
                                      donationId: donationId,
                                    ),
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text("Error: $e")),
                                );
                              }
                            },
                          style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38A6DB),
                        elevation: 4,
                        shadowColor: Colors.black.withOpacity(0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'DONATE NOW',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 1,
                            color: Colors.white,
                          ),
                        ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 30),

          _buildFooter(),
        ],
      ),
    ),
  ),
)
    );

}
}
