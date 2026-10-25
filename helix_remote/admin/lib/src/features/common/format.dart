import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// "2026-10-02 14:03" in the operator's local time.
String formatTime(DateTime time) {
  final t = time.toLocal();
  return '${_date(t)} ${_two(t.hour)}:${_two(t.minute)}';
}

/// "2026-10-02" (the server only records the day a device was last seen).
String formatDay(DateTime time) => _date(time.toLocal());

String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// The first 8 characters of an id, enough to tell rows apart.
String shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

/// What the console calls [account]: the name the person gave themselves
/// (their app reports it, ADR-030), else their Helix name.
String accountTitle(AdminAccount account) {
  final name = account.displayName?.trim() ?? '';
  if (name.isNotEmpty) return name;
  final helix = account.helixName ?? '';
  return helix.isEmpty ? 'No Helix name' : helix;
}

/// The full number once the account's app has reported it and the server
/// keeps numbers (`HELIX_PHONE_KEY`, ADR-030), else the last four digits.
String accountPhone(AdminAccount account) {
  final number = account.phoneNumber ?? '';
  return number.isNotEmpty ? number : maskedPhone(account.phoneLast4);
}

/// A phone number as the server reports it: the last four digits only.
String maskedPhone(String? last4) =>
    last4 == null || last4.isEmpty ? 'No phone number' : '•••• $last4';

/// The two people a report is about, for the moderation queue (ADR-030).
/// The server joins each one's own name and full number onto the row; what
/// it did not join - an account whose app never reported, or a server with
/// no `HELIX_PHONE_KEY` - falls back to the id, or to no number at all.
/// These four are the console's only way in to a report's numbers.
String reportSubjectName(AdminReport report) =>
    _reportName(report.subjectName, report.subject);

/// The account that filed the report, named the same way.
String reportReporterName(AdminReport report) =>
    _reportName(report.reporterName, report.reporter);

/// The reported account's number, or null when the server has none to show.
String? reportSubjectPhone(AdminReport report) =>
    _reportPhone(report.subjectPhone);

/// The reporter's number, or null.
String? reportReporterPhone(AdminReport report) =>
    _reportPhone(report.reporterPhone);

String _reportName(String? name, String accountId) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? shortId(accountId) : trimmed;
}

String? _reportPhone(String? number) =>
    number == null || number.isEmpty ? null : number;

/// "12 MiB".
String formatBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// "1,234" for counts on the dashboard.
String formatCount(num value) {
  final digits = value.round().abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
