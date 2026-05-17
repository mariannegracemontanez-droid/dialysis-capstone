import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProofUploadPage extends StatefulWidget {
  final String donationId;
  final String paymentMethod;

  const ProofUploadPage({
    super.key,
    required this.donationId,
    required this.paymentMethod,
  });

  @override
  State<ProofUploadPage> createState() => _ProofUploadPageState();
}

class _ProofUploadPageState extends State<ProofUploadPage>
    with SingleTickerProviderStateMixin {
  Uint8List? _imageBytes;
  bool _isLoading = false;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  final Color _darkTeal = const Color(0xFF163B56);
  final Color _primaryTeal = const Color(0xFF3B97A2);
  final Color _accentBlue = const Color(0xFF38A6DB);
  final Color _surface = const Color(0xFFF7FBFD);
  final Color _softBlue = const Color(0xFFEAF7FB);

  @override
  void initState() {
    super.initState();

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
    _animationController.dispose();
    super.dispose();
  }

  bool get _isGcash => widget.paymentMethod.toUpperCase() == 'GCASH';

  Future<void> pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _imageBytes = bytes;
      });
    }
  }

  Future<void> uploadProof() async {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please upload your receipt first.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      final filePath =
          'receipts/${widget.donationId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage
          .from('donation_receipts')
          .uploadBinary(filePath, _imageBytes!);

      final imageUrl = supabase.storage
          .from('donation_receipts')
          .getPublicUrl(filePath);

      await supabase
          .from('donations')
          .update({'proof_url': imageUrl, 'status': 'pending'})
          .eq('id', widget.donationId);

      if (!mounted) return;

      setState(() => _isLoading = false);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: _primaryTeal),
              const SizedBox(width: 10),
              const Text('Proof Submitted'),
            ],
          ),
          content: const Text(
            'Your receipt has been uploaded successfully. Please wait while the admin verifies your donation.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: Text(
                'Back to Home',
                style: TextStyle(
                  color: _primaryTeal,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
              final mobile = constraints.maxWidth < 850;

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
                      'STEP 2 OF 2',
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
                    'Upload your proof of payment for verification.',
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
                    'Scan the QR code, complete your transfer, then upload your receipt. Your donation will stay pending until reviewed by the admin.',
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
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Column(
                  children: [
                    _heroStep(
                      icon: Icons.qr_code_rounded,
                      title: 'Scan QR',
                      text: 'Pay using ${widget.paymentMethod}.',
                    ),
                    const SizedBox(height: 14),
                    _heroStep(
                      icon: Icons.receipt_long_rounded,
                      title: 'Upload Receipt',
                      text: 'Attach a clear image of your payment proof.',
                    ),
                    const SizedBox(height: 14),
                    _heroStep(
                      icon: Icons.verified_rounded,
                      title: 'Admin Review',
                      text: 'Your donation will be verified after review.',
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
              subtitle: 'Completed',
              active: true,
              done: true,
            ),
            _progressStep(
              number: '2',
              title: 'Proof Upload',
              subtitle: 'Current step',
              active: true,
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
    bool done = false,
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
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white)
                : Text(
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

  Widget _buildQrCard() {
    return _animatedEntry(
      delay: 80,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
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
          children: [
            _sectionLabel(
              icon: _isGcash
                  ? Icons.phone_android_rounded
                  : Icons.account_balance_rounded,
              title: _isGcash ? 'GCash Payment QR' : 'Bank Transfer QR',
              subtitle: 'Scan this QR code using your selected payment method.',
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFE3EEF4)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  _isGcash
                      ? 'lib/assets/image/gcash_qr.jpg'
                      : 'lib/assets/image/bank_qr.jpg',
                  height: 285,
                  width: 285,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _tipItem('Use the exact amount you entered on the donation form.'),
            _tipItem('Take a clear screenshot after successful payment.'),
            _tipItem('Keep the reference number visible if available.'),
          ],
        ),
      ),
    );
  }

  Widget _tipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: _primaryTeal, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.blueGrey.shade600,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard() {
    return _animatedEntry(
      delay: 160,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
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
          children: [
            _sectionLabel(
              icon: Icons.cloud_upload_outlined,
              title: 'Upload Receipt',
              subtitle:
                  'Attach a clear screenshot or photo showing your successful payment.',
            ),
            const SizedBox(height: 24),
            InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: pickImage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 315,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _imageBytes == null ? _surface : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _imageBytes == null
                        ? const Color(0xFFD8EAF0)
                        : _primaryTeal,
                    width: _imageBytes == null ? 1.2 : 1.8,
                  ),
                ),
                child: _imageBytes == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 76,
                            width: 76,
                            decoration: BoxDecoration(
                              color: _softBlue,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              Icons.add_photo_alternate_outlined,
                              color: _primaryTeal,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Click to upload receipt',
                            style: TextStyle(
                              color: _darkTeal,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Accepted: JPG, PNG, or screenshot',
                            style: TextStyle(
                              color: Colors.blueGrey.shade500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Image.memory(
                          _imageBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
              ),
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: pickImage,
                icon: Icon(Icons.refresh_rounded, color: _primaryTeal),
                label: Text(
                  'Replace receipt image',
                  style: TextStyle(
                    color: _primaryTeal,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 58,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : uploadProof,
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
                            Icon(Icons.verified_rounded, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'SUBMIT PROOF FOR VERIFICATION',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 0.4,
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
              'Make sure the receipt clearly shows the payment amount, date, and reference number if available. This helps verify your donation faster.',
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

  Widget _buildPageIntro() {
    return Column(
      children: [
        Text(
          'Complete Payment Verification',
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
            'Please complete your payment using the QR code below, then upload a clear receipt so your donation can be reviewed.',
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

  @override
  Widget build(BuildContext context) {
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
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final mobile = constraints.maxWidth < 880;

                              if (mobile) {
                                return Column(
                                  children: [
                                    _buildQrCard(),
                                    const SizedBox(height: 24),
                                    _buildUploadCard(),
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildQrCard()),
                                  const SizedBox(width: 24),
                                  Expanded(child: _buildUploadCard()),
                                ],
                              );
                            },
                          ),
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
