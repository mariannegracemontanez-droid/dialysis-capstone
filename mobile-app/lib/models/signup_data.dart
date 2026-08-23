import '../utils/form_options.dart';

class SignupData {
  final String fullName;
  final String email;
  final String phone;
  final String password;
  final String status;
  final String dateOfBirth;
  final String homeAddress;
  final String bloodType;
  final String emergencyContactName;
  final String emergencyContactNumber;
  final String emergencyContactRelationship;
  final String profileId;
  final String patientId;
  final String clinicId;
  final String clinicName;
  final List<String> clinicRequirements;
  final Map<String, String> documentUrls;
  final String ckdLevel;
  final List<String> conditions;
  final String province;
  final String city;
  final String barangay;
  final String locationSummary;
  final String medicalDocumentPath;
  final List<String> medicalDocumentPaths;
  final String referralDoctor;
  final List<String> insuranceOptions;
  final String budgetRange;
  final String preferredClinicType;

  SignupData({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.password,
    this.status = 'pending',
    this.dateOfBirth = '',
    this.homeAddress = '',
    this.bloodType = '',
    this.emergencyContactName = '',
    this.emergencyContactNumber = '',
    this.emergencyContactRelationship = '',
    this.profileId = '',
    this.patientId = '',
    this.clinicId = '',
    this.clinicName = '',
    this.clinicRequirements = const [],
    this.documentUrls = const {},
    this.ckdLevel = 'Stage 1',
    this.conditions = const [],
    this.province = '',
    this.city = '',
    this.barangay = '',
    this.locationSummary = '',
    this.medicalDocumentPath = '',
    this.medicalDocumentPaths = const [],
    this.referralDoctor = '',
    this.insuranceOptions = const [],
    this.budgetRange = 'Low-cost / Government-supported',
    this.preferredClinicType = 'Public Hospital',
  });

  /// Builds a [SignupData] pre-filled from a previously-submitted patient
  /// application row (e.g. when an existing patient applies to another
  /// clinic), so they only need to pick a new clinic and upload that
  /// clinic's required documents instead of re-typing everything.
  ///
  /// Clinic-specific fields (clinicId, clinicName, documentUrls,
  /// clinicRequirements, patientId) are intentionally left at their
  /// defaults so a brand-new application gets created.
  factory SignupData.fromPatientRow(
    Map<String, dynamic> row, {
    required String profileId,
    String fallbackFullName = '',
    String fallbackEmail = '',
    String fallbackPhone = '',
  }) {
    String stringOf(String key) => row[key]?.toString().trim() ?? '';

    final rawHomeAddress = stringOf('home_address');
    final addressMatch = RegExp(
      r'^(.*),\s*Barangay\s+([^,]+),\s*Valenzuela City\s*$',
      caseSensitive: false,
    ).firstMatch(rawHomeAddress);
    final street = addressMatch?.group(1)?.trim() ?? rawHomeAddress;
    final parsedBarangay = addressMatch?.group(2)?.trim() ?? '';
    final barangay = FormOptions.valenzuelaBarangays.contains(parsedBarangay)
        ? parsedBarangay
        : '';

    final rawContactName = stringOf('emergency_contact_name');
    final contactMatch = RegExp(
      r'^(.*)\s*\(([^)]+)\)\s*$',
    ).firstMatch(rawContactName);
    final contactName = contactMatch?.group(1)?.trim() ?? rawContactName;
    final parsedRelationship = contactMatch?.group(2)?.trim() ?? '';
    final relationship =
        FormOptions.emergencyContactRelationships.contains(parsedRelationship)
        ? parsedRelationship
        : '';

    final insuranceRaw = stringOf('insurance');
    final insuranceOptions = insuranceRaw.isEmpty || insuranceRaw == 'None'
        ? <String>[]
        : insuranceRaw
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();

    final existingCondition = stringOf('existing_condition');
    final conditions = existingCondition.isEmpty
        ? <String>[]
        : [existingCondition];

    final fullName = stringOf('full_name');
    final email = stringOf('email');
    final phone = stringOf('phone');

    return SignupData(
      fullName: fullName.isNotEmpty ? fullName : fallbackFullName,
      email: email.isNotEmpty ? email : fallbackEmail,
      phone: phone.isNotEmpty ? phone : fallbackPhone,
      password: '',
      profileId: profileId,
      dateOfBirth: stringOf('date_of_birth'),
      homeAddress: street,
      barangay: barangay,
      bloodType: stringOf('blood_type'),
      emergencyContactName: contactName,
      emergencyContactNumber: stringOf('emergency_contact_number'),
      emergencyContactRelationship: relationship,
      ckdLevel: stringOf('dialysis_stage').isNotEmpty
          ? stringOf('dialysis_stage')
          : 'Stage 1',
      conditions: conditions,
      insuranceOptions: insuranceOptions,
      budgetRange: stringOf('budget').isNotEmpty
          ? stringOf('budget')
          : 'Low-cost / Government-supported',
      preferredClinicType: stringOf('preferred_clinic').isNotEmpty
          ? stringOf('preferred_clinic')
          : 'Public Hospital',
      locationSummary: stringOf('user_location'),
    );
  }

  SignupData copyWith({
    String? profileId,
    String? fullName,
    String? email,
    String? phone,
    String? status,
    String? password,
    String? dateOfBirth,
    String? homeAddress,
    String? bloodType,
    String? emergencyContactName,
    String? emergencyContactNumber,
    String? emergencyContactRelationship,
    String? patientId,
    String? clinicId,
    String? clinicName,
    String? ckdLevel,
    List<String>? conditions,
    String? province,
    String? city,
    String? barangay,
    String? locationSummary,
    String? medicalDocumentPath,
    List<String>? medicalDocumentPaths,
    List<String>? clinicRequirements,
    Map<String, String>? documentUrls,
    String? referralDoctor,
    List<String>? insuranceOptions,
    String? budgetRange,
    String? preferredClinicType,
  }) {
    return SignupData(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      password: password ?? this.password,
      status: status ?? this.status,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      homeAddress: homeAddress ?? this.homeAddress,
      bloodType: bloodType ?? this.bloodType,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactNumber:
          emergencyContactNumber ?? this.emergencyContactNumber,
      emergencyContactRelationship:
          emergencyContactRelationship ?? this.emergencyContactRelationship,
      profileId: profileId ?? this.profileId,
      patientId: patientId ?? this.patientId,
      clinicId: clinicId ?? this.clinicId,
      clinicName: clinicName ?? this.clinicName,
      clinicRequirements: clinicRequirements ?? this.clinicRequirements,
      documentUrls: documentUrls ?? this.documentUrls,
      ckdLevel: ckdLevel ?? this.ckdLevel,
      conditions: conditions ?? this.conditions,
      province: province ?? this.province,
      city: city ?? this.city,
      barangay: barangay ?? this.barangay,
      locationSummary: locationSummary ?? this.locationSummary,
      medicalDocumentPath: medicalDocumentPath ?? this.medicalDocumentPath,
      medicalDocumentPaths: medicalDocumentPaths ?? this.medicalDocumentPaths,
      referralDoctor: referralDoctor ?? this.referralDoctor,
      insuranceOptions: insuranceOptions ?? this.insuranceOptions,
      budgetRange: budgetRange ?? this.budgetRange,
      preferredClinicType: preferredClinicType ?? this.preferredClinicType,
    );
  }
}
