import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/payment_config.dart';
import '../services/donation_checkout_service.dart';
import '../theme/brand.dart';
import '../widgets/decor.dart';
import '../widgets/donation_steps.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import '../widgets/unfinished_donation_dialog.dart';
import 'checkout_page.dart';
import 'landing_page.dart';
import 'login_page.dart';

/// Largest amount `donations.amount numeric(12, 2)` can hold.
const double maxDonationAmount = 9999999999.99;

/// Parses the custom amount field: plain digits with at most two decimal
/// places (centavos), up to [maxDonationAmount]. Returns null for anything
/// else. `double.tryParse` alone also accepted "NaN" (which slipped past the
/// `amount <= 0` check), "Infinity", "1e3" and sub-centavo amounts.
double? parseDonationAmount(String input) {
  final value = input.trim();
  if (!RegExp(r'^(\d+(\.\d{0,2})?|\.\d{1,2})$').hasMatch(value)) return null;

  final amount = double.parse(value);
  return amount > maxDonationAmount ? null : amount;
}

/// Step two of the donation journey: amount, destination and payment
/// channel.
///
/// This page only COLLECTS the donor's choices and shows a preview. The
/// donation itself -- amount validation, centre eligibility, the random
/// pick, the equal split and the database write -- is made server-side by
/// `create_donation_checkout()` (see supabase_migration_donation_sandbox.sql),
/// after which the donor continues to [CheckoutPage].
class DonationPage extends StatefulWidget {
  const DonationPage({
    super.key,
    this.isAnonymous = false,
    this.service,
    this.continueUnfinished = false,
  });

  final bool isAnonymous;

  /// Set when the donor already chose "Continue donation" (after logging
  /// in): the unfinished donation is reopened without asking again.
  final bool continueUnfinished;

  /// Injectable for tests; defaults to the live Supabase client.
  final DonationCheckoutService? service;

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage>
    with SingleTickerProviderStateMixin {

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _customAmountController = TextEditingController();

  // GCash is the only channel while Bank Transfer is hidden, so it starts
  // selected.
  String? _selectedPaymentChannel = kBankTransferEnabled ? null : kGcashMethod;
  String? _selectedAllocationMethod;
  String? _selectedCenterId;
  bool _isLoading = false;
  bool _isLoadingCenters = false;
  List<Map<String, dynamic>> _dialysisCenters = [];
  String? _errorMessage;

  late final DonationCheckoutService _service =
      widget.service ?? DonationCheckoutService();
  DonationPaymentSettings _settings = DonationPaymentSettings.fallback;

  /// The current submit attempt; reused when the donor retries the same
  /// donation so the server returns it instead of creating a duplicate.
  CheckoutRequest? _pendingRequest;

  /// An unfinished checkout from earlier in this browser (e.g. before a
  /// refresh), offered for resuming.
  DonationCheckout? _resumable;
  String? _resumableSecret;

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
    _loadSettings();
    _loadResumableCheckout(prompt: true);

    _customAmountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    setState(() {});
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _service.fetchSettings();
      if (!mounted) return;
      setState(() => _settings = settings);
    } catch (_) {
      // Keep the defaults; the server re-checks everything on submit.
    }
  }

  /// Offers to resume a checkout left open in this browser (for example
  /// after a refresh). Its recipients come back from the server unchanged.
  ///
  /// While that checkout is open, its original request is kept (also across a
  /// refresh), so continuing again with the same details returns the SAME
  /// donation -- the random centre and the equal split are never redone. Once
  /// the donation is finished or cancelled, the request is dropped.
  ///
  /// Only a donation that belongs to this flow is offered: the anonymous flow
  /// gets anonymous donations, a signed-in donor gets only their own. When
  /// [prompt] is set (the page was just opened), the donor is asked once
  /// whether to continue it or start over.
  Future<void> _loadResumableCheckout({bool prompt = false}) async {
    final pending = await _service.loadPending();
    if (pending == null) {
      if (mounted && !_isLoading) setState(() => _pendingRequest = null);
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (!pendingBelongsTo(pending, anonymousFlow: widget.isAnonymous, userId: userId)) {
      // Started by someone else in this browser (or by the other flow):
      // never shown here, and left untouched for its owner.
      return;
    }

    DonationCheckout checkout;
    try {
      checkout = await _service.fetchCheckout(pending.id, pending.secret);
    } catch (_) {
      await _service.clearPending();
      if (mounted) setState(() => _pendingRequest = null);
      return;
    }
    if (!mounted) return;
    if (!checkout.isOpen) {
      await _service.clearPending();
      if (mounted) setState(() => _pendingRequest = null);
      return;
    }
    setState(() {
      _resumable = checkout;
      _resumableSecret = pending.secret;
      _pendingRequest = pending.request ?? _pendingRequest;
    });

    if (!prompt || _resumePrompted) return;
    _resumePrompted = true;

    if (widget.continueUnfinished) {
      _restoreForm(checkout);
      await _openCheckout(checkout, pending.secret);
      return;
    }

    final choice = await showUnfinishedDonationDialog(context, checkout);
    if (!mounted) return;
    switch (choice) {
      case UnfinishedDonationChoice.continueDonation:
        _restoreForm(checkout);
        await _openCheckout(checkout, pending.secret);
      case UnfinishedDonationChoice.startOver:
        await _startOver(checkout, pending.secret);
      case null:
        break; // left as is; the "unfinished donation" card stays available
    }
  }

  bool _resumePrompted = false;

  /// Puts the unfinished donation's details back into the form: amount,
  /// allocation option and (for a specific centre) the centre. The recipients
  /// and amounts themselves come from the server and are shown on review.
  void _restoreForm(DonationCheckout c) {
    setState(() {
      _customAmountController.text = centavosToAmountInput(c.amountCentavos);
      _selectedAllocationMethod = switch (c.mode) {
        DonationMode.specificCenter => 'Specific Dialysis Center',
        DonationMode.randomCenter => 'Randomly Assign a Dialysis Center',
        DonationMode.allCenters => 'Distribute Donation Equally Among All Centers',
        null => _selectedAllocationMethod,
      };
      _selectedCenterId = c.mode == DonationMode.specificCenter && c.allocations.isNotEmpty
          ? c.allocations.first.clinicId
          : null;
      _errorMessage = null;
    });
  }

  /// Opens the review & pay step for an existing (unfinished) donation.
  Future<void> _openCheckout(DonationCheckout checkout, String secret) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          checkout: checkout,
          clientSecret: secret,
          service: _service,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _resumable = null);
    _loadResumableCheckout();
  }

  /// Discards an unfinished donation after the donor confirmed it: cancels it
  /// on the server (nothing was charged) and resets the form.
  Future<void> _startOver(DonationCheckout checkout, String secret) async {
    try {
      await _service.cancel(checkout.donationId, secret);
    } catch (_) {
      // Already closed on the server; just forget it here.
    }
    await _service.clearPending();
    if (!mounted) return;
    setState(() {
      _resumable = null;
      _resumableSecret = null;
      _pendingRequest = null;
      _customAmountController.clear();
      _selectedAllocationMethod = null;
      _selectedCenterId = null;
      _errorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Donation ${checkout.reference} was cancelled. You can start a new donation.'),
        backgroundColor: Brand.brand,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// The same eligible-centre list the server allocates from
  /// (`donation_eligible_centers()`, i.e. every centre not marked closed),
  /// in the server's allocation order.
  Future<void> _loadDialysisCenters() async {
    setState(() {
      _isLoadingCenters = true;
    });

    try {
      final centers = await _service.fetchEligibleCenters();

      if (!mounted) return;

      setState(() {
        _dialysisCenters = sortCentersForAllocation(centers);
        _isLoadingCenters = false;

        // A previously chosen centre that is no longer eligible is cleared.
        if (_selectedCenterId != null &&
            !_dialysisCenters.any((c) => c['id']?.toString() == _selectedCenterId)) {
          _selectedCenterId = null;
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
      // The random centre is picked by the server when the donation is
      // created -- never here -- so only a specific pick is kept locally.
      _selectedCenterId = null;
    });
  }

  /// Preview of the Donate-to-All split. The server recomputes it with the
  /// same rule when the donation is created, and the checkout page shows
  /// the server's figures before payment.
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

    final centerCount = _dialysisCenters.length;
    final centavos = _parseCentavos();
    if (centavos == null || centavos <= 0) {
      return Text(
        'Your donation will be split equally among $centerCount eligible '
        '${centerCount == 1 ? 'center' : 'centers'}. Enter an amount to see '
        'each center\'s share.',
        style: textStyle,
      );
    }

    final shares = splitCentavosEqually(centavos, centerCount);
    if (shares.isEmpty) {
      return Text(
        'The amount is too small to divide among $centerCount centers.',
        style: textStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${formatCentavos(centavos)} split equally among $centerCount eligible '
          '${centerCount == 1 ? 'center' : 'centers'}:',
          style: textStyle,
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < centerCount; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : Border(top: BorderSide(color: _darkTeal.withValues(alpha: 0.10))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dialysisCenters[i]['name']?.toString() ?? 'Unnamed Center',
                    style: Brand.body(13.5, color: Brand.textStrong),
                  ),
                ),
                const SizedBox(width: 12),
                Text(formatCentavos(shares[i]), style: textStyle.copyWith(fontSize: 13.5)),
              ],
            ),
          ),
      ],
    );
  }

  void _selectCenter(String centerId) {
    setState(() {
      _selectedCenterId = centerId;
    });
  }

  int? _parseCentavos() => parseAmountToCentavos(_customAmountController.text);

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
                            ? 'Checking available dialysis centers...'
                            : (_dialysisCenters.isNotEmpty
                                  ? 'One of ${_dialysisCenters.length} centers '
                                        'will be chosen at random. You will see '
                                        'which one before you pay.'
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
              subtitle: kBankTransferEnabled
                  ? 'Select the channel you will use to send your donation.'
                  : 'Donations are paid with GCash.',
              accent: Brand.mint,
              accentSoft: Brand.mintSoft,
            ),
            const SizedBox(height: 18),

            // Bank Transfer is hidden by kBankTransferEnabled (see
            // config/payment_config.dart); the original two-option layout
            // below is kept intact for when it is switched back on.
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;

                if (!kBankTransferEnabled) {
                  return _paymentButton(
                    method: kGcashMethod,
                    icon: Icons.phone_android_rounded,
                    subtitle: !_settings.isSandbox
                        ? 'Mobile wallet'
                        : _settings.paymongoTestEnabled
                            ? 'Mobile wallet · PayMongo test mode'
                            : 'Mobile wallet · simulated payment',
                  );
                }

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
                            Text('REVIEW & CONTINUE TO GCASH'),
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

    // Validate donation amount (integer centavos; the server re-validates).
    final centavos = _parseCentavos();

    if (centavos == null || centavos <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid donation amount.';
      });
      return;
    }

    if (centavos < _settings.minAmountCentavos ||
        centavos > _settings.maxAmountCentavos) {
      setState(() {
        _errorMessage = 'Please enter an amount between '
            '${formatCentavos(_settings.minAmountCentavos)} and '
            '${formatCentavos(_settings.maxAmountCentavos)}.';
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

    // Random and Donate to All need at least one eligible centre (the
    // server checks again, against the live list).
    if (_selectedAllocationMethod != 'Specific Dialysis Center' &&
        _dialysisCenters.isEmpty) {
      setState(() {
        _errorMessage = 'No dialysis centers are currently available to receive donations.';
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

    if (_selectedPaymentChannel != kGcashMethod) {
      setState(() {
        _errorMessage = 'Only GCash is available for donations right now.';
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

    final mode = switch (_selectedAllocationMethod) {
      'Randomly Assign a Dialysis Center' => DonationMode.randomCenter,
      'Distribute Donation Equally Among All Centers' => DonationMode.allCenters,
      _ => DonationMode.specificCenter,
    };
    final clinicId =
        mode == DonationMode.specificCenter ? _selectedCenterId : null;
    final enteredName = _nameController.text.trim();
    final donorName =
        widget.isAnonymous || enteredName.isEmpty ? null : enteredName;

    // Reuse the previous attempt's keys if nothing changed, so a retry after
    // a timeout -- or continuing again after Back or a refresh while that
    // checkout is still open -- returns the same donation (same random
    // centre, same split) instead of creating a second one.
    final previous = _pendingRequest;
    final request = previous != null &&
            previous.sameAs(
              mode: mode,
              amountCentavos: centavos,
              clinicId: clinicId,
              anonymous: widget.isAnonymous,
              donorName: donorName,
            )
        ? previous
        : CheckoutRequest(
            mode: mode,
            amountCentavos: centavos,
            clinicId: clinicId,
            anonymous: widget.isAnonymous,
            donorName: donorName,
          );
    _pendingRequest = request;

    try {
      final checkout = await _service.createCheckout(request);

      if (!mounted) return;

      // The request is kept until this donation is finished or cancelled
      // (see _loadResumableCheckout), not cleared here.
      setState(() {
        _isLoading = false;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CheckoutPage(
            checkout: checkout,
            clientSecret: request.clientSecret,
            service: _service,
          ),
        ),
      );

      // Back from an unfinished checkout: offer to resume it here.
      if (mounted) _loadResumableCheckout();
    } on DonationCheckoutException catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });

      // The centre list may have changed underneath the donor.
      if (e.code == 'CENTER_NOT_ELIGIBLE' || e.code == 'NO_ELIGIBLE_CENTERS') {
        _pendingRequest = null;
        _loadDialysisCenters();
      }
    }
  }

  /// Shown when this browser still has an unpaid checkout. Resuming reloads
  /// it from the server, so the recipient(s) cannot have changed.
  Widget _buildResumeCard() {
    final checkout = _resumable!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brand.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Brand.brand.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You have an unfinished donation', style: Brand.heading(17)),
          const SizedBox(height: 6),
          Text(
            '${checkout.reference} · ${formatCentavos(checkout.amountCentavos)} · '
            '${checkout.allocations.length == 1 ? checkout.allocations.first.clinicName : '${checkout.allocations.length} centers'}',
            style: Brand.body(13.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: () async {
                  _restoreForm(checkout);
                  await _openCheckout(checkout, _resumableSecret!);
                },
                child: const Text('Resume checkout'),
              ),
              TextButton(
                onPressed: () async {
                  final secret = _resumableSecret!;
                  if (!await confirmStartOver(context, checkout)) return;
                  await _startOver(checkout, secret);
                },
                child: const Text('Cancel it'),
              ),
            ],
          ),
        ],
      ),
    );
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
  /// The wording here follows [_handleDonate]: the server creates a pending
  /// donation with fixed recipients, and it only counts once the payment is
  /// confirmed on the checkout page.
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
                    'You will review the amount and recipient center(s) before '
                    'paying with GCash. Your donation is complete once the '
                    'payment goes through.'
                    '${_settings.isSandbox ? ' $kDemoBannerText' : ''}',
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
                          if (_resumable != null) ...[
                            _buildResumeCard(),
                            const SizedBox(height: 22),
                          ],
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
