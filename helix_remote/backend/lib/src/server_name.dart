/// The admin-chosen display name for this server.
///
/// Shown to the server's own users - on the join screen before they
/// register, and in the app's Settings once they have - so that a
/// self-hosted deployment reads as "Rahman Family Server" rather than as a
/// bare hostname.
///
/// Stored in the `server_configuration` table under [serverNameConfigKey].
/// Absent means the admin never set one, and callers fall back to the
/// hostname.
library;

const serverNameConfigKey = 'server_name';

/// Longest name accepted. Long enough for "The Rahman Family's Server",
/// short enough to fit a Settings row and a join-screen heading on a
/// narrow phone without truncation.
const maxServerNameLength = 60;

/// Outcome of validating an admin-submitted server name.
sealed class ServerNameResult {
  const ServerNameResult();
}

/// The name is acceptable; [value] is the normalized form to persist.
final class ServerNameValid extends ServerNameResult {
  const ServerNameValid(this.value);

  final String value;
}

/// The admin cleared the name; the stored key should be removed and
/// callers fall back to the hostname.
final class ServerNameCleared extends ServerNameResult {
  const ServerNameCleared();
}

final class ServerNameInvalid extends ServerNameResult {
  const ServerNameInvalid(this.error);

  final String error;
}

/// Validates and normalizes an admin-submitted server name.
///
/// This value is rendered inside every user's app, so it gets stricter
/// treatment than a plain length check:
///
///  * surrounding whitespace is trimmed and internal runs are collapsed to
///    a single space, so a name can't be padded to push layout around.
///    This is what makes a pasted `Home\nServer` land as `Home Server`
///    rather than being refused over an invisible character;
///  * every other control character - NUL, BEL, the C1 block - is rejected
///    rather than stripped, since silently changing what an admin typed is
///    worse than telling them it isn't allowed;
///  * bidirectional override characters are rejected, since they can make
///    displayed text read differently from what is stored.
ServerNameResult validateServerName(String? raw) {
  if (raw == null) {
    return const ServerNameInvalid('server_name is required');
  }

  // Collapse internal whitespace runs before trimming so that a name made
  // only of spaces normalizes to empty and reads as "clear it".
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const ServerNameCleared();

  for (final rune in normalized.runes) {
    if (_isControl(rune)) {
      return const ServerNameInvalid(
        'server_name must not contain control characters',
      );
    }
    if (_isBidiControl(rune)) {
      return const ServerNameInvalid(
        'server_name must not contain text-direction override characters',
      );
    }
  }

  // Count user-perceived length in runes: a name of emoji would otherwise
  // hit the limit at a quarter of the visible characters.
  if (normalized.runes.length > maxServerNameLength) {
    return const ServerNameInvalid(
      'server_name must be $maxServerNameLength characters or fewer',
    );
  }

  return ServerNameValid(normalized);
}

bool _isControl(int rune) =>
    rune < 0x20 || (rune >= 0x7f && rune <= 0x9f);

/// LRE/RLE/PDF/LRO/RLO, LRI/RLI/FSI/PDI, and the deprecated LRM/RLM/ALM
/// marks - all of which reorder how following text is displayed.
bool _isBidiControl(int rune) =>
    (rune >= 0x202a && rune <= 0x202e) ||
    (rune >= 0x2066 && rune <= 0x2069) ||
    rune == 0x200e ||
    rune == 0x200f ||
    rune == 0x061c;
