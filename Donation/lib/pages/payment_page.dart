import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({
    super.key,
    required this.fullName,
    required this.email,
    required this.amount,
    required this.paymentMethod,
  });

  final String fullName;
  final String email;
  final double amount;
  final String paymentMethod;

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final _picker = ImagePicker();
  XFile? _receiptPhoto;
  bool _isUploading = false;
  String? _errorMessage;
  String? _successMessage;

  final Color _darkTeal = const Color(0xFF1F5E7D);
  final Color _lightGray = const Color(0xFFF2F5F8);
  final Color _confirmTeal = const Color(0xFF7DD9D8);

  Future<void> _pickReceipt() async {
    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );

    if (photo == null) {
      return;
    }

    setState(() {
      _receiptPhoto = photo;
      _errorMessage = null;
    });
  }

  Future<void> _confirmDonation() async {
    if (_receiptPhoto == null) {
      setState(() {
        _errorMessage = 'Please add a receipt photo to continue.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('User is not signed in.');
      }

      final bytes = await _receiptPhoto!.readAsBytes();
      final extension = _receiptPhoto!.name.contains('.')
          ? _receiptPhoto!.name.split('.').last
          : 'jpg';
      final path = 'receipts/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$extension';

      await Supabase.instance.client.storage.from('receipts').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      final publicUrl = Supabase.instance.client.storage.from('receipts').getPublicUrl(path);

      await Supabase.instance.client.from('donations').insert({
        'donor_id': user.id,
        'full_name': widget.fullName,
        'email': widget.email,
        'amount': widget.amount,
        'payment_method': widget.paymentMethod,
        'payment_status': 'pending',
        'transaction_reference': publicUrl,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      setState(() {
        _successMessage = 'Proof uploaded successfully. Your donation is pending verification.';
        _isUploading = false;
      });

      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _errorMessage = 'Error confirming donation. ${e.toString()}';
      });
    }
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
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10)),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: const Text(
                'Thank you For Your Donation. Your generosity helps us continue our mission. We truly appreciate your support. Kindly share the receipt as proof of transaction so we may confirm your donation.',
                style: TextStyle(fontSize: 16, height: 1.7),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _pickReceipt,
              child: Container(
                height: 260,
                decoration: BoxDecoration(
                  color: _lightGray,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _receiptPhoto == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, size: 36, color: Colors.black45),
                          SizedBox(height: 12),
                          Text('ADD PHOTO', style: TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.file(
                          File(_receiptPhoto!.path),
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
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
                onPressed: _isUploading ? null : _confirmDonation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _confirmTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: _isUploading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('CONFIRM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
            _buildFooter(),
          ],
        ),
      ),
    );
  }
}
