/// Some backend `date` columns come back as a full ISO timestamp rather than a plain
/// `YYYY-MM-DD` string (tenant-service has no `pg` date-type-parser override — only
/// billing-service does, see its README) — same defensive truncation owner-dashboard's
/// `lib/api.ts` callers already apply to billing-service's date fields for the same
/// reason. Safe on an already-short date string too (`.split` on a string with no `T`
/// just returns the whole string in element 0).
String shortDate(String raw) => raw.split('T').first;

const _staleBannerMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// No `intl` dependency for a single call site — hand-rolled "Aug 18, 3:45 PM" in the
/// device's local time, for the offline stale-cache banner (see cached_fetch.dart).
String formatSyncedAt(DateTime dt) {
  final local = dt.toLocal();
  final hour24 = local.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final period = hour24 < 12 ? 'AM' : 'PM';
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_staleBannerMonths[local.month - 1]} ${local.day}, $hour12:$minute $period';
}
