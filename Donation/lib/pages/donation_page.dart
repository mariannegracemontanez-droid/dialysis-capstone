import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/brand.dart';
import '../widgets/decor.dart';
import '../widgets/donation_steps.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'landing_page.dart';
import 'login_page.dart';

/// Step two of the donation journey: amount, destination and payment
/// channel.
///
/// Everything that decides what a donation *is* - validation, the three
/// allocation methods, the equal-split arithmetic and the write to the
/// donation records - is unchanged from the original page and marked below.
/// This file only changes how that form looks and reads.
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

  // The page's original colour slots, now pointing at the shared palette so
  // this form matches the rest of the site. `_accentBlue` drives the submit
  // button, which is why it is the same coral used for every other donate
  // action on the site.
  final Color _darkTeal = Brand.brandDeep;
  final Color _primaryTeal = Brand.teal;
  final Color _accentBlue = Brand.coral;
  final Color _surface = Brand.canvas;
  final Color _softBlue = Brand.sky;
  final Color _fieldFill = const Color(0xFFF4F8FB);

  @override
  void initState() {
    super.initState();

    // Prefilled for a registered donation only. An anonymous donation must
    // not pick up the signed-in account's details just because a session
    // happens to exist -- choosing "Donate Anonymously" while logged in
    // stays anonymous, and none of the account's information is prefilled,
    // shown or submitted.
    final user = Supabase.instance.client.auth.currentUser;

    if (!widget.isAnonymous && user != null) {
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

  /// Returns to the landing page and clears the whole donation journey from
  /// the navigation stack.
  ///
  /// Used both when a donation has been completed and when this page is the
  /// only route left (see [_buildHeader]). Replacing the stack rather than
  /// popping a fixed number of routes is what keeps this correct no matter
  /// how the donor arrived -- straight from the landing page, by way of the
  /// details page, or through the login step, which leaves this page as the
  /// sole route. It also means Back can never re-enter a finished or
  /// abandoned donation.
  void _goToLandingPage() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  // ------------------------------------------------------- presentation

  PreferredSizeWidget _buildHeader() {
    return AppBar(
      backgroundColor: Brand.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 74,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Brand.brandDeep),
        tooltip: 'Back',
        // Normal back behaviour whenever there is a route to go back to.
        // When there is not -- signing in mid-donation replaces the stack,
        // so this page can be the only route -- popping would leave the app
        // with no route at all, so fall back to the landing page instead.
        onPressed: () {
          final navigator = Navigator.of(context);

          if (navigator.canPop()) {
            navigator.pop();
          } else {
            _goToLandingPage();
          }
        },
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Image.asset(
            'lib/assets/image/CureNurture_logo.png',
            width: 36,
            height: 36,
            semanticLabel: 'CureNurture logo',
          ),
          const SizedBox(width: 10),
          const Text(
            'CureNurture',
            style: TextStyle(
              fontFamily: Brand.displayFont,
              color: Brand.brandDeep,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Brand.border),
      ),
    );
  }

  Widget _animatedEntry({required Widget child, int delay = 0}) {
    return Reveal(delayMs: delay, child: child);
  }

  /// Banded page header carrying the step indicator, so a donor can always
  /// see where they are in the journey and what is still ahead.
  Widget _buildHero() {
    final width = MediaQuery.of(context).size.width;
    final mobile = Brand.isMobile(width);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: Brand.brandGradient),
      child: Stack(
        children: [
          const Positioned.fill(child: FlowBackdrop(opacity: 0.85)),
          Padding(
            padding: EdgeInsets.symmetric(vertical: mobile ? 40 : 56),
            child: ContentColumn(
              maxWidth: 1000,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Eyebrow(
                      widget.isAnonymous
                          ? 'Anonymous donation'
                          : 'Donor account',
                      light: true,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Complete your donation.',
                    textAlign: TextAlign.center,
                    style: Brand.display(
                      mobile ? 30 : 42,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 660),
                      child: Text(
                        'Choose an amount, decide which dialysis centre it '
                        'supports, and tell us how you will be sending it.',
                        textAlign: TextAlign.center,
                        style: Brand.body(
                          mobile ? 14.5 : 16,
                          color: Colors.white.withValues(alpha: 0.84),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 34),
                  const DonationSteps(current: 1, light: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? accent,
    Color? accentSoft,
  }) {
    final tone = accent ?? _primaryTeal;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: Brand.iconBox(accentSoft ?? Brand.tealSoft, radius: 15),
          child: Icon(icon, color: tone, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Brand.heading(18)),
              const SizedBox(height: 4),
              Text(subtitle, style: Brand.body(13.5, color: Brand.textMuted)),
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
    String? prefixText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        color: _darkTeal,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        prefixText: prefixText,
        prefixStyle: TextStyle(
          color: _darkTeal,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        filled: true,
        fillColor: _fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: const TextStyle(color: Brand.textMuted),
        floatingLabelStyle: const TextStyle(
          color: Brand.brand,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: Brand.textMuted.withValues(alpha: 0.6)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Brand.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Brand.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Brand.brand, width: 2),
        ),
      ),
    );
  }

  /// Shared look for the three kinds of choice in this form - payment
  /// channel, allocation method and dialysis centre. Each one still just
  /// reports a tap to the selection handler it was given.
  Widget _choiceTile({
    required bool isSelected,
    required VoidCallback onTap,
    required IconData icon,
    required String title,
    required String subtitle,
    required String semanticLabel,
    bool compact = false,
  }) {
    return HoverLift(
      lift: 3,
      builder: (context, hovered) {
        return Semantics(
          inMutuallyExclusiveGroup: true,
          selected: isSelected,
          button: true,
          label: semanticLabel,
          child: InkWell(
            borderRadius: BorderRadius.circular(compact ? 18 : 20),
            focusColor: Brand.brand.withValues(alpha: 0.10),
            hoverColor: Colors.transparent,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: EdgeInsets.all(compact ? 14 : 17),
              decoration: BoxDecoration(
                color: isSelected ? Brand.sky : Brand.white,
                borderRadius: BorderRadius.circular(compact ? 18 : 20),
                border: Border.all(
                  color: isSelected
                      ? Brand.brand
                      : (hovered
                            ? Brand.brand.withValues(alpha: 0.40)
                            : Brand.border),
                  width: isSelected ? 2 : 1.2,
                ),
                boxShadow: isSelected || hovered ? Brand.shadowSoft : null,
              ),
              child: Row(
                children: [
                  Container(
                    height: compact ? 38 : 44,
                    width: compact ? 38 : 44,
                    decoration: Brand.iconBox(
                      isSelected ? Brand.white : _softBlue,
                      radius: 14,
                    ),
                    child: Icon(
                      icon,
                      color: Brand.brand,
                      size: compact ? 19 : 22,
                    ),
                  ),
                  SizedBox(width: compact ? 11 : 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Brand.label(
                            compact ? 14 : 15,
                            color: Brand.textStrong,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: Brand.body(12.5, color: Brand.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 24,
                    width: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Brand.brand : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? Brand.brand : Brand.borderStrong,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _paymentButton({
    required String method,
    required IconData icon,
    required String subtitle,
  }) {
    final isSelected = _selectedPaymentChannel == method;

    return _choiceTile(
      isSelected: isSelected,
      onTap: () => _selectPaymentChannel(method),
      icon: icon,
      title: method,
      subtitle: subtitle,
      semanticLabel: 'Pay by $method. $subtitle',
    );
  }

  Widget _allocationButton({
    required String method,
    required IconData icon,
    required String subtitle,
  }) {
    final isSelected = _selectedAllocationMethod == method;

    return _choiceTile(
      isSelected: isSelected,
      onTap: () => _selectAllocationMethod(method),
      icon: icon,
      title: method,
      subtitle: subtitle,
      semanticLabel: '$method. $subtitle',
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

    return _choiceTile(
      isSelected: isSelected,
      onTap: () => _selectCenter(centerId),
      icon: Icons.local_hospital_rounded,
      title: name,
      subtitle: location,
      semanticLabel: 'Donate to $name${location.isEmpty ? '' : ', $location'}',
      compact: true,
    );
  }

  Widget _messageBox(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.coralSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.coral.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Brand.coral, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              // Announced to assistive tech as soon as it appears, so a
              // validation failure is not silent for screen-reader users.
              style: Brand.label(14, color: Brand.coral),
            ),
          ),
        ],
      ),
    );
  }

  /// An inset panel used for the detail that appears under a chosen
  /// allocation method.
  Widget _allocationDetail({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.tealSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.teal.withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }

  Widget _buildDonationForm() {
    final width = MediaQuery.of(context).size.width;
    final mobile = Brand.isMobile(width);

    return _animatedEntry(
      delay: 100,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(mobile ? 22 : 36),
        decoration: BoxDecoration(
          color: Brand.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Brand.border),
          boxShadow: Brand.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              icon: widget.isAnonymous
                  ? Icons.visibility_off_rounded
                  : Icons.person_outline_rounded,
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
                  final narrow = constraints.maxWidth < 720;

                  if (narrow) {
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
              subtitle: 'Enter the amount you would like to contribute.',
              accent: Brand.coral,
              accentSoft: Brand.coralSoft,
            ),
            const SizedBox(height: 18),

            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: _buildTextField(
                label: 'Custom Amount',
                hint: 'Enter amount',
                controller: _customAmountController,
                keyboardType: TextInputType.number,
                prefixText: '₱  ',
              ),
            ),

            const SizedBox(height: 34),

            _sectionLabel(
              icon: Icons.alt_route_rounded,
              title: 'Fund Allocation',
              subtitle:
                  'Choose how you would like your donation to be distributed.',
              accent: Brand.brand,
              accentSoft: Brand.sky,
            ),
            const SizedBox(height: 18),

            Column(
              children: [
                _allocationButton(
                  method: 'Specific Dialysis Center',
                  icon: Icons.location_on_outlined,
                  subtitle: 'Choose exactly which center receives your donation.',
                ),
                const SizedBox(height: 12),
                _allocationButton(
                  method: 'Randomly Assign a Dialysis Center',
                  icon: Icons.shuffle_rounded,
                  subtitle: 'A dialysis center will be randomly selected to receive your donation.',
                ),
                const SizedBox(height: 12),
                _allocationButton(
                  method: 'Distribute Donation Equally Among All Centers',
                  icon: Icons.balance_outlined,
                  subtitle: 'Your donation will be shared equally across all centers.',
                ),
              ],
            ),

            if (_selectedAllocationMethod == 'Specific Dialysis Center')
              _allocationDetail(
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
                        style: Brand.body(13, color: Brand.textMuted),
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

            if (_selectedAllocationMethod ==
                'Randomly Assign a Dialysis Center')
              _allocationDetail(
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
                        style: Brand.label(13, color: Brand.brandDeep),
                      ),
                    ),
                  ],
                ),
              ),

            if (_selectedAllocationMethod ==
                'Distribute Donation Equally Among All Centers')
              _allocationDetail(
                child: Row(
                  children: [
                    Icon(Icons.balance_outlined, color: _primaryTeal, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: _buildEqualDistributionSummary()),
                  ],
                ),
              ),

            const SizedBox(height: 34),

            _sectionLabel(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Payment Method',
              subtitle:
                  'Select the channel you will use to send your donation.',
              accent: Brand.mint,
              accentSoft: Brand.mintSoft,
            ),
            const SizedBox(height: 18),

            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;

                if (narrow) {
                  return Column(
                    children: [
                      _paymentButton(
                        method: 'GCASH',
                        icon: Icons.phone_android_rounded,
                        subtitle: 'Mobile wallet transfer',
                      ),
                      const SizedBox(height: 12),
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

            // The strongest element on the page, matching the Donate action
            // everywhere else on the site.
            SizedBox(
              height: 60,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleDonate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentBlue,
                  disabledBackgroundColor: _accentBlue.withValues(alpha: 0.45),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _isLoading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Row(
                          key: ValueKey('text'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.favorite_rounded, size: 21),
                            SizedBox(width: 10),
                            Text('SUBMIT DONATION'),
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

        // What the donor actually typed into Full Name / Organization wins.
        // The field is editable and asks them to "Enter your name", so a
        // value entered there is the name this donation is recorded under --
        // it lets a donor give under an organisation's name, or a different
        // spelling, without altering their account.
        //
        // Left blank, this falls back to exactly the chain it always used:
        // the account's profile name, then the account email, then a generic
        // label -- so a donor who ignores the field is recorded as before.
        // Account identification (donor_id) and the donor's email are taken
        // from the authenticated account either way, and are untouched here.
        final enteredName = _nameController.text.trim();

        donorName = enteredName.isNotEmpty
            ? enteredName
            : (profile?['full_name'] as String?)?.trim() ?? '';

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
            'status': 'verified',
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

      // Donations are voluntary and no longer require a payment receipt or any
      // review before they count -- the donation (and its center routing,
      // above) is already fully recorded at this point, so we just confirm
      // that to the donor instead of asking for proof of payment.
      // Not dismissible on purpose: closing this by tapping the barrier or
      // pressing Escape used to drop the donor back onto a still-filled form
      // that could be submitted a second time. "Back to Home" below is the
      // only way out of it.
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Thank You!'),
            content: const Text(
              'Your donation has been recorded successfully. We truly appreciate your generosity.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Back to Home'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      // The donation is fully recorded by this point; all that is left is to
      // put the donor back on the landing page. This runs once the dialog has
      // actually closed and -- because the dialog is not dismissible -- only
      // ever by way of the "Back to Home" button above.
      _goToLandingPage();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to continue with your donation. ${e.toString()}';
      });
    }
  }

  Widget _buildLoginRequiredCard() {
    final width = MediaQuery.of(context).size.width;
    final mobile = Brand.isMobile(width);

    return _animatedEntry(
      child: Container(
        padding: EdgeInsets.all(mobile ? 26 : 38),
        decoration: BoxDecoration(
          color: Brand.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Brand.border),
          boxShadow: Brand.shadowCard,
        ),
        child: Column(
          children: [
            Container(
              height: 68,
              width: 68,
              decoration: Brand.iconBox(Brand.sky, radius: 22),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Brand.brand,
                size: 33,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Please log in to donate',
              textAlign: TextAlign.center,
              style: Brand.heading(mobile ? 21 : 24),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                'Sign in first so your donation can be properly recorded and '
                'verified under your name.',
                textAlign: TextAlign.center,
                style: Brand.body(14.5),
              ),
            ),
            const SizedBox(height: 26),
            DonateButton(
              label: 'Go to Login',
              icon: Icons.login_rounded,
              expand: mobile,
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// What actually happens on submit.
  ///
  /// The wording here follows the behaviour in [_handleDonate]: the record
  /// is written and confirmed straight away, and the transfer itself is
  /// made by the donor through the channel they picked above. There is no
  /// separate proof-upload or review step in this flow.
  Widget _buildReminderStrip() {
    return _animatedEntry(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Brand.sky,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Brand.brand.withValues(alpha: 0.16)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: Brand.iconBox(Brand.white, radius: 14),
              child: const Icon(
                Icons.info_outline_rounded,
                color: Brand.brand,
                size: 21,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What happens when you submit',
                    style: Brand.label(15, color: Brand.textStrong),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your donation is saved to CureNurture’s donation records '
                    'along with the amount, the payment channel you selected '
                    'and the dialysis centre it is directed to. You will see a '
                    'confirmation as soon as it has been recorded.',
                    style: Brand.body(13.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final width = MediaQuery.of(context).size.width;
    final mobile = Brand.isMobile(width);

    return Scaffold(
      backgroundColor: _surface,
      appBar: _buildHeader(),
      body: RevealScope(
        child: SingleChildScrollView(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  _buildHero(),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: mobile ? 32 : 46,
                    ),
                    child: ContentColumn(
                      maxWidth: 1000,
                      child: Column(
                        children: [
                          (!widget.isAnonymous && user == null)
                              ? _buildLoginRequiredCard()
                              : _buildDonationForm(),
                          const SizedBox(height: 22),
                          _buildReminderStrip(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
