import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'package:flutter/foundation.dart';

class FileUploadService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final ImagePicker _imagePicker = ImagePicker();

  /// Pick a single image from the device
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

  /// Pick multiple images from the device
  Future<List<XFile>?> pickImages() async {
    try {
      final pickedFiles = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      return pickedFiles;
    } catch (e) {
      throw Exception('Failed to pick images: $e');
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

      final fileBytes = await imageFile.readAsBytes();

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

      final fileBytes = await imageFile.readAsBytes();

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

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');
  }

  Future<void> _ensureAuthenticated() async {
    final currentUser = _supabase.auth.currentUser;
    final currentSession = _supabase.auth.currentSession;
    if (currentUser == null || currentSession == null) {
      throw Exception(
        'Upload failed: no authenticated Supabase session. Please log in again.',
      );
    }
  }

  Future<String> uploadMedicalDocumentImage({
    required XFile imageFile,
    required String patientId,
    required String clinicId,
  }) async {
    try {
      if (patientId.isEmpty) {
        throw Exception('Upload failed: missing patient application ID.');
      }

      await _ensureAuthenticated();

      const bucketName = 'medical_docs';

      final originalName = imageFile.name.isNotEmpty
          ? imageFile.name
          : imageFile.path.split('/').last;

      final extension = originalName.contains('.')
          ? originalName.split('.').last.toLowerCase()
          : 'jpg';

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_sanitizeFileName(originalName)}';

      final objectPath = '$patientId/$fileName';
      final fileBytes = await imageFile.readAsBytes();

      if (kDebugMode) {
        debugPrint('Uploading to bucket: $bucketName');
        debugPrint('Object path: $objectPath');
        debugPrint('File size: ${fileBytes.length} bytes');
      }

      await _supabase.storage
          .from(bucketName)
          .uploadBinary(
            objectPath,
            fileBytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
            ),
          );

      final publicUrl = _supabase.storage
          .from(bucketName)
          .getPublicUrl(objectPath);

      debugPrint('Upload successful: $publicUrl');

      return publicUrl;
    } catch (e) {
      debugPrint('Failed to upload medical document image: $e');
      throw Exception('Failed to upload medical document image: $e');
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
