class SignupData {
  final String fullName;
  final String email;
  final String phone;
  final String password;
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
    this.ckdLevel = 'Stage 3',
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
    String? fullName,
    String? email,
    String? phone,
    String? password,
    String? ckdLevel,
    List<String>? conditions,
    String? province,
    String? city,
    String? barangay,
    String? locationSummary,
    String? medicalDocumentPath,
    List<String>? medicalDocumentPaths,
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
