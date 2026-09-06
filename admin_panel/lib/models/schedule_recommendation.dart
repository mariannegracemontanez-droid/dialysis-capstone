/// Result types for ScheduleRecommendationService.
///
/// A recommendation is a set of recurring DAY + DEFAULT SHIFT pairs --
/// the shift here is the patient's normal shift for that weekday, which
/// seeds the daily schedule. It is not a permanent booking: the actual
/// shift a patient receives on a specific date is still settled by the
/// center's daily first-come-first-served flow, which can move them.
library;

/// One recommended recurring slot.
class RecommendedSlot {
  final String day;
  final String shiftId;
  final String shiftCode;
  final String shiftLabel;

  const RecommendedSlot({
    required this.day,
    required this.shiftId,
    required this.shiftCode,
    required this.shiftLabel,
  });

  @override
  String toString() => '$day — $shiftLabel';
}

/// A single ranked recommendation (the algorithm returns up to 3, best
/// first).
class ScheduleRecommendation {
  final List<RecommendedSlot> slots;
  final double score;
  final List<String> reasons;
  final List<String> warnings;

  const ScheduleRecommendation({
    required this.slots,
    required this.score,
    required this.reasons,
    required this.warnings,
  });

  List<String> get days => slots.map((s) => s.day).toList();

  /// 0-100 rounded, for a UI badge like "92% Match".
  int get matchPercent => score.clamp(0, 100).round();

  /// Stable identity used to break scoring ties deterministically.
  String get signature => slots.map((s) => '${s.day}:${s.shiftCode}').join('|');
}

/// Day-level occupancy for one operating day, aggregated across shifts.
class DayOccupancy {
  final String day;
  final int scheduledPatients;
  final int targetCapacity;

  const DayOccupancy({
    required this.day,
    required this.scheduledPatients,
    required this.targetCapacity,
  });

  double get occupancyPercent =>
      targetCapacity <= 0 ? 0 : (scheduledPatients / targetCapacity) * 100;
}

/// The full result of generateSuggestedSchedule.
class ScheduleRecommendationResult {
  final bool success;

  /// Set when [success] is false -- e.g. the patient already has a
  /// schedule, or no combination of day/shift pairs fits within capacity.
  final String? blockReason;

  /// Up to 3, best first. Empty when [success] is false.
  final List<ScheduleRecommendation> recommendations;

  /// The occupancy snapshot used to generate the recommendations, so the
  /// UI can explain "why" without re-deriving it.
  final List<DayOccupancy> dayOccupancy;

  const ScheduleRecommendationResult({
    required this.success,
    required this.recommendations,
    required this.dayOccupancy,
    this.blockReason,
  });

  factory ScheduleRecommendationResult.blocked(
    String reason, {
    List<DayOccupancy> dayOccupancy = const [],
  }) {
    return ScheduleRecommendationResult(
      success: false,
      blockReason: reason,
      recommendations: const [],
      dayOccupancy: dayOccupancy,
    );
  }
}

/// Whether the center can take on a new patient, derived from the same
/// engine that produces recommendations -- never a separate rule set.
enum AcceptanceVerdict { canAccommodate, reviewRequired, cannotAccommodate }

class AcceptanceEvaluation {
  final AcceptanceVerdict verdict;
  final String headline;
  final String detail;
  final int sessionsPerWeek;

  /// Set when a valid schedule exists -- the very schedule that would be
  /// suggested after acceptance, so acceptance can never say "yes" to a
  /// patient the scheduler can't actually place.
  final ScheduleRecommendation? suggestion;

  const AcceptanceEvaluation({
    required this.verdict,
    required this.headline,
    required this.detail,
    required this.sessionsPerWeek,
    this.suggestion,
  });
}
