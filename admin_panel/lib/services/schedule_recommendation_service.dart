import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/center_schedule.dart';
import '../models/schedule_recommendation.dart';
import 'center_schedule_service.dart';

/// Deterministic weekly schedule recommendation for dialysis patients,
/// and the acceptance evaluation built on the very same engine.
///
/// It never writes anything: it reads the center's capacity snapshot and
/// returns ranked day + default-shift schedules for staff to review,
/// adjust and save through CenterScheduleService.setPatientRecurringSchedule.
///
/// Scheduling model
/// ----------------
/// The recommendation is not "find any free slot". It works from the
/// patient's required sessions per week and evaluates whole weekly
/// combinations, scoring how well each one spreads sessions across the
/// week as well as how much room it leaves the center. The recurring
/// shift it returns is the patient's DEFAULT shift, which seeds the
/// daily schedule -- the actual shift on a specific date is still
/// settled by the center's first-come-first-served daily flow.
///
/// Clinical scope
/// --------------
/// Only scheduling constraints the system actually models are applied:
/// required frequency, operating days, shift availability, configured
/// capacity, and even distribution across the week. No clinical rule
/// beyond those is inferred. Anything further (minimum/maximum interdialytic
/// interval, shift suitability for specific conditions) needs clinical
/// confirmation and a configurable field before it can be enforced --
/// see [distributionNote].
class ScheduleRecommendationService {
  final SupabaseClient supabase = Supabase.instance.client;
  final CenterScheduleService _centerScheduleService = CenterScheduleService();

  /// Standard hemodialysis frequency, used only when a patient row
  /// doesn't have sessions_per_week set yet. Surfaced to the UI as an
  /// assumption rather than silently applied.
  static const int defaultSessionsPerWeek = 3;

  /// The two alternating day patterns dialysis centers actually run.
  /// Suggestions are drawn from these rather than from every arithmetic
  /// combination of free days, so a recommendation is always a real
  /// rotation the center can staff -- never something like Mon/Tue/Wed.
  static const List<List<String>> standardPatterns = [
    ['Monday', 'Wednesday', 'Friday'],
    ['Tuesday', 'Thursday', 'Saturday'],
  ];

  /// The distribution component rewards spreading sessions evenly across
  /// the operating week. That is an operational spacing preference the
  /// system can justify from its own data -- it is deliberately NOT
  /// presented as a clinical interval rule, which would need clinician
  /// sign-off and a configurable minimum/maximum gap.
  static const String distributionNote =
      'Sessions are spread across the week using the center\'s operating '
      'days. Clinically specific interdialytic interval rules are not '
      'applied and would need to be configured and clinically confirmed.';

  // Scoring weights. Named constants, summing to 100, so a score reads
  // naturally as a percentage and the formula stays inspectable.
  static const double _capacityWeight = 40;
  static const double _distributionWeight = 35;
  static const double _shiftConsistencyWeight = 15;
  static const double _workloadBalanceWeight = 10;

  static const int maxRecommendations = 3;

  Future<int?> getSessionsPerWeek(String patientId) =>
      _centerScheduleService.getSessionsPerWeek(patientId);

  // ------------------------------------------------------------------
  // Recommendation
  // ------------------------------------------------------------------

  Future<ScheduleRecommendationResult> generateSuggestedSchedule({
    required String patientId,
    required String clinicId,
    int? sessionsPerWeekOverride,
  }) async {
    final existing =
        await _centerScheduleService.getPatientRecurringSchedule(patientId);
    if (existing != null && existing.isActive) {
      return ScheduleRecommendationResult.blocked(
        'This patient already has an active weekly schedule.',
      );
    }

    final sessionsPerWeek = sessionsPerWeekOverride ??
        await _centerScheduleService.getSessionsPerWeek(patientId) ??
        defaultSessionsPerWeek;

    final snapshot = await _centerScheduleService.getCapacitySnapshot(clinicId);

    return buildRecommendation(
      snapshot: snapshot,
      sessionsPerWeek: sessionsPerWeek,
    );
  }

  /// The pure ranking step, separated from data loading so the
  /// acceptance evaluation can reuse an existing snapshot instead of
  /// running a second, potentially divergent analysis.
  ScheduleRecommendationResult buildRecommendation({
    required CenterCapacitySnapshot snapshot,
    required int sessionsPerWeek,
  }) {
    final dayOccupancy = [
      for (final day in snapshot.days)
        DayOccupancy(
          day: day.day,
          scheduledPatients: day.scheduled,
          targetCapacity: day.capacity,
        ),
    ];

    if (!snapshot.isConfigured) {
      return ScheduleRecommendationResult.blocked(
        "This center's operating days and shifts are not configured yet.",
        dayOccupancy: dayOccupancy,
      );
    }

    if (sessionsPerWeek <= 0) {
      return ScheduleRecommendationResult.blocked(
        'This patient has no required number of sessions per week.',
        dayOccupancy: dayOccupancy,
      );
    }

    // A day is usable only if the center operates then AND at least one
    // active shift still has room.
    final usableDays = snapshot.days
        .where((d) => d.isOperating && d.shifts.any((s) => !s.isFull))
        .map((d) => d.day)
        .toList();

    if (usableDays.length < sessionsPerWeek) {
      return ScheduleRecommendationResult.blocked(
        'This patient requires $sessionsPerWeek session(s)/week, but only '
        '${usableDays.length} operating day(s) still have available shift '
        'capacity at this center.',
        dayOccupancy: dayOccupancy,
      );
    }

    final combinations = _candidateDaySets(usableDays, sessionsPerWeek);

    if (combinations.isEmpty) {
      return ScheduleRecommendationResult.blocked(
        'Neither standard rotation (Monday/Wednesday/Friday or '
        'Tuesday/Thursday/Saturday) currently has enough available shift '
        'capacity for $sessionsPerWeek session(s) per week.',
        dayOccupancy: dayOccupancy,
      );
    }

    final candidates = <ScheduleRecommendation>[];

    for (final combo in combinations) {
      final slots = <RecommendedSlot>[];
      final warnings = <String>[];
      var totalAvailabilityRatio = 0.0;
      var nearCapacityCount = 0;

      for (final day in combo) {
        final dayCapacity = snapshot.dayByName(day);
        if (dayCapacity == null) continue;

        final chosen = _pickShift(dayCapacity);
        if (chosen == null) break;

        slots.add(
          RecommendedSlot(
            day: day,
            shiftId: chosen.shift.id,
            shiftCode: chosen.shift.shiftCode,
            shiftLabel: chosen.shift.displayLabel,
          ),
        );

        totalAvailabilityRatio += chosen.effectiveCapacity <= 0
            ? 0.0
            : chosen.available / chosen.effectiveCapacity;

        if (chosen.utilization >= CenterScheduleService.nearCapacityThreshold) {
          nearCapacityCount++;
          warnings.add(
            '${chosen.shift.displayLabel} on $day is near capacity '
            '(${chosen.scheduled}/${chosen.effectiveCapacity}).',
          );
        }
      }

      // A combination is only valid if every day got a usable shift.
      if (slots.length != combo.length) continue;

      final avgAvailability = totalAvailabilityRatio / slots.length;
      final spacing = _spacingRatio(combo, snapshot.operatingDays);
      final shiftConsistency = _shiftConsistency(slots);
      final workloadBalance = _workloadBalance(combo, snapshot);

      final score = (_capacityWeight * avgAvailability) +
          (_distributionWeight * spacing) +
          (_shiftConsistencyWeight * shiftConsistency) +
          (_workloadBalanceWeight * workloadBalance);

      final reasons = <String>[
        'Meets the required $sessionsPerWeek session(s) per week.',
        if (spacing >= 0.8)
          'Sessions are evenly distributed across the operating week.'
        else
          'Sessions fit the days the center still has capacity for.',
        if (avgAvailability >= 0.4)
          'Selected shifts have good remaining capacity.'
        else if (nearCapacityCount == 0)
          "Stays within the center's configured shift capacity.",
        if (shiftConsistency == 1)
          'Keeps the patient on the same shift every session.',
      ];

      candidates.add(
        ScheduleRecommendation(
          slots: slots,
          score: score,
          reasons: reasons,
          warnings: warnings,
        ),
      );
    }

    if (candidates.isEmpty) {
      return ScheduleRecommendationResult.blocked(
        'No suitable weekly schedule could be built from the center\'s '
        'currently available day and shift capacity.',
        dayOccupancy: dayOccupancy,
      );
    }

    // Deterministic ordering: score first, then a stable signature so
    // equal-scoring schedules always come back in the same order.
    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.signature.compareTo(b.signature);
    });

    return ScheduleRecommendationResult(
      success: true,
      recommendations: candidates.take(maxRecommendations).toList(),
      dayOccupancy: dayOccupancy,
    );
  }

  /// Picks the default shift for a day: most remaining room wins, ties
  /// broken by the shift's own ordering (earliest start time first, as
  /// loaded), so the same center state always yields the same shift.
  ShiftCapacity? _pickShift(DayCapacity day) {
    ShiftCapacity? best;

    for (final candidate in day.shifts) {
      if (candidate.isFull || !candidate.shift.isActive) continue;
      if (best == null || candidate.available > best.available) {
        best = candidate;
      }
    }

    return best;
  }

  /// 1.0 = ideal even spacing across the center's operating days. A
  /// single-session schedule has nothing to space out.
  double _spacingRatio(List<String> combo, List<String> operatingDays) {
    if (combo.length <= 1) return 1.0;

    final indices = combo.map(operatingDays.indexOf).where((i) => i >= 0).toList()
      ..sort();
    if (indices.length <= 1) return 1.0;

    final gaps = [
      for (var i = 1; i < indices.length; i++) indices[i] - indices[i - 1],
    ];
    final minGap = gaps.reduce((a, b) => a < b ? a : b);
    final idealGap = (operatingDays.length - 1) / (combo.length - 1);
    if (idealGap <= 0) return 1.0;

    final ratio = minGap / idealGap;
    return ratio > 1 ? 1.0 : ratio;
  }

  /// Rewards keeping the patient on one shift all week -- easier for the
  /// patient and for the center's daily first-come-first-served flow.
  double _shiftConsistency(List<RecommendedSlot> slots) {
    if (slots.length <= 1) return 1.0;
    final codes = slots.map((s) => s.shiftCode).toSet();
    return codes.length == 1 ? 1.0 : 1.0 / codes.length;
  }

  /// Nudges toward the center's overall quieter days, on top of the raw
  /// shift-level capacity score.
  double _workloadBalance(List<String> combo, CenterCapacitySnapshot snapshot) {
    var total = 0.0;

    for (final day in combo) {
      final dayCapacity = snapshot.dayByName(day);
      if (dayCapacity == null || dayCapacity.capacity <= 0) continue;
      // clamp() is declared on num and returns num, so convert
      // explicitly rather than letting it widen the arithmetic.
      final used =
          (dayCapacity.scheduled / dayCapacity.capacity).clamp(0, 1).toDouble();
      total += 1 - used;
    }

    return combo.isEmpty ? 0.0 : total / combo.length;
  }

  /// Candidate day sets, drawn from the two standard rotations rather
  /// than every possible combination of free days.
  ///
  /// A pattern qualifies only if every one of its days is usable, so a
  /// rotation is never suggested with a closed or full day in it. Fewer
  /// than three sessions takes the leading days of each pattern (still
  /// alternating, e.g. Monday/Wednesday). More than three can't be
  /// expressed as one rotation, so that case falls back to evaluating
  /// combinations of the usable days.
  List<List<String>> _candidateDaySets(List<String> usableDays, int sessions) {
    if (sessions > standardPatterns.first.length) {
      return _combinations(usableDays, sessions);
    }

    final usable = usableDays.toSet();
    final candidates = <List<String>>[];

    for (final pattern in standardPatterns) {
      final days = pattern.take(sessions).toList();
      if (days.length == sessions && days.every(usable.contains)) {
        candidates.add(days);
      }
    }

    return candidates;
  }

  List<List<String>> _combinations(List<String> items, int k) {
    if (k <= 0 || k > items.length) return [];

    final results = <List<String>>[];

    void combine(int start, List<String> current) {
      if (current.length == k) {
        results.add(List<String>.from(current));
        return;
      }

      for (var i = start; i < items.length; i++) {
        current.add(items[i]);
        combine(i + 1, current);
        current.removeLast();
      }
    }

    combine(0, []);
    return results;
  }

  // ------------------------------------------------------------------
  // New patient acceptance
  // ------------------------------------------------------------------

  /// Answers "can this center actually accommodate this patient?" by
  /// running the same recommendation engine used after acceptance -- so
  /// acceptance can never say yes to a patient the scheduler then can't
  /// place. Read-only: it decides nothing on its own, it informs the
  /// admin's decision.
  Future<AcceptanceEvaluation> evaluateAcceptance({
    required String patientId,
    required String clinicId,
  }) async {
    final storedSessions =
        await _centerScheduleService.getSessionsPerWeek(patientId);
    final sessionsPerWeek = storedSessions ?? defaultSessionsPerWeek;

    final snapshot = await _centerScheduleService.getCapacitySnapshot(clinicId);
    final result = buildRecommendation(
      snapshot: snapshot,
      sessionsPerWeek: sessionsPerWeek,
    );

    final assumedNote = storedSessions == null
        ? ' Required frequency is not recorded for this patient, so the '
            'standard $defaultSessionsPerWeek sessions/week was assumed.'
        : '';

    if (!result.success || result.recommendations.isEmpty) {
      return AcceptanceEvaluation(
        verdict: AcceptanceVerdict.cannotAccommodate,
        headline: 'Cannot accommodate',
        detail:
            '${result.blockReason ?? 'No valid weekly schedule could be built.'}'
            '$assumedNote',
        sessionsPerWeek: sessionsPerWeek,
      );
    }

    final best = result.recommendations.first;
    // Days only: the shift the engine used to prove capacity exists is
    // not presented as an assignment -- staff choose the default shift
    // themselves when the schedule is actually created.
    final schedule = best.days.join(', ');

    if (best.warnings.isNotEmpty) {
      return AcceptanceEvaluation(
        verdict: AcceptanceVerdict.reviewRequired,
        headline: 'Limited — review required',
        detail:
            'A complete weekly schedule is possible ($schedule), but some of '
            'those shifts are already near capacity.$assumedNote',
        sessionsPerWeek: sessionsPerWeek,
        suggestion: best,
      );
    }

    return AcceptanceEvaluation(
      verdict: AcceptanceVerdict.canAccommodate,
      headline: 'Can accommodate',
      detail:
          'The center has compatible capacity for $sessionsPerWeek session(s) '
          'per week ($schedule).$assumedNote',
      sessionsPerWeek: sessionsPerWeek,
      suggestion: best,
    );
  }
}
