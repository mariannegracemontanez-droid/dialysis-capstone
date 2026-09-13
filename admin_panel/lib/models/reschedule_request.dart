/// One patient-submitted request to move a dialysis session, as stored in
/// the `reschedule_requests` table the mobile app already writes to
/// (mobile-app/lib/services/reschedule_service.dart). The Center Admin
/// dashboard reads that same table -- there is no separate admin-side
/// request list.
///
/// Status vocabulary matches what the mobile app already renders:
/// pending -> approved | declined, plus `changed_date` when the admin
/// granted a date other than the one the patient asked for.
class RescheduleRequest {
  final String id;
  final String patientId;
  final String patientName;
  final String clinicId;

  /// The dialysis date the patient wants to move away from.
  final DateTime? originalDate;

  /// The date the patient asked for. Null when they only sent a reason.
  final DateTime? requestedDate;

  /// The date the admin actually granted -- equal to [requestedDate] for a
  /// plain accept, different after "Change Date".
  final DateTime? resolvedDate;
  final String? resolvedShift;

  final String? reason;
  final String? notes;
  final String status;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? adminNotes;

  const RescheduleRequest({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.clinicId,
    required this.status,
    this.originalDate,
    this.requestedDate,
    this.resolvedDate,
    this.resolvedShift,
    this.reason,
    this.notes,
    this.createdAt,
    this.reviewedAt,
    this.adminNotes,
  });

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  factory RescheduleRequest.fromJson(Map<String, dynamic> json) {
    final patient = json['patients'];

    return RescheduleRequest(
      id: json['id'].toString(),
      patientId: json['patient_id']?.toString() ?? '',
      patientName: patient is Map
          ? (_text(patient['full_name']) ?? 'Unknown patient')
          : 'Unknown patient',
      clinicId: json['clinic_id']?.toString() ?? '',
      originalDate: _date(json['original_date']),
      requestedDate: _date(json['requested_date']),
      resolvedDate: _date(json['resolved_date']),
      resolvedShift: _text(json['resolved_shift']),
      reason: _text(json['reason']),
      notes: _text(json['notes']),
      status: (_text(json['status']) ?? 'pending').toLowerCase(),
      createdAt: _date(json['created_at']),
      reviewedAt: _date(json['reviewed_at']),
      adminNotes: _text(json['admin_notes']),
    );
  }

  bool get isPending => status == 'pending';

  /// Accepted, whether on the requested date or one the admin chose.
  bool get isGranted => status == 'approved' || status == 'changed_date';

  /// What the admin sees in the list: the date the patient is actually
  /// asking to be scheduled on, falling back to the granted date.
  DateTime? get displayDate => requestedDate ?? resolvedDate;

  String get statusLabel {
    switch (status) {
      case 'approved':
        return 'Accepted';
      case 'declined':
        return 'Rejected';
      case 'changed_date':
        return 'Date changed';
      case 'cancelled':
        return 'Withdrawn';
      default:
        return 'Pending';
    }
  }
}
