enum ReadinessLevel { normal, caution, critical }

class ReadinessFinding {
  final String message;
  final ReadinessLevel level;

  ReadinessFinding(this.message, this.level);
}

class DialysisReadinessResult {
  final ReadinessLevel level;
  final String verdict;
  final List<ReadinessFinding> findings;

  DialysisReadinessResult({
    required this.level,
    required this.verdict,
    required this.findings,
  });
}

/// Rule-based analysis of admin-entered BP and weight readings, judging
/// whether the values recorded for a dialysis session look appropriate.
/// Not a diagnostic tool — flags values outside typical safe ranges for a
/// dialysis patient so they can be reviewed by the clinic.
class DialysisReadinessAnalyzer {
  static DialysisReadinessResult analyze({
    int? systolic,
    int? diastolic,
    double? beforeWeight,
    double? afterWeight,
  }) {
    final findings = <ReadinessFinding>[];

    if (systolic != null && diastolic != null) {
      if (systolic >= 180 || diastolic >= 120) {
        findings.add(
          ReadinessFinding(
            'Blood pressure ($systolic/$diastolic mmHg) is critically high — '
            'this needs immediate medical attention before or during dialysis.',
            ReadinessLevel.critical,
          ),
        );
      } else if (systolic < 90 || diastolic < 60) {
        findings.add(
          ReadinessFinding(
            'Blood pressure ($systolic/$diastolic mmHg) is low — there is a '
            'risk of intradialytic hypotension.',
            ReadinessLevel.caution,
          ),
        );
      } else if (systolic >= 140 || diastolic >= 90) {
        findings.add(
          ReadinessFinding(
            'Blood pressure ($systolic/$diastolic mmHg) is elevated for a '
            'dialysis patient and should be monitored closely.',
            ReadinessLevel.caution,
          ),
        );
      } else {
        findings.add(
          ReadinessFinding(
            'Blood pressure ($systolic/$diastolic mmHg) is within a safe '
            'range for dialysis.',
            ReadinessLevel.normal,
          ),
        );
      }
    }

    if (beforeWeight != null && afterWeight != null && beforeWeight > 0) {
      final removedKg = beforeWeight - afterWeight;
      final percent = (removedKg / beforeWeight) * 100;

      if (removedKg < 0) {
        findings.add(
          ReadinessFinding(
            'Weight increased after the session '
            '(${beforeWeight.toStringAsFixed(1)}kg → ${afterWeight.toStringAsFixed(1)}kg) '
            '— this is unusual and should be reviewed by the care team.',
            ReadinessLevel.caution,
          ),
        );
      } else if (percent > 6) {
        findings.add(
          ReadinessFinding(
            'Fluid removed during the session was ${percent.toStringAsFixed(1)}% '
            'of body weight — a large removal that raises the risk of cramping '
            'or low blood pressure.',
            ReadinessLevel.critical,
          ),
        );
      } else if (percent > 5) {
        findings.add(
          ReadinessFinding(
            'Fluid removed during the session was ${percent.toStringAsFixed(1)}% '
            'of body weight — on the higher end and worth monitoring.',
            ReadinessLevel.caution,
          ),
        );
      } else {
        findings.add(
          ReadinessFinding(
            'Fluid removed during the session (${percent.toStringAsFixed(1)}% '
            'of body weight) is within a typical safe range.',
            ReadinessLevel.normal,
          ),
        );
      }
    }

    if (findings.isEmpty) {
      return DialysisReadinessResult(
        level: ReadinessLevel.normal,
        verdict: 'No blood pressure or weight readings available yet to analyze.',
        findings: findings,
      );
    }

    final level = findings.any((f) => f.level == ReadinessLevel.critical)
        ? ReadinessLevel.critical
        : findings.any((f) => f.level == ReadinessLevel.caution)
        ? ReadinessLevel.caution
        : ReadinessLevel.normal;

    final verdict = level == ReadinessLevel.critical
        ? 'Needs immediate attention'
        : level == ReadinessLevel.caution
        ? 'Needs monitoring'
        : 'Appropriate for dialysis';

    return DialysisReadinessResult(
      level: level,
      verdict: verdict,
      findings: findings,
    );
  }
}
