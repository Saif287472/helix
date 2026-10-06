// Masks for anything that might reach a log, an error message or a
// terminal: the engine never prints full phone numbers or ids of other
// people (AGENTS.md security invariants).

/// `+88017*****01`: the country prefix and the last two digits.
String maskPhone(String number) {
  final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.length <= 6) return '*' * digits.length;
  return '${digits.substring(0, 4)}${'*' * (digits.length - 6)}'
      '${digits.substring(digits.length - 2)}';
}

/// `0192a4f0…` for an account, device or message id.
String shortId(String id) => id.length <= 8 ? id : '${id.substring(0, 8)}…';
