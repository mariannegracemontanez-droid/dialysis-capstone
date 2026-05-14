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
