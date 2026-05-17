import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import 'proof_page.dart';

class DonationPage extends StatefulWidget {
  const DonationPage({super.key});

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _customAmountController = TextEditingController();

  String? _selectedPaymentChannel;
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  final Color _darkTeal = const Color(0xFF163B56);
  final Color _primaryTeal = const Color(0xFF3B97A2);
  final Color _accentBlue = const Color(0xFF38A6DB);
  final Color _surface = const Color(0xFFF7FBFD);
  final Color _softBlue = const Color(0xFFEAF7FB);
  final Color _fieldFill = const Color(0xFFF2F6F9);

  @override
  void initState() {
    super.initState();

    final user = Supabase.instance.client.auth.currentUser;

    if (user != null) {
      _emailController.text = user.email ?? '';
    }

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
    _nameController.dispose();
    _emailController.dispose();
    _customAmountController.dispose();
    _animationController.dispose();
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
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  PreferredSizeWidget _buildHeader() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 74,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: _darkTeal),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Image.asset(
            'lib/assets/image/CureNurture_logo.png',
            width: 36,
            height: 36,
          ),
          const SizedBox(width: 10),
          Text(
            'Cure Nurture',
            style: TextStyle(color: _darkTeal, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
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
            offset: Offset(0, 24 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 52),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkTeal, _primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mobile = constraints.maxWidth < 900;

              final text = Column(
                crossAxisAlignment: mobile
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: const Text(
                      'STEP 1 OF 2',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Start your donation details.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Fill in your information, choose a contribution amount, and select your payment method. The next step will ask you to upload your proof of payment.',
                    textAlign: mobile ? TextAlign.center : TextAlign.left,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: 16,
                      height: 1.7,
                    ),
                  ),
                ],
              );

              final steps = Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Column(
                  children: [
                    _heroStep(
                      icon: Icons.edit_note_rounded,
                      title: 'Enter Details',
                      text: 'Provide your name and email for donation records.',
                    ),
                    const SizedBox(height: 14),
                    _heroStep(
                      icon: Icons.volunteer_activism_rounded,
                      title: 'Choose Amount',
                      text: 'Select or enter the amount you want to give.',
                    ),
                    const SizedBox(height: 14),
                    _heroStep(
                      icon: Icons.upload_file_rounded,
                      title: 'Upload Proof Next',
                      text:
                          'Continue to the proof upload and verification step.',
                    ),
                  ],
                ),
              );

              if (mobile) {
                return Column(
                  children: [text, const SizedBox(height: 28), steps],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 6, child: text),
                  const SizedBox(width: 44),
                  Expanded(flex: 4, child: steps),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _heroStep({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Row(
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
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
                text,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageIntro() {
    return Column(
      children: [
        Text(
          'Complete Your Donation Details',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _darkTeal,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: Text(
            'This information helps us properly record your donation and connect it to your payment proof in the next step.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey.shade600,
              fontSize: 15.5,
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationProgress() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFD8EAF0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = constraints.maxWidth < 680;

          final steps = [
            _progressStep(
              number: '1',
              title: 'Donation Details',
              subtitle: 'Current step',
              active: true,
            ),
            _progressStep(
              number: '2',
              title: 'Proof Upload',
              subtitle: 'Next step',
              active: false,
            ),
            _progressStep(
              number: '3',
              title: 'Admin Review',
              subtitle: 'Pending',
              active: false,
            ),
          ];

          if (mobile) {
            return Column(
              children: steps
                  .map(
                    (step) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: step,
                    ),
                  )
                  .toList(),
            );
          }

          return Row(
            children: [
              Expanded(child: steps[0]),
              _progressLine(),
              Expanded(child: steps[1]),
              _progressLine(),
              Expanded(child: steps[2]),
            ],
          );
        },
      ),
    );
  }

  Widget _progressStep({
    required String number,
    required String title,
    required String subtitle,
    required bool active,
  }) {
    return Row(
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: active ? _primaryTeal : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? _primaryTeal : const Color(0xFFD8EAF0),
            ),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: active ? Colors.white : Colors.blueGrey,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: active ? _darkTeal : Colors.blueGrey.shade500,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.blueGrey.shade500,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _progressLine() {
    return Container(
      width: 34,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFCFE2EA),
    );
  }

  Widget _sectionLabel({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: _softBlue,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _primaryTeal),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _darkTeal,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.blueGrey.shade500,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    Widget? prefixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(color: _darkTeal, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        filled: true,
        fillColor: _fieldFill,
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
          borderSide: BorderSide(color: _primaryTeal, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildAmountButton(String label) {
    final isSelected =
        _customAmountController.text.trim() == label.replaceAll('P', '');

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _selectAmount(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        decoration: BoxDecoration(
          color: isSelected ? _darkTeal : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? _darkTeal : const Color(0xFFD5E4EA),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _darkTeal.withOpacity(0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : _darkTeal,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _paymentButton({
    required String method,
    required IconData icon,
    required String subtitle,
  }) {
    final isSelected = _selectedPaymentChannel == method;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _selectPaymentChannel(method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected ? _darkTeal : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? _darkTeal : const Color(0xFFDCE8EE),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _darkTeal.withOpacity(0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.16) : _softBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : _primaryTeal,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method,
                    style: TextStyle(
                      color: isSelected ? Colors.white : _darkTeal,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white.withOpacity(0.72)
                          : Colors.blueGrey.shade500,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: isSelected ? Colors.white : Colors.blueGrey.shade300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBox(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonationForm() {
    return _animatedEntry(
      delay: 100,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: const Color(0xFFE3EEF4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.045),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              icon: Icons.person_outline_rounded,
              title: 'Donor Information',
              subtitle:
                  'These details help us identify and record your contribution.',
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final mobile = constraints.maxWidth < 720;

                if (mobile) {
                  return Column(
                    children: [
                      _buildTextField(
                        label: 'Full Name / Organization',
                        hint: 'Enter your name',
                        controller: _nameController,
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          color: _primaryTeal,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        label: 'Email Address',
                        hint: 'Enter your email',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: _primaryTeal,
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        label: 'Full Name / Organization',
                        hint: 'Enter your name',
                        controller: _nameController,
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          color: _primaryTeal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        label: 'Email Address',
                        hint: 'Enter your email',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: _primaryTeal,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 34),
            _sectionLabel(
              icon: Icons.volunteer_activism_rounded,
              title: 'Donation Amount',
              subtitle:
                  'Choose a suggested amount or enter a custom contribution.',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: _buildTextField(
                    label: 'Custom Amount',
                    hint: 'Enter amount',
                    controller: _customAmountController,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icon(
                      Icons.payments_outlined,
                      color: _primaryTeal,
                    ),
                  ),
                ),
                _buildAmountButton('P50'),
                _buildAmountButton('P100'),
                _buildAmountButton('P500'),
                _buildAmountButton('P1000'),
              ],
            ),
            const SizedBox(height: 34),
            _sectionLabel(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Payment Method',
              subtitle:
                  'Select the channel you will use to send your donation.',
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final mobile = constraints.maxWidth < 720;

                if (mobile) {
                  return Column(
                    children: [
                      _paymentButton(
                        method: 'GCASH',
                        icon: Icons.phone_android_rounded,
                        subtitle: 'Mobile wallet transfer',
                      ),
                      const SizedBox(height: 14),
                      _paymentButton(
                        method: 'BANK TRANSFER',
                        icon: Icons.account_balance_rounded,
                        subtitle: 'Manual bank transfer',
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: _paymentButton(
                        method: 'GCASH',
                        icon: Icons.phone_android_rounded,
                        subtitle: 'Mobile wallet transfer',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _paymentButton(
                        method: 'BANK TRANSFER',
                        icon: Icons.account_balance_rounded,
                        subtitle: 'Manual bank transfer',
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 22),
              _messageBox(_errorMessage!),
            ],
            const SizedBox(height: 28),
            SizedBox(
              height: 58,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleDonate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentBlue,
                  disabledBackgroundColor: _accentBlue.withOpacity(0.55),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
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
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Row(
                          key: ValueKey('text'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_forward_rounded, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'CONTINUE TO PROOF UPLOAD',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginRequiredCard() {
    return Container(
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFFE3EEF4)),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline_rounded, color: _primaryTeal, size: 46),
          const SizedBox(height: 18),
          Text(
            'Please log in to donate',
            style: TextStyle(
              color: _darkTeal,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Sign in first so your donation can be properly recorded and verified.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey.shade600, height: 1.6),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryTeal,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text(
              'Go to Login',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFD8EAF0)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: _primaryTeal),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'After submitting your donation details, you will upload your proof of payment. Your donation will remain pending until it is reviewed.',
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDonate() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final amount = _parseAmount();

    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your name or organization name.';
      });
      return;
    }

    if (email.isEmpty || !_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
      });
      return;
    }

    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Please choose or enter a valid donation amount.';
      });
      return;
    }

    if (_selectedPaymentChannel == null) {
      setState(() {
        _errorMessage = 'Please select a payment method.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('donations')
          .insert({
            'donor_id': user.id,
            'name': name,
            'email': email,
            'amount': amount,
            'payment_method': _selectedPaymentChannel,
            'status': 'pending',
          })
          .select()
          .single();

      final donationId = response['id'];

      if (!mounted) return;

      setState(() => _isLoading = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProofUploadPage(
            donationId: donationId,
            paymentMethod: _selectedPaymentChannel!,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: _surface,
      appBar: _buildHeader(),
      body: SingleChildScrollView(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                _buildHero(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 46,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        children: [
                          _buildPageIntro(),
                          const SizedBox(height: 28),
                          _buildVerificationProgress(),
                          const SizedBox(height: 28),
                          user == null
                              ? _buildLoginRequiredCard()
                              : _buildDonationForm(),
                          const SizedBox(height: 24),
                          _buildReminderStrip(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
