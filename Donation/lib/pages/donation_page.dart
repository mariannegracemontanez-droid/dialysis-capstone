import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/payment_config.dart';
import '../services/donation_checkout_service.dart';
import '../theme/brand.dart';
import '../widgets/donation_steps.dart';
import '../widgets/motion.dart';
import '../widgets/site_nav.dart';
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
  //
  // Everything below this line only presents the state above. Every choice
  // still goes through the same selection handlers, and submitting still
  // runs [_handleDonate] unchanged.

  /// Back: normal back behaviour whenever there is a route to go back to.
  /// When there is not -- signing in mid-donation replaces the stack, so this
  /// page can be the only route -- popping would leave the app with no route
  /// at all, so fall back to the landing page instead.
  void _handleBack() {
    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _goToLandingPage();
    }
  }

  /// The site's floating capsule navigation (the same bar as the landing and
  /// About pages), with the back button and the donor's place in the
  /// journey instead of a Donate action - the donor is already donating.
  Widget _buildNavBar() {
    final mobile = Brand.isMobile(MediaQuery.of(context).size.width);

    return NavCapsule(
      child: Row(
        children: [
          NavBackButton(onPressed: _handleBack),
          const SizedBox(width: 12),
          const BrandMark(),
          const Spacer(),
          if (!mobile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Brand.tealSoft,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Brand.teal.withValues(alpha: 0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    size: 17,
                    color: Brand.teal,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Step 2 of 3',
                    style: Brand.label(13, color: Brand.brandDeep),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _animatedEntry({required Widget child, int delay = 0}) {
    return Reveal(delayMs: delay, child: child);
  }

  /// A light, left-aligned page opening - deliberately unlike the navy
  /// heroes of the landing and About pages, so the donation step reads as a
  /// calm working page. The step indicator sits on a white card beneath it.
  Widget _buildHero() {
    final width = MediaQuery.of(context).size.width;
    final mobile = Brand.isMobile(width);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Brand.sky, Brand.canvas],
        ),
      ),
      child: Stack(
        children: [
          // A soft teal glow at the top right, for warmth.
          Positioned(
            right: -120,
            top: -80,
            width: 520,
            height: 420,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Brand.teal.withValues(alpha: 0.16),
                      Brand.teal.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              // The floating navigation sits over the top of the page.
              top: SiteNav.reserve + (mobile ? 28 : 44),
              bottom: mobile ? 8 : 12,
            ),
            child: ContentColumn(
              maxWidth: _pageWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(
                    widget.isAnonymous ? 'Anonymous donation' : 'Donor account',
                  ),
                  SizedBox(height: mobile ? 16 : 18),
                  Text(
                    'Complete your donation.',
                    style: Brand.display(mobile ? 30 : 42),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      'Choose an amount, decide which dialysis centre it '
                      'supports, and tell us how you will be sending it. '
                      'Every peso goes toward the care of patients who depend '
                      'on treatment every week.',
                      style: Brand.body(mobile ? 14.5 : 16),
                    ),
                  ),
                  SizedBox(height: mobile ? 22 : 30),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(mobile ? 16 : 22),
                    decoration: Brand.card(radius: 22),
                    child: const DonationSteps(current: 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const double _pageWidth = 1120;

  // ------------------------------------------------------ form sections

  /// Whether each part of the form is filled in well enough to submit -
  /// shown only as a tick on the section's number, never used to validate
  /// (the checks in [_handleDonate] are unchanged).
  bool get _amountReady {
    final centavos = _parseCentavos();
    return centavos != null &&
        centavos >= _settings.minAmountCentavos &&
        centavos <= _settings.maxAmountCentavos;
  }

  bool get _destinationReady =>
      _selectedAllocationMethod != null &&
      (_selectedAllocationMethod != 'Specific Dialysis Center' ||
          _selectedCenterId != null);

  bool get _paymentReady => _selectedPaymentChannel != null;

  /// One numbered step of the form, on its own card. The number turns into
  /// a tick once that step is complete, so progress down the page is
  /// visible at a glance.
  Widget _formSection({
    required int number,
    required String title,
    required String subtitle,
    required Widget child,
    bool complete = false,
    bool required = true,
    int delay = 0,
  }) {
    final mobile = Brand.isMobile(MediaQuery.of(context).size.width);

    return _animatedEntry(
      delay: delay,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(mobile ? 16 : 28),
        decoration: BoxDecoration(
          color: Brand.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: complete ? Brand.teal.withValues(alpha: 0.35) : Brand.border,
          ),
          boxShadow: Brand.shadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 36,
                  width: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: complete ? Brand.teal : Brand.white,
                    border: Border.all(
                      color: complete ? Brand.teal : Brand.brandDeep,
                      width: 1.6,
                    ),
                  ),
                  child: complete
                      ? const Icon(
                          Icons.check_rounded,
                          size: 19,
                          color: Colors.white,
                        )
                      : Text(
                          '$number',
                          style: Brand.label(15, color: Brand.brandDeep),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(title, style: Brand.heading(mobile ? 17 : 18.5)),
                          _requirementTag(required),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Brand.body(13.5, color: Brand.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: mobile ? 18 : 22),
            child,
          ],
        ),
      ),
    );
  }

  Widget _requirementTag(bool required) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: required ? Brand.coralSoft : Brand.borderSoft,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        required ? 'Required' : 'Optional',
        style: Brand.label(
          11.5,
          color: required ? Brand.coral : Brand.textMuted,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    Widget? prefixIcon,
    String? prefixText,
    String? helperText,
    String? errorText,
    TextStyle? style,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style:
          style ??
          TextStyle(
            color: _darkTeal,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        errorText: errorText,
        helperMaxLines: 2,
        errorMaxLines: 2,
        prefixIcon: prefixIcon,
        prefixText: prefixText,
        prefixStyle: (style ?? const TextStyle(fontSize: 15)).copyWith(
          color: _darkTeal,
          fontWeight: FontWeight.w700,
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
        helperStyle: Brand.body(12.5, color: Brand.textMuted),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Brand.coral),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Brand.coral, width: 2),
        ),
      ),
    );
  }

  /// Shared look for the choices in this form - payment channel, allocation
  /// method and dialysis centre. Each one still just reports a tap to the
  /// selection handler it was given. [vertical] stacks the icon above the
  /// text, for the side-by-side allocation cards on wider screens.
  Widget _choiceTile({
    required bool isSelected,
    required VoidCallback onTap,
    required IconData icon,
    required String title,
    required String subtitle,
    required String semanticLabel,
    bool compact = false,
    bool vertical = false,
  }) {
    final radius = BorderRadius.circular(compact ? 16 : 20);

    final iconBox = Container(
      height: compact ? 36 : 44,
      width: compact ? 36 : 44,
      decoration: Brand.iconBox(
        isSelected ? Brand.white : _softBlue,
        radius: 14,
      ),
      child: Icon(icon, color: Brand.brand, size: compact ? 18 : 22),
    );

    final check = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 22,
      width: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? Brand.brand : Colors.transparent,
        border: Border.all(
          color: isSelected ? Brand.brand : Brand.borderStrong,
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Brand.label(compact ? 14 : 15, color: Brand.textStrong),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(subtitle, style: Brand.body(12.5, color: Brand.textMuted)),
        ],
      ],
    );

    return HoverLift(
      lift: 3,
      builder: (context, hovered) {
        return Semantics(
          inMutuallyExclusiveGroup: true,
          selected: isSelected,
          button: true,
          label: semanticLabel,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: radius,
            focusColor: Brand.brand.withValues(alpha: 0.10),
            hoverColor: Colors.transparent,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: EdgeInsets.all(compact ? 13 : (vertical ? 18 : 16)),
              decoration: BoxDecoration(
                color: isSelected ? Brand.sky : Brand.white,
                borderRadius: radius,
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
              child: vertical
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [iconBox, const Spacer(), check],
                        ),
                        const SizedBox(height: 14),
                        text,
                      ],
                    )
                  : Row(
                      children: [
                        iconBox,
                        SizedBox(width: compact ? 11 : 13),
                        Expanded(child: text),
                        const SizedBox(width: 10),
                        check,
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
      title: method == kGcashMethod ? 'GCash' : method,
      subtitle: subtitle,
      semanticLabel: 'Pay by $method. $subtitle',
    );
  }

  /// Display titles for the three allocation methods. The method strings
  /// themselves are unchanged - they are what the form logic switches on.
  static const Map<String, String> _allocationTitles = {
    'Specific Dialysis Center': 'Choose a centre',
    'Randomly Assign a Dialysis Center': 'Random centre',
    'Distribute Donation Equally Among All Centers': 'Split equally',
  };

  Widget _allocationButton({
    required String method,
    required IconData icon,
    required String subtitle,
    bool vertical = false,
  }) {
    final isSelected = _selectedAllocationMethod == method;

    return _choiceTile(
      isSelected: isSelected,
      onTap: () => _selectAllocationMethod(method),
      icon: icon,
      title: _allocationTitles[method] ?? method,
      subtitle: subtitle,
      semanticLabel: '$method. $subtitle',
      vertical: vertical,
    );
  }

  Widget _centerButton(Map<String, dynamic> center) {
    final centerId = center['id']?.toString() ?? '';
    final name = center['name']?.toString() ?? 'Unnamed Center';
    final location = (center['address']?.toString().isNotEmpty ?? false)
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
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.coralSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.coral.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Brand.coral,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: Brand.label(14, color: Brand.coral)),
            ),
          ],
        ),
      ),
    );
  }

  /// An inset panel for the detail that appears under a chosen allocation
  /// method.
  Widget _allocationDetail({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      // Tighter on phones, where this panel sits inside a section card.
      padding: EdgeInsets.all(
        Brand.isMobile(MediaQuery.of(context).size.width) ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: Brand.tealSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.teal.withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }

  // ------------------------------------------------------------ step 1

  Widget _buildDetailsSection() {
    if (widget.isAnonymous) {
      return _formSection(
        number: 1,
        title: 'Giving anonymously',
        subtitle: 'Your donation will not be associated with a donor account.',
        required: false,
        complete: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: Brand.iconBox(Brand.tealSoft, radius: 13),
              child: Icon(
                Icons.visibility_off_rounded,
                color: _primaryTeal,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No name or email is stored with this donation, and it '
                'appears in the public list as “Anonymous”.',
                style: Brand.body(14),
              ),
            ),
          ],
        ),
      );
    }

    final name = _buildTextField(
      label: 'Full Name / Organization',
      hint: 'Enter your name',
      controller: _nameController,
      prefixIcon: Icon(Icons.person_outline_rounded, color: _primaryTeal),
    );
    final email = _buildTextField(
      label: 'Email Address',
      hint: 'Enter your email',
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      prefixIcon: Icon(Icons.email_outlined, color: _primaryTeal),
    );

    return _formSection(
      number: 1,
      title: 'Your details',
      subtitle: 'These details help us identify and record your contribution.',
      required: false,
      complete: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(children: [name, const SizedBox(height: 16), email]);
          }
          return Row(
            children: [
              Expanded(child: name),
              const SizedBox(width: 16),
              Expanded(child: email),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ step 2

  /// Suggested amounts. Tapping one only fills the amount field; the field
  /// is validated exactly as if it had been typed.
  static const List<int> _suggestedPesos = [100, 500, 1000, 2500];

  Widget _buildAmountSection() {
    final text = _customAmountController.text.trim();
    final invalidFormat = text.isNotEmpty && _parseCentavos() == null;
    final suggestions = [
      for (final pesos in _suggestedPesos)
        if (pesos * 100 >= _settings.minAmountCentavos &&
            pesos * 100 <= _settings.maxAmountCentavos)
          pesos,
    ];

    return _formSection(
      number: 2,
      title: 'Donation amount',
      subtitle: 'Enter the amount you would like to contribute.',
      complete: _amountReady,
      delay: 60,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (suggestions.isNotEmpty) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final pesos in suggestions) _amountChip(pesos)],
            ),
            const SizedBox(height: 16),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: _buildTextField(
              label: 'Custom Amount',
              hint: 'Enter amount',
              controller: _customAmountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              prefixText: '₱  ',
              style: TextStyle(
                color: _darkTeal,
                fontFamily: Brand.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
              errorText: invalidFormat
                  ? 'Use numbers only, with up to two decimal places.'
                  : null,
              helperText:
                  'Between ${formatCentavos(_settings.minAmountCentavos)} and '
                  '${formatCentavos(_settings.maxAmountCentavos)}.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountChip(int pesos) {
    final selected = _parseCentavos() == pesos * 100;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Donate ${formatCentavos(pesos * 100)}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _customAmountController.text = '$pesos';
          setState(() => _errorMessage = null);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Brand.coralSoft : Brand.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Brand.coral : Brand.border,
              width: selected ? 1.8 : 1.2,
            ),
          ),
          child: Text(
            formatCentavos(pesos * 100),
            style: Brand.label(
              14.5,
              color: selected ? Brand.coral : Brand.brandDeep,
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ step 3

  Widget _buildDestinationSection() {
    const options = [
      (
        method: 'Specific Dialysis Center',
        icon: Icons.location_on_outlined,
        subtitle: 'Choose exactly which centre receives your donation.',
      ),
      (
        method: 'Randomly Assign a Dialysis Center',
        icon: Icons.shuffle_rounded,
        subtitle: 'One centre is picked at random when the donation is made.',
      ),
      (
        method: 'Distribute Donation Equally Among All Centers',
        icon: Icons.balance_outlined,
        subtitle: 'Shared equally across every eligible centre.',
      ),
    ];

    return _formSection(
      number: 3,
      title: 'Where your gift goes',
      subtitle: 'Choose how you would like your donation to be distributed.',
      complete: _destinationReady,
      delay: 120,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < options.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: _allocationButton(
                            method: options[i].method,
                            icon: options[i].icon,
                            subtitle: options[i].subtitle,
                            vertical: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                for (int i = 0; i < options.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _allocationButton(
                    method: options[i].method,
                    icon: options[i].icon,
                    subtitle: options[i].subtitle,
                  ),
                ],
              ..._destinationDetail(columns: wide ? 2 : 1),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _destinationDetail({required int columns}) {
    if (_selectedAllocationMethod == 'Specific Dialysis Center') {
      return [
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select a centre · ${_dialysisCenters.length} available',
                      style: Brand.label(13.5, color: Brand.brandDeep),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 10.0;
                        final tileWidth = columns == 1
                            ? constraints.maxWidth
                            : (constraints.maxWidth - gap) / 2;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final center in _dialysisCenters)
                              SizedBox(
                                width: tileWidth,
                                child: _centerButton(center),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
        ),
      ];
    }

    if (_selectedAllocationMethod == 'Randomly Assign a Dialysis Center') {
      return [
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
      ];
    }

    if (_selectedAllocationMethod ==
        'Distribute Donation Equally Among All Centers') {
      return [
        _allocationDetail(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.balance_outlined, color: _primaryTeal, size: 20),
              const SizedBox(width: 12),
              Expanded(child: _buildEqualDistributionSummary()),
            ],
          ),
        ),
      ];
    }

    return const [];
  }

  // ------------------------------------------------------------ step 4

  Widget _buildPaymentSection() {
    return _formSection(
      number: 4,
      title: 'Payment method',
      subtitle: kBankTransferEnabled
          ? 'Select the channel you will use to send your donation.'
          : 'Donations are paid with GCash.',
      complete: _paymentReady,
      delay: 180,
      // Bank Transfer is hidden by kBankTransferEnabled (see
      // config/payment_config.dart); the original two-option layout below is
      // kept intact for when it is switched back on.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

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
    );
  }

  /// The four numbered steps of the form.
  Widget _buildDonationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDetailsSection(),
        const SizedBox(height: 18),
        _buildAmountSection(),
        const SizedBox(height: 18),
        _buildDestinationSection(),
        const SizedBox(height: 18),
        _buildPaymentSection(),
      ],
    );
  }

  // ------------------------------------------------------------ summary

  String get _destinationSummary {
    switch (_selectedAllocationMethod) {
      case 'Specific Dialysis Center':
        final center = _dialysisCenters.where(
          (c) => c['id']?.toString() == _selectedCenterId,
        );
        return center.isEmpty
            ? 'Choose a centre'
            : (center.first['name']?.toString() ?? 'Unnamed Center');
      case 'Randomly Assign a Dialysis Center':
        return 'A random centre, shown before you pay';
      case 'Distribute Donation Equally Among All Centers':
        final count = _dialysisCenters.length;
        return count == 0
            ? 'Split equally among all centres'
            : 'Split equally among $count '
                  '${count == 1 ? 'centre' : 'centres'}';
      default:
        return 'Not chosen yet';
    }
  }

  /// A live preview of the donation on a navy card, with the submit action.
  /// It reflects the form only; the server's figures are shown on the review
  /// step before anything is paid.
  Widget _buildSummary() {
    final centavos = _parseCentavos();
    final hasAmount = centavos != null && centavos > 0;
    final name = _nameController.text.trim();

    return _animatedEntry(
      delay: 140,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: Brand.deepGradient,
          borderRadius: BorderRadius.circular(26),
          boxShadow: Brand.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Your donation', light: true),
            const SizedBox(height: 18),
            Text(
              hasAmount ? formatCentavos(centavos) : '₱ —',
              style: Brand.display(36, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              hasAmount ? 'Donation amount' : 'Enter an amount to begin',
              style: Brand.body(
                13,
                color: Colors.white.withValues(alpha: 0.70),
              ),
            ),
            const SizedBox(height: 20),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
            const SizedBox(height: 18),
            _summaryRow(
              icon: widget.isAnonymous
                  ? Icons.visibility_off_rounded
                  : Icons.person_outline_rounded,
              label: 'Giving as',
              value: widget.isAnonymous
                  ? 'Anonymous'
                  : (name.isEmpty ? 'Your donor account' : name),
            ),
            const SizedBox(height: 14),
            _summaryRow(
              icon: Icons.alt_route_rounded,
              label: 'Destination',
              value: _destinationSummary,
              pending: !_destinationReady,
            ),
            const SizedBox(height: 14),
            _summaryRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Payment',
              value: _selectedPaymentChannel == null
                  ? 'Not chosen yet'
                  : (_selectedPaymentChannel == kGcashMethod
                        ? 'GCash'
                        : _selectedPaymentChannel!),
              pending: !_paymentReady,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 20),
              _messageBox(_errorMessage!),
            ],
            const SizedBox(height: 22),
            _buildSubmitButton(),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.70),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You will review the amount and recipient centre(s) '
                    'before paying.',
                    style: Brand.body(
                      12.5,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow({
    required IconData icon,
    required String label,
    required String value,
    bool pending = false,
  }) {
    const turquoise = Color(0xFF7FD0D9);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 17, color: turquoise),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: Brand.eyebrow(
                  color: Colors.white.withValues(alpha: 0.60),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: pending
                    ? Brand.body(
                        14,
                        color: Colors.white.withValues(alpha: 0.62),
                      )
                    : Brand.label(14.5, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The strongest element on the page, matching the Donate action
  /// everywhere else on the site. Still calls [_handleDonate].
  Widget _buildSubmitButton() {
    return SizedBox(
      height: 58,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleDonate,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentBlue,
          disabledBackgroundColor: _accentBlue.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: Brand.displayFont,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
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
                    Icon(Icons.favorite_rounded, size: 20),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Review & Continue to GCash',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
        boxShadow: Brand.shadowSoft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: Brand.iconBox(Brand.sky, radius: 14),
            child: const Icon(
              Icons.history_rounded,
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
                  'You have an unfinished donation',
                  style: Brand.heading(17),
                ),
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
          borderRadius: BorderRadius.circular(26),
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

  /// What actually happens on submit, as three short reassurances.
  ///
  /// The wording follows [_handleDonate]: the server creates a pending
  /// donation with fixed recipients, and it only counts once the payment is
  /// confirmed on the checkout page.
  Widget _buildReassurance() {
    Widget point(IconData icon, String title, String text) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: Brand.iconBox(Brand.tealSoft, radius: 11),
            child: Icon(icon, size: 17, color: Brand.teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Brand.label(14, color: Brand.textStrong)),
                const SizedBox(height: 2),
                Text(text, style: Brand.body(13)),
              ],
            ),
          ),
        ],
      );
    }

    return _animatedEntry(
      delay: 200,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Brand.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Brand.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What happens when you submit', style: Brand.heading(16)),
            const SizedBox(height: 16),
            point(
              Icons.fact_check_outlined,
              'Review before you pay',
              'You will see the amount and recipient center(s) before paying '
                  'with GCash.',
            ),
            const SizedBox(height: 14),
            point(
              Icons.lock_outline_rounded,
              'Recipients stay fixed',
              'Once your donation is created, the centre(s) it supports do '
                  'not change.',
            ),
            const SizedBox(height: 14),
            point(
              Icons.verified_outlined,
              'Recorded once paid',
              'Your donation is complete once the payment goes through.',
            ),
            if (_settings.isSandbox) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Brand.sky,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Brand.brand,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kDemoBannerText,
                        style: Brand.body(12.5, color: Brand.brandDeep),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
    final needsLogin = !widget.isAnonymous && user == null;

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_resumable != null) ...[
          _buildResumeCard(),
          const SizedBox(height: 18),
        ],
        needsLogin ? _buildLoginRequiredCard() : _buildDonationForm(),
      ],
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!needsLogin) ...[_buildSummary(), const SizedBox(height: 18)],
        _buildReassurance(),
      ],
    );

    return Scaffold(
      backgroundColor: _surface,
      body: Stack(
        children: [
          RevealScope(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      _buildHero(),
                      Padding(
                        padding: EdgeInsets.only(
                          top: mobile ? 18 : 24,
                          bottom: mobile ? 40 : 64,
                        ),
                        child: ContentColumn(
                          maxWidth: _pageWidth,
                          // The form and its summary sit side by side on
                          // wide screens; below that the summary follows the
                          // form, so the submit button comes after every step.
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth < 940) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    main,
                                    const SizedBox(height: 18),
                                    side,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: main),
                                  const SizedBox(width: 28),
                                  SizedBox(width: 370, child: side),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildNavBar()),
        ],
      ),
    );
  }
}
