import 'package:flutter/material.dart';

/// The Admin panel's one set of field validation rules.
///
/// ## Why this file exists
///
/// Validation used to be written inline at each save button, so the same
/// field was checked differently (or not at all) depending on which modal
/// it was in: the Edit Patient form accepted an empty email and a
/// letters-only phone number, the blood pressure form accepted a systolic
/// of 0, the login form posted a blank password to Supabase. Collecting
/// the rules here means a field of a given *kind* is checked the same way
/// everywhere, and the message the admin reads names the field and says
/// what is wrong with it.
///
/// ## Contract
///
/// Every function returns `null` when the value is acceptable, or a
/// ready-to-show sentence when it is not. That is deliberately the same
/// shape Flutter's own `FormFieldValidator` uses, so a rule can be passed
/// straight to a `TextFormField.validator` *or* checked by hand before a
/// save and handed to [AdminNotice.error]. Nothing here shows UI itself.
///
/// ## Bounds
///
/// The numeric limits below are not invented: each one either mirrors a
/// CHECK constraint that already exists in `supabase/` (session duration
/// 0-8h / 0-59m, capacity >= 0), or a range the app already enforced
/// somewhere (sessions per week 1-6). The rest are wide sanity bounds
/// meant only to catch a typo -- a 900 kg patient, a 4000 mmHg reading --
/// never to second-guess a clinician.
class AdminValidators {
  const AdminValidators._();

  // ------------------------------------------------------------ text

  /// Default cap for a single-line text field. Generous: the point is to
  /// stop a pasted document, not to ration typing.
  static const int defaultTextLimit = 120;

  /// A field that must be filled in.
  ///
  /// Whitespace does not count as filled -- a value of "   " is empty as
  /// far as anyone reading the record is concerned.
  static String? requiredText(
    String? value, {
    required String label,
    int minLength = 1,
    int maxLength = defaultTextLimit,
  }) {
    final text = (value ?? '').trim();

    if (text.isEmpty) {
      return 'Please enter the $label.';
    }

    if (text.length < minLength) {
      return 'The $label must be at least $minLength characters.';
    }

    if (text.length > maxLength) {
      return 'The $label is too long (maximum $maxLength characters).';
    }

    return null;
  }

  /// A field that may be left blank, but is length-checked when filled.
  static String? optionalText(
    String? value, {
    required String label,
    int maxLength = defaultTextLimit,
  }) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;

    if (text.length > maxLength) {
      return 'The $label is too long (maximum $maxLength characters).';
    }

    return null;
  }

  // ----------------------------------------------------------- email

  /// Deliberately permissive: one `@`, something either side, and a dot
  /// in the domain. Anything stricter starts rejecting addresses that are
  /// perfectly deliverable, and the real proof of an address is that mail
  /// to it arrives -- not a regex.
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? email(
    String? value, {
    String label = 'email address',
    bool required = true,
  }) {
    final text = (value ?? '').trim();

    if (text.isEmpty) {
      return required ? 'Please enter the $label.' : null;
    }

    if (text.length > 254) {
      return 'That $label is too long.';
    }

    if (!_emailPattern.hasMatch(text)) {
      return 'Please enter a valid $label, for example name@example.com.';
    }

    return null;
  }

  // ----------------------------------------------------------- phone

  /// Counts digits rather than matching a format, so +63, 09xx, spaces,
  /// dashes and parentheses are all accepted. Seven digits is the
  /// shortest real landline; fifteen is the E.164 maximum.
  static String? phone(
    String? value, {
    String label = 'phone number',
    bool required = true,
  }) {
    final text = (value ?? '').trim();

    if (text.isEmpty) {
      return required ? 'Please enter the $label.' : null;
    }

    if (RegExp(r'[^0-9+()\-\s]').hasMatch(text)) {
      return 'The $label may only contain digits, spaces, +, - and ( ).';
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length < 7 || digits.length > 15) {
      return 'Please enter a valid $label (7 to 15 digits).';
    }

    return null;
  }

  // ---------------------------------------------------------- number

  /// A whole, non-negative-by-default number such as a machine count or
  /// a shift capacity.
  static String? wholeNumber(
    String? value, {
    required String label,
    int min = 0,
    int max = 1000000,
    bool required = true,
  }) {
    final text = (value ?? '').trim();

    if (text.isEmpty) {
      return required ? 'Please enter the $label.' : null;
    }

    final parsed = int.tryParse(text);

    if (parsed == null) {
      // Caught separately from the range check so "3.5" and "abc" get an
      // answer about what they actually are, not a bare range.
      return double.tryParse(text) != null
          ? 'The $label must be a whole number.'
          : 'Please enter a valid $label (numbers only).';
    }

    if (parsed < min) {
      return min == 0
          ? 'The $label cannot be negative.'
          : 'The $label must be at least $min.';
    }

    if (parsed > max) {
      return 'The $label cannot be more than $max.';
    }

    return null;
  }

  /// A measurement that may have a decimal part, such as a weight.
  static String? decimalNumber(
    String? value, {
    required String label,
    double min = 0,
    double max = 1000000,
    bool required = true,
    bool allowZero = false,
  }) {
    final text = (value ?? '').trim();

    if (text.isEmpty) {
      return required ? 'Please enter the $label.' : null;
    }

    final parsed = double.tryParse(text);

    if (parsed == null) {
      return 'Please enter a valid $label (numbers only).';
    }

    if (!parsed.isFinite) {
      return 'Please enter a valid $label.';
    }

    if (!allowZero && parsed == 0) {
      return 'The $label must be greater than zero.';
    }

    if (parsed < min) {
      return 'The $label must be at least ${_trim(min)}.';
    }

    if (parsed > max) {
      return 'The $label cannot be more than ${_trim(max)}.';
    }

    return null;
  }

  static String _trim(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }

  // -------------------------------------------------- clinical values

  /// Wide sanity bounds only. Anything inside them is a clinical
  /// judgement the app has no business overruling.
  static String? weightKg(String? value, {required String label}) {
    return decimalNumber(value, label: label, min: 1, max: 400);
  }

  /// Checks the pair together, because the pair is what makes a reading
  /// wrong: a systolic below its own diastolic is a transposed entry, not
  /// a patient.
  static String? bloodPressure({
    required String? systolic,
    required String? diastolic,
    String systolicLabel = 'systolic reading',
    String diastolicLabel = 'diastolic reading',
  }) {
    final systolicError = wholeNumber(
      systolic,
      label: systolicLabel,
      min: 40,
      max: 300,
    );
    if (systolicError != null) return systolicError;

    final diastolicError = wholeNumber(
      diastolic,
      label: diastolicLabel,
      min: 20,
      max: 200,
    );
    if (diastolicError != null) return diastolicError;

    final sys = int.parse(systolic!.trim());
    final dia = int.parse(diastolic!.trim());

    if (sys <= dia) {
      return 'The systolic reading must be higher than the diastolic '
          'reading (entered $sys/$dia).';
    }

    return null;
  }

  // ------------------------------------------------------------ time

  /// Minutes since midnight -- the comparable form of a [TimeOfDay].
  static int minutesOf(TimeOfDay time) => time.hour * 60 + time.minute;

  /// A start/end pair on the same day.
  ///
  /// [label] names what the range is ("AM shift", "operating hours") so
  /// the message points at the row that is wrong when several are on
  /// screen at once.
  static String? timeRange({
    required TimeOfDay? start,
    required TimeOfDay? end,
    required String label,
  }) {
    if (start == null || end == null) {
      return 'Please set both a start time and an end time for the $label.';
    }

    final startMinutes = minutesOf(start);
    final endMinutes = minutesOf(end);

    if (startMinutes == endMinutes) {
      return 'The $label start time and end time cannot be the same.';
    }

    if (startMinutes > endMinutes) {
      return 'The $label start time must be earlier than its end time.';
    }

    return null;
  }

  /// Two ranges that must not overlap -- the AM and PM shifts of one day.
  static String? nonOverlappingRanges({
    required TimeOfDay firstStart,
    required TimeOfDay firstEnd,
    required String firstLabel,
    required TimeOfDay secondStart,
    required TimeOfDay secondEnd,
    required String secondLabel,
  }) {
    final overlaps =
        minutesOf(firstStart) < minutesOf(secondEnd) &&
        minutesOf(secondStart) < minutesOf(firstEnd);

    if (!overlaps) return null;

    return 'The $firstLabel and the $secondLabel overlap. '
        'Adjust their times so the two do not run at the same hours.';
  }

  /// A range that must sit inside another -- a shift inside the center's
  /// operating hours.
  static String? rangeWithin({
    required TimeOfDay start,
    required TimeOfDay end,
    required TimeOfDay outerStart,
    required TimeOfDay outerEnd,
    required String label,
    required String outerLabel,
  }) {
    if (minutesOf(start) >= minutesOf(outerStart) &&
        minutesOf(end) <= minutesOf(outerEnd)) {
      return null;
    }

    return 'The $label runs outside the $outerLabel '
        '(${formatTime(outerStart)} - ${formatTime(outerEnd)}). '
        'Widen the $outerLabel or move the $label inside them.';
  }

  // ------------------------------------------------------------ dates

  /// A date of birth or a session date: real, not in the future, and not
  /// absurdly far back.
  static String? pastDate(
    DateTime? value, {
    required String label,
    bool required = true,
    int maxYearsAgo = 130,
  }) {
    if (value == null) {
      return required ? 'Please choose the $label.' : null;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);

    if (day.isAfter(today)) {
      return 'The $label cannot be in the future.';
    }

    if (day.isBefore(DateTime(now.year - maxYearsAgo, now.month, now.day))) {
      return 'Please check the $label -- it is more than $maxYearsAgo '
          'years ago.';
    }

    return null;
  }

  // -------------------------------------------------- time formatting

  /// `HH:mm:ss`, the shape Postgres `time` columns round-trip as and the
  /// shape clinic_shifts.start_time / end_time are already stored in.
  static String toSqlTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  /// Parses `HH:mm`, `HH:mm:ss` or `H:mm AM/PM` back into a [TimeOfDay].
  /// Returns null for anything it cannot read, so a caller can fall back
  /// rather than silently landing on midnight.
  static TimeOfDay? parseTime(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;

    final match = RegExp(
      r'^(\d{1,2})\s*:\s*(\d{2})(?:\s*:\s*\d{2})?\s*([AaPp])?\.?[Mm]?\.?$',
    ).firstMatch(text);

    if (match == null) return null;

    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    final meridiem = match.group(3)?.toUpperCase();

    if (hour == null || minute == null) return null;
    if (minute < 0 || minute > 59) return null;

    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      if (meridiem == 'A') {
        hour = hour == 12 ? 0 : hour;
      } else {
        hour = hour == 12 ? 12 : hour + 12;
      }
    }

    if (hour < 0 || hour > 23) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  /// `7:00 AM` -- the display form the mobile app's clinic pages and the
  /// Super Admin's operating-hours default already use, so a value this
  /// panel writes reads identically everywhere it is shown.
  static String formatTime(TimeOfDay time) {
    final isPm = time.hour >= 12;
    var hour = time.hour % 12;
    if (hour == 0) hour = 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${isPm ? 'PM' : 'AM'}';
  }

  /// `7:00 AM - 5:00 PM` -- the single string stored in
  /// clinics.operating_hours.
  static String formatRange(TimeOfDay start, TimeOfDay end) {
    return '${formatTime(start)} - ${formatTime(end)}';
  }

  /// Reads a stored `operating_hours` string back into its two times.
  /// Returns null when the stored value is free text this panel did not
  /// write, so the caller can say so instead of guessing.
  static ({TimeOfDay start, TimeOfDay end})? parseRange(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;

    final parts = text.split(
      RegExp(r'\s*(?:-|–|—|to)\s*', caseSensitive: false),
    );
    if (parts.length != 2) return null;

    final start = parseTime(parts[0]);
    final end = parseTime(parts[1]);

    if (start == null || end == null) return null;

    return (start: start, end: end);
  }

  // ------------------------------------------------------- composition

  /// Returns the first failure from a list of checks, or null when they
  /// all pass. Lets a save handler read as a list of rules rather than a
  /// ladder of early returns.
  static String? firstError(List<String? Function()> checks) {
    for (final check in checks) {
      final error = check();
      if (error != null) return error;
    }
    return null;
  }
}
