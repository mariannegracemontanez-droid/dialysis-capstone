import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'dart:io';

class FileUploadService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final ImagePicker _imagePicker = ImagePicker();

  /// Pick an image from the device
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      return pickedFile;
    } catch (e) {
      throw Exception('Failed to pick image: $e');
    }
  }

  /// Upload medical certificate for appointment
  Future<String> uploadMedicalCertificate({
    required String userId,
    required String appointmentId,
    required XFile imageFile,
  }) async {
    try {
      const bucketName = 'medical-certificates';
      final fileName =
          '${userId}_${appointmentId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final file = File(imageFile.path);
      final fileBytes = await file.readAsBytes();

      await _supabase.storage
          .from(bucketName)
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      final publicUrl = _supabase.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload medical certificate: $e');
    }
  }

  /// Upload appointment image/document
  Future<String> uploadAppointmentImage({
    required String userId,
    required XFile imageFile,
  }) async {
    try {
      const bucketName = 'appointment-images';
      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final file = File(imageFile.path);
      final fileBytes = await file.readAsBytes();

      await _supabase.storage
          .from(bucketName)
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      final publicUrl = _supabase.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload appointment image: $e');
    }
  }

  /// Delete a file from storage
  Future<void> deleteFile({
    required String bucketName,
    required String fileName,
  }) async {
    try {
      await _supabase.storage.from(bucketName).remove([fileName]);
    } catch (e) {
      throw Exception('Failed to delete file: $e');
    }
  }
}
