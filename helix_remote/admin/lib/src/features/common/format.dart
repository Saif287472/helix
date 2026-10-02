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

/// A phone number as the server reports it: the last four digits only.
String maskedPhone(String? last4) =>
    last4 == null || last4.isEmpty ? 'No phone number' : '•••• $last4';

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
