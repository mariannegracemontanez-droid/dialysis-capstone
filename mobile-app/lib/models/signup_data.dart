import '../utils/form_options.dart';
import '../utils/patient_name.dart';

/// A clinic application created during the current setup session (the
/// `patients` row exists so documents can be uploaded against it). Kept so
/// going back and choosing the same clinic again reuses the row instead of
/// failing with "already applied".
class ApplicationDraft {
  final String patientId;
  final Map<String, String> documentUrls;

  const ApplicationDraft({
    required this.patientId,
    this.documentUrls = const {},
  });
}

class SignupData {
  final PatientName name;
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
  final String preferredClinicType;
  final Map<String, ApplicationDraft> applicationDrafts;

  SignupData({
    required this.name,
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
    this.preferredClinicType = 'Public Hospital',
    this.applicationDrafts = const {},
  });

  String get fullName => name.displayName;

  /// Street address plus barangay, in the format stored in
  /// `patients.home_address` (and parsed back by [fromPatientRow]).
  String get composedHomeAddress => barangay.isEmpty
      ? homeAddress
      : '$homeAddress, Barangay $barangay, Valenzuela City';

  /// Contact name plus relationship, in the format stored in
  /// `patients.emergency_contact_name`.
  String get composedEmergencyContactName =>
      emergencyContactRelationship.isEmpty
      ? emergencyContactName
      : '$emergencyContactName ($emergencyContactRelationship)';

  /// The patient-submitted columns of a `patients` application row. Each
  /// row is the snapshot sent to one clinic, so the same map is used when
  /// the row is created and when it is updated on final submit.
  Map<String, Object?> toPatientApplicationColumns() {
    final parsedDob = DateTime.tryParse(dateOfBirth.trim());

    final selectedCondition = conditions.contains('None') || conditions.isEmpty
        ? 'None'
        : conditions.firstWhere(
            (condition) => condition != 'None',
            orElse: () => 'None',
          );

    final insuranceText = insuranceOptions.isNotEmpty
        ? insuranceOptions.join(', ')
        : 'None';

    return {
      ...name.toColumns(),
      'email': email,
      'phone': phone,
      'date_of_birth': ?parsedDob?.toIso8601String().split('T').first,
      'home_address': composedHomeAddress,
      'blood_type': bloodType,
      'emergency_contact_name': composedEmergencyContactName,
      'emergency_contact_number': emergencyContactNumber,
      'dialysis_stage': ckdLevel,
      'existing_condition': selectedCondition,
      'insurance': insuranceText,
      'financial_support': insuranceText,
      'preferred_clinic': preferredClinicType,
      'user_location': locationSummary,
    };
  }

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
    PatientName fallbackName = const PatientName(),
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

    // Prefer separated components from the application row, then from the
    // account profile; a legacy full name is carried along for display only.
    final rowName = PatientName.fromRow(row);
    final PatientName name;
    if (rowName.hasComponents) {
      name = rowName;
    } else if (fallbackName.hasComponents) {
      name = fallbackName;
    } else {
      name = rowName.legacyFullName.isNotEmpty ? rowName : fallbackName;
    }
    final email = stringOf('email');
    final phone = stringOf('phone');

    return SignupData(
      name: name,
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
      preferredClinicType: stringOf('preferred_clinic').isNotEmpty
          ? stringOf('preferred_clinic')
          : 'Public Hospital',
      locationSummary: stringOf('user_location'),
    );
  }

  SignupData copyWith({
    String? profileId,
    PatientName? name,
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
    String? preferredClinicType,
    Map<String, ApplicationDraft>? applicationDrafts,
  }) {
    return SignupData(
      name: name ?? this.name,
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
      preferredClinicType: preferredClinicType ?? this.preferredClinicType,
      applicationDrafts: applicationDrafts ?? this.applicationDrafts,
    );
  }
}
