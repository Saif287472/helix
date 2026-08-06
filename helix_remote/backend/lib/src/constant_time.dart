/// Comparison helpers for values where an early return leaks information.
///
/// Dart's `==` on `String` short-circuits at the first differing code unit, so
/// the time it takes to reject a wrong value depends on how much of the prefix
/// was right. For a bearer token or a MAC that is a (weak, but real) oracle:
/// an attacker who can measure enough samples can recover the secret one
/// character at a time instead of guessing it whole.
///
/// Remote timing attacks across a network are genuinely hard, and nothing here
/// is a substitute for rate limiting. But the fix is a few lines and the
/// alternative is arguing about exploitability every time someone reads the
/// code.
library;

import 'dart:convert';

/// Compares two byte lists without returning early.
///
/// The loop always runs to the end of the longer list, accumulating
/// differences into [mismatch] rather than branching on them. Length
/// inequality is folded into the same accumulator so that a wrong-length
/// input costs the same as a wrong-content one.
bool constantTimeBytesEqual(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  // Non-zero when the lengths differ, so a short input cannot pass by
  // matching only the prefix that exists.
  var mismatch = a.length ^ b.length;
  for (var i = 0; i < length; i++) {
    // Out-of-range positions read as -1, a value no byte can equal, so a
    // shorter input never scores a match on the overhang.
    final x = i < a.length ? a[i] : -1;
    final y = i < b.length ? b[i] : -1;
    mismatch |= x ^ y;
  }
  return mismatch == 0;
}

/// Compares two strings without returning early.
///
/// Encodes to UTF-8 first so the comparison is over bytes rather than UTF-16
/// code units; for the ASCII tokens and base64/hex digests this is used on,
/// the two are the same, and for anything else byte comparison is the more
/// defensible choice.
bool constantTimeStringEqual(String a, String b) =>
    constantTimeBytesEqual(utf8.encode(a), utf8.encode(b));
