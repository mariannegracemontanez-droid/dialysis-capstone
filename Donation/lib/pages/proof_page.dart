// REMOVE dart:io ❌
// import 'dart:io';

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProofUploadPage extends StatefulWidget {
  final String donationId;

  const ProofUploadPage({super.key, required this.donationId});

  @override
  State<ProofUploadPage> createState() => _ProofUploadPageState();
}

class _ProofUploadPageState extends State<ProofUploadPage> {
  Uint8List? _imageBytes;
  bool _isLoading = false;

  // 📸 PICK IMAGE (WEB SAFE)
  Future<void> pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();

      setState(() {
        _imageBytes = bytes;
      });
    }
  }

  // 🚀 UPLOAD + SAVE
  Future<void> uploadProof() async {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload a receipt first")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      final filePath =
          'receipts/${widget.donationId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // 📤 Upload
      await supabase.storage
          .from('donation_receipts')
          .uploadBinary(filePath, _imageBytes!);

      // 🔗 Get URL
      final imageUrl =
          supabase.storage.from('donation_receipts').getPublicUrl(filePath);

      // 📝 Save to DB
      await supabase.from('donations').update({
        'proof_url': imageUrl,
        'status': 'pending',
      }).eq('id', widget.donationId);

      if (!mounted) return;

      // ✅ SUCCESS UI
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Success 🎉"),
          content: const Text(
              "Your receipt has been uploaded. Please wait for admin approval."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // back to landing
              },
              child: const Text("OK"),
            )
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Upload failed: $e")),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFF),
      appBar: AppBar(
        title: const Text("Upload Proof"),
        centerTitle: true,
        backgroundColor: const Color(0xFF2F6D85),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // 💬 MESSAGE CARD
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4FA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "Thank you for your donation 💙\n\nUpload your receipt so we can verify your contribution.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14),
                  ),
                ),

                const SizedBox(height: 30),

                // 📸 IMAGE BOX
                GestureDetector(
                  onTap: pickImage,
                  child: Container(
                    height: 240,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _imageBytes == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_upload,
                                  size: 50, color: Colors.grey),
                              SizedBox(height: 10),
                              Text("Click to upload receipt"),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 30),

                // 🚀 BUTTON
                ElevatedButton(
                  onPressed: _isLoading ? null : uploadProof,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38A6DB),
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 3,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "CONFIRM UPLOAD",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
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