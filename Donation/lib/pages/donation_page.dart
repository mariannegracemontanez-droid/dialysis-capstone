import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import 'payment_page.dart';

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

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaymentPage(
          fullName: name,
          email: email,
          amount: amount,
          paymentMethod: paymentMethod,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (confirmed == true) {
        _successMessage = 'Donation pending verification. Thank you for your support!';
        _errorMessage = null;
        _selectedPaymentChannel = null;
        _customAmountController.clear();
      }
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

  Widget _buildPaymentChannelButton(String label) {
    final isSelected = _selectedPaymentChannel == label;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => _selectPaymentChannel(label),
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? _darkTeal : Colors.white,
          foregroundColor: isSelected ? Colors.white : _darkTeal,
          side: BorderSide(color: _darkTeal.withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        child: Text(label, textAlign: TextAlign.center),
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
      child: Column(
        children: const [
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
        backgroundColor: _darkTeal,
        elevation: 0,
        title: Row(
          children: [
            Image.asset('lib/assets/image/CureNurture_logo.png', width: 34, height: 34),
            const SizedBox(width: 12),
            const Text('Cure Nurture', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Donor Contribution Form',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 26),
            if (user == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 10)),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'Please log in to donate.',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sign in or create an account before proceeding with your donation.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _darkTeal, padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: () {
                          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
                        },
                        child: const Text('Go to Login'),
                      ),
                    ),
                  ],
                ),
              ),
            if (user != null) ...[
              _buildTextField(hint: 'Full Name / Organization Name', controller: _nameController),
              const SizedBox(height: 16),
              _buildTextField(hint: 'Email Address', controller: _emailController, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 24),
              const Text('Choose an amount to donate:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(width: 140, child: _buildTextField(hint: 'Custom Amount', controller: _customAmountController, keyboardType: TextInputType.number)),
                  _buildAmountButton('P50'),
                  _buildAmountButton('P100'),
                  _buildAmountButton('P500'),
                  _buildAmountButton('P1000'),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Payment Channel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildPaymentChannelButton('GCASH'),
                  const SizedBox(width: 12),
                  _buildPaymentChannelButton('BANK TRANSFER'),
                ],
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_successMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _successMessage!,
                    style: const TextStyle(color: Colors.green, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _goToPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _darkTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('DONATE NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            const SizedBox(height: 32),
            _buildFooter(),
          ],
        ),
      ),
    );
  }
}
