// The single interpretation of a center's stored `clinics.operating_hours`
// string for the whole Super Admin app.
//
// This replaces two separate implementations that disagreed about the same
// stored value -- center_page's `isCenterOpenByOperatingHours` and
// dashboard_page's `_isOpenNow` -- so the Centers page and the Dashboard can
// no longer reach different conclusions about the same center.
//
// The behaviour kept here is center_page's, because it was a strict superset:
// every case the two handled differently was one the dashboard version simply
// failed to parse and reported as "closed" (en/em dashes, "to"/"until",
// 24-hour times without AM/PM, overnight ranges, and open == close). There was
// no input the dashboard version read more correctly, so nothing here is a new
// business rule -- it is the more capable of the two existing behaviours,
// applied consistently.
//
// This is about operating hours ONLY. It has no bearing on the lifecycle
// `clinics.status == 'closed'` state or on the capacity-based Status shown in
// Center Management -- both of those are decided elsewhere and are unchanged.

import 'package:flutter/material.dart';

/// Whether [operatingHours] says the center is open at [now].
///
/// Returns false for a null/blank value, and for anything that cannot be
/// parsed -- an unreadable string is never treated as "open".
///
/// Accepted separators: `-`, `–` (en dash), `—` (em dash), ` to `, ` until `
/// (the word forms are case-insensitive).
///
/// Accepted times: `8`, `8:00`, `8 AM`, `8:00 AM`, `08:00` -- minutes and the
/// AM/PM suffix are each optional, and a time without AM/PM is read as a
/// 24-hour value. An hour outside 0-23 or a minute outside 0-59 is rejected
/// rather than silently wrapping.
///
/// Overnight ranges are supported: when the closing time is earlier than the
/// opening time the period is treated as crossing midnight, so `10:00 PM -
/// 2:00 AM` includes 11:00 PM and 1:00 AM but excludes 3:00 AM.
///
/// An opening time equal to the closing time means "always open", which is the
/// interpretation the existing Center Management parser already applied.
///
/// [now] defaults to the device's current local time, matching what both
/// previous implementations used. It is injectable so the behaviour can be
/// tested at a fixed time; no timezone conversion is performed here.
bool isWithinOperatingHours(String? operatingHours, {TimeOfDay? now}) {
  if (operatingHours == null || operatingHours.trim().isEmpty) return false;

  try {
    final normalized = operatingHours
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'\s+to\s+', caseSensitive: false), '-')
        .replaceAll(RegExp(r'\s+until\s+', caseSensitive: false), '-');

    final parts = normalized.split('-');
    if (parts.length < 2) return false;

    final openTime = _parseOperatingTime(parts[0]);
    final closeTime = _parseOperatingTime(parts[1]);
    final currentTime = now ?? TimeOfDay.now();

    final nowMinutes = (currentTime.hour * 60) + currentTime.minute;
    final openMinutes = (openTime.hour * 60) + openTime.minute;
    final closeMinutes = (closeTime.hour * 60) + closeTime.minute;

    if (openMinutes == closeMinutes) return true;

    // Handles overnight schedules like 8:00 PM - 6:00 AM.
    if (closeMinutes < openMinutes) {
      return nowMinutes >= openMinutes || nowMinutes <= closeMinutes;
    }

    return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
  } catch (_) {
    return false;
  }
}

/// Reads one side of an operating-hours range. Throws a [FormatException] for
/// anything unparseable or out of range, which [isWithinOperatingHours] turns
/// into "not open".
TimeOfDay _parseOperatingTime(String value) {
  final cleaned = value.trim().toUpperCase();
  final regex = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?');
  final match = regex.firstMatch(cleaned);

  if (match == null) {
    throw FormatException('Invalid operating hours format: $value');
  }

  var hour = int.parse(match.group(1)!);
  final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
  final period = match.group(3);

  if (period == 'PM' && hour != 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;

  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw FormatException('Invalid operating hours format: $value');
  }

  return TimeOfDay(hour: hour, minute: minute);
}
