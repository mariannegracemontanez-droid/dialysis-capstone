import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import 'proof_page.dart';

class DonationPage extends StatefulWidget {
  const DonationPage({
    super.key,
    this.isAnonymous = false,
  });

  final bool isAnonymous;

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage>
    with SingleTickerProviderStateMixin {
    
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _customAmountController = TextEditingController();

  String? _selectedPaymentChannel;
  String? _selectedAllocationMethod;
  String? _selectedCenterId;
  bool _isLoading = false;
  bool _isLoadingCenters = false;
  List<Map<String, dynamic>> _dialysisCenters = [];
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

    _loadDialysisCenters();

    _customAmountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    setState(() {});
  }

  Future<void> _loadDialysisCenters() async {
    setState(() {
      _isLoadingCenters = true;
    });

    try {
      final response = await Supabase.instance.client
          .from('clinics')
          .select('id, name, address, city, status')
          .or('status.is.null,status.neq.closed')
          .order('name', ascending: true);

      if (!mounted) return;

      setState(() {
        _dialysisCenters = List<Map<String, dynamic>>.from(response);
        _isLoadingCenters = false;

        if (_selectedAllocationMethod == 'Randomly Assign a Dialysis Center' &&
            _selectedCenterId == null) {
          _selectedCenterId = _pickRandomCenterId();
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingCenters = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _customAmountController.removeListener(_onAmountChanged);
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

  void _selectAllocationMethod(String method) {
    setState(() {
      _selectedAllocationMethod = method;
      _selectedCenterId = (method == 'Randomly Assign a Dialysis Center' && !_isLoadingCenters)
          ? _pickRandomCenterId()
          : null;
    });
  }

  String? _pickRandomCenterId() {
    if (_dialysisCenters.isEmpty) return null;
    return _dialysisCenters[Random().nextInt(_dialysisCenters.length)]['id']
        ?.toString();
  }

  String? _centerNameById(String? centerId) {
    if (centerId == null) return null;
    for (final center in _dialysisCenters) {
      if (center['id']?.toString() == centerId) {
        return center['name']?.toString();
      }
    }
    return null;
  }

  // Splits [amount] into [centerCount] shares using integer centavos so the
  // shares always sum back to exactly [amount], even when it doesn't divide evenly.
  List<double> _computeEqualShares(double amount, int centerCount) {
    if (centerCount <= 0) return [];

    final totalCentavos = (amount * 100).round();
    final baseCentavos = totalCentavos ~/ centerCount;
    final remainder = totalCentavos % centerCount;

    return List<double>.generate(centerCount, (i) {
      final centavos = baseCentavos + (i < remainder ? 1 : 0);
      return centavos / 100;
    });
  }

  Widget _buildEqualDistributionSummary() {
    final textStyle = TextStyle(
      color: _darkTeal,
      fontWeight: FontWeight.w700,
      fontSize: 12.5,
    );

    if (_isLoadingCenters) {
      return Text('Calculating equal distribution...', style: textStyle);
    }

    if (_dialysisCenters.isEmpty) {
      return Text(
        'No dialysis centers are currently available for equal distribution.',
        style: textStyle,
      );
    }

    final amount = _parseAmount();
    if (amount == null || amount <= 0) {
      return Text(
        'Enter a donation amount to see the equal distribution breakdown.',
        style: textStyle,
      );
    }

    final centerCount = _dialysisCenters.length;
    final shares = _computeEqualShares(amount, centerCount);
    final minShare = shares.reduce((a, b) => a < b ? a : b);
    final maxShare = shares.reduce((a, b) => a > b ? a : b);

    final perCenterText = minShare == maxShare
        ? '₱${minShare.toStringAsFixed(2)} per center'
        : '₱${minShare.toStringAsFixed(2)}–₱${maxShare.toStringAsFixed(2)} per center';

    return Text(
      '$perCenterText × $centerCount ${centerCount == 1 ? 'center' : 'centers'} = '
      '₱${amount.toStringAsFixed(2)} total',
      style: textStyle,
    );
  }

  void _selectCenter(String centerId) {
    setState(() {
      _selectedCenterId = centerId;
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

  Widget _allocationButton({
    required String method,
    required IconData icon,
    required String subtitle,
  }) {
    final isSelected = _selectedAllocationMethod == method;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _selectAllocationMethod(method),
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

  Widget _centerButton(Map<String, dynamic> center) {
    final centerId = center['id']?.toString() ?? '';
    final name = center['name']?.toString() ?? 'Unnamed Center';
    final location =
        (center['address']?.toString().isNotEmpty ?? false)
        ? center['address'].toString()
        : (center['city']?.toString() ?? '');
    final isSelected = _selectedCenterId == centerId;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _selectCenter(centerId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _darkTeal : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _darkTeal : const Color(0xFFDCE8EE),
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
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.16) : _softBlue,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.local_hospital_outlined,
                color: isSelected ? Colors.white : _primaryTeal,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : _darkTeal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      location,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white.withOpacity(0.72)
                            : Colors.blueGrey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: isSelected ? Colors.white : Colors.blueGrey.shade300,
              size: 20,
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
            title: widget.isAnonymous
                ? 'Anonymous Donation'
                : 'Donor Information',
            subtitle: widget.isAnonymous
                ? 'Your donation will not be associated with a donor account.'
                : 'These details help us identify and record your contribution.',
          ),
          const SizedBox(height: 18),

          if (!widget.isAnonymous) ...[
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
          ] else
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
            icon: Icons.volunteer_activism_outlined,
            title: 'Fund Allocation',
            subtitle:
                'Choose how you would like your donation to be distributed.',
          ),
          const SizedBox(height: 18),

          Column(
            children: [
              _allocationButton(
                method: 'Specific Dialysis Center',
                icon: Icons.location_on_outlined,
                subtitle: 'Choose exactly which center receives your donation.',
              ),
              const SizedBox(height: 14),
              _allocationButton(
                method: 'Randomly Assign a Dialysis Center',
                icon: Icons.shuffle_rounded,
                subtitle: 'A dialysis center will be randomly selected to receive your donation.',
              ),
              const SizedBox(height: 14),
              _allocationButton(
                method: 'Distribute Donation Equally Among All Centers',
                icon: Icons.balance_outlined,
                subtitle: 'Your donation will be shared equally across all centers.',
              ),
            ],
          ),

          if (_selectedAllocationMethod == 'Specific Dialysis Center') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isLoadingCenters
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    )
                  : _dialysisCenters.isEmpty
                  ? Text(
                      'No dialysis centers are available right now.',
                      style: TextStyle(
                        color: Colors.blueGrey.shade500,
                        fontSize: 12.5,
                      ),
                    )
                  : Column(
                      children: [
                        for (int i = 0; i < _dialysisCenters.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _centerButton(_dialysisCenters[i]),
                        ],
                      ],
                    ),
            ),
          ],

          if (_selectedAllocationMethod ==
              'Randomly Assign a Dialysis Center') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(Icons.shuffle_rounded, color: _primaryTeal, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isLoadingCenters
                          ? 'Selecting a dialysis center...'
                          : (_centerNameById(_selectedCenterId) != null
                                ? 'Randomly assigned to: ${_centerNameById(_selectedCenterId)}'
                                : 'No dialysis centers are currently available.'),
                      style: TextStyle(
                        color: _darkTeal,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_selectedAllocationMethod ==
              'Distribute Donation Equally Among All Centers') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(Icons.balance_outlined, color: _primaryTeal, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: _buildEqualDistributionSummary()),
                ],
              ),
            ),
          ],

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
              onPressed: _isLoading ? null :_handleDonate,
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

Future<void> _handleDonate() async {
  setState(() {
    _errorMessage = null;
  });

  // Validate donation amount
  final amount = _parseAmount();

  if (amount == null || amount <= 0) {
    setState(() {
      _errorMessage = 'Please enter a valid donation amount.';
    });
    return;
  }

  // Validate fund allocation selection
  if (_selectedAllocationMethod == null) {
    setState(() {
      _errorMessage = 'Please select a fund allocation option.';
    });
    return;
  }

  // Validate dialysis center selection
  if (_selectedAllocationMethod == 'Specific Dialysis Center' &&
      _selectedCenterId == null) {
    setState(() {
      _errorMessage = 'Please select a dialysis center.';
    });
    return;
  }

  // Validate random center assignment
  if (_selectedAllocationMethod == 'Randomly Assign a Dialysis Center' &&
      _selectedCenterId == null) {
    setState(() {
      _errorMessage = 'No dialysis centers are currently available for random assignment.';
    });
    return;
  }

  // Validate equal distribution has eligible centers
  if (_selectedAllocationMethod == 'Distribute Donation Equally Among All Centers' &&
      _dialysisCenters.isEmpty) {
    setState(() {
      _errorMessage = 'No dialysis centers are currently available for equal distribution.';
    });
    return;
  }

  // Validate payment method
  if (_selectedPaymentChannel == null) {
    setState(() {
      _errorMessage = 'Please select a payment method.';
    });
    return;
  }

  // For registered donors, make sure they are logged in.
  final user = Supabase.instance.client.auth.currentUser;

  if (!widget.isAnonymous && user == null) {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Login Required'),
          content: const Text(
            'Please log in to your registered donor account before continuing.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const LoginPage(),
                  ),
                  (route) => false,
                );
              },
              child: const Text('Back to Login'),
            ),
          ],
        );
      },
    );

    return;
  }

  setState(() {
    _isLoading = true;
  });

  try {
    String? donorId;
    String donorName;
    String donorEmail;

    if (widget.isAnonymous) {
  // Anonymous donation:
  // Do not store the donor's account information.
  donorId = null;
  donorName = '';
  donorEmail = '';
} else  {
      // Registered donation:
      // Use the currently logged-in account.
      donorId = user!.id;

      donorEmail = user.email ?? '';

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      donorName = (profile?['full_name'] as String?)?.trim() ?? '';

      if (donorName.isEmpty) {
        donorName = user.email ?? 'Registered Donor';
      }

      if (donorEmail.isEmpty || !_isValidEmail(donorEmail)) {
        throw Exception('The registered account does not have a valid email.');
      }
    }

    // Save the donation record.
    //
    // Specific and Random both resolve to exactly one center, so they use
    // the existing donations.clinic_id column directly -- the donation is
    // immediately associated with that center, with no Super Admin step.
    // Equal Distribution has no single center, so clinic_id is left null on
    // the parent row (amount is still the full total); the per-center
    // breakdown is saved separately below, into donation_allocations, so
    // each center admin can see their own share.
    final isEqualDistribution = _selectedAllocationMethod ==
        'Distribute Donation Equally Among All Centers';

    // Records which of the three allocation methods the donor picked, so
    // Super Admin's review screen can show it truthfully -- a specific-
    // center pick and a random-center pick both end up as the same
    // donations.clinic_id, so that column alone can't tell them apart.
    final allocationType = isEqualDistribution
        ? 'equal_distribution'
        : (_selectedAllocationMethod == 'Randomly Assign a Dialysis Center'
              ? 'random_center'
              : 'specific_center');

    final response = await Supabase.instance.client
        .from('donations')
        .insert({
          'donor_id': donorId,
          'name': widget.isAnonymous ? null : donorName,
          'email': widget.isAnonymous ? null : donorEmail,
          'amount': amount,
          'payment_method': _selectedPaymentChannel,
          'status': 'pending',
          'clinic_id': isEqualDistribution ? null : _selectedCenterId,
          'allocation_type': allocationType,
        })
        .select('id')
        .single();

    final donationId = response['id'].toString();

    if (isEqualDistribution) {
      // Reuses the exact shares already calculated and shown to the donor
      // in the Fund Allocation summary -- not recalculated here.
      final shares = _computeEqualShares(amount, _dialysisCenters.length);

      await Supabase.instance.client.from('donation_allocations').insert([
        for (int i = 0; i < _dialysisCenters.length; i++)
          {
            'donation_id': donationId,
            'clinic_id': _dialysisCenters[i]['id'],
            'amount': shares[i],
          },
      ]);
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    // Continue to proof upload.
    Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => ProofUploadPage(
      donationId: donationId,
      paymentMethod: _selectedPaymentChannel!,
    ),
  ),
);
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _errorMessage = 'Unable to continue with your donation. ${e.toString()}';
    });
  }
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
                          (!widget.isAnonymous && user == null)
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