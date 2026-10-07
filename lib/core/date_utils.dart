/// Some backend `date` columns come back as a full ISO timestamp rather than a plain
/// `YYYY-MM-DD` string (tenant-service has no `pg` date-type-parser override — only
/// billing-service does, see its README) — same defensive truncation owner-dashboard's
/// `lib/api.ts` callers already apply to billing-service's date fields for the same
/// reason. Safe on an already-short date string too (`.split` on a string with no `T`
/// just returns the whole string in element 0).
String shortDate(String raw) => raw.split('T').first;

const _monthAbbr = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// 1 (January) - 12 (December) → full name, for the one-line "which month" copy Lease's
/// renewal card and Payments' due-date hero both compose ("ends in February", "Friday 5
/// September").
String fullMonthName(int month) => _monthNames[month - 1];

/// "2026-09-05" → "Friday 5 September" — no year, full weekday and month, matching how a
/// renter actually reads a due date rather than the abbreviated calendar-entry shape
/// [formatDisplayDate] uses everywhere else. Falls back to the input unchanged if it
/// isn't `YYYY-MM-DD` shaped, same defensive posture as formatDisplayDate.
String formatDueDate(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  return '${_weekdayNames[date.weekday - 1]} ${date.day} ${_monthNames[date.month - 1]}';
}

/// No `intl` dependency for a single call site — hand-rolled "Aug 18, 3:45 PM" in the
/// device's local time, for the offline stale-cache banner (see cached_fetch.dart).
String formatSyncedAt(DateTime dt) {
  final local = dt.toLocal();
  final hour24 = local.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final period = hour24 < 12 ? 'AM' : 'PM';
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_monthAbbr[local.month - 1]} ${local.day}, $hour12:$minute $period';
}

/// "2026-08-31" → "6 days ago" (today is 2026-09-06) — Maintenance's own list cards (doc
/// option "1e") used to print `item.createdAt` straight to screen; day-granularity only,
/// matching what a renter actually thinks in ("a few days ago", not "14 hours ago").
/// Older than a month, this falls back to [formatDisplayDate] rather than an
/// ever-growing "47 days ago". Falls back to the input unchanged if it isn't
/// `YYYY-MM-DD` shaped.
String formatRelativeDate(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  final today = DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final startOfThat = DateTime(date.year, date.month, date.day);
  final days = startOfToday.difference(startOfThat).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 30) return '$days days ago';
  return formatDisplayDate(shortDate(isoDate));
}

/// "2026-08-20" → "20 Aug 2026" — for any already-`shortDate`d date rendered directly to
/// the renter (Maintenance timestamps, Lease/agreement dates, transaction history, guest
/// visit dates), replacing the raw ISO string most screens printed as-is. Falls back to
/// the input unchanged if it isn't `YYYY-MM-DD` shaped, rather than throwing on
/// unexpected backend data.
String formatDisplayDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null || month < 1 || month > 12) {
    return isoDate;
  }
  return '$day ${_monthAbbr[month - 1]} $year';
}
