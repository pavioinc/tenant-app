/// Some backend `date` columns come back as a full ISO timestamp rather than a plain
/// `YYYY-MM-DD` string (tenant-service has no `pg` date-type-parser override — only
/// billing-service does, see its README) — same defensive truncation owner-dashboard's
/// `lib/api.ts` callers already apply to billing-service's date fields for the same
/// reason. Safe on an already-short date string too (`.split` on a string with no `T`
/// just returns the whole string in element 0).
String shortDate(String raw) => raw.split('T').first;
