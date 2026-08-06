/// Account identifiers that a client may never claim at registration.
///
/// `account_id` is chosen by the client and only ever bound into a transcript
/// the client signs with its *own* key, so the signature proves the client
/// committed to the value — not that the value is legitimately theirs. Until
/// admin became a real capability (see `accounts.is_admin`), the literal
/// string `'admin'` *was* the admin credential, so whoever registered it first
/// obtained the operator console. That hole is closed by the capability
/// change; this list is the second layer, so a future refactor that
/// reintroduces a name-based check cannot silently reopen it.
///
/// Matching is case-insensitive and ignores surrounding whitespace, because
/// `'Admin'` and `' admin '` are the same claim to a human reader and the
/// point of the list is to stop the impersonation, not to be pedantic about
/// byte equality.
library;

/// Synthetic `account_id` attached to requests authenticated by the static
/// admin API token. No account row exists behind it — the token carries the
/// operator capability directly. It appears in audit entries so operator
/// actions are attributable to *something*, and it is safe to use precisely
/// because [kReservedAccountIds] makes it unregisterable.
const String kAdminTokenAccountId = 'admin';

const Set<String> kReservedAccountIds = {
  'admin',
  'administrator',
  'root',
  'superuser',
  'sysadmin',
  'system',
  'helix',
  'support',
  'security',
  'moderator',
  'operator',
  'server',
  'service',
  'null',
  'undefined',
  'me',
  'self',
};

/// Whether [accountId] is reserved and must be refused at registration.
bool isReservedAccountId(String accountId) =>
    kReservedAccountIds.contains(accountId.trim().toLowerCase());

/// Returns an error message when [accountId] is unacceptable, or null when it
/// is fine.
///
/// The length and character bounds are deliberately loose. The real client
/// derives the value from its identity public key (16 lowercase hex
/// characters), so a tight rule could be enforced — but existing deployments
/// hold accounts created before any rule existed, and tightening the format
/// is a data migration, not a validation change. These bounds only reject
/// values that no honest client would ever send: empty, absurdly long, or
/// containing characters that would make the id unsafe to embed in a log
/// line, a path segment, or a JSON key.
String? accountIdError(String? accountId) {
  if (accountId == null || accountId.isEmpty) {
    return 'account_id is required';
  }
  if (accountId.length > 64) {
    return 'account_id must be at most 64 characters';
  }
  if (accountId.trim() != accountId) {
    return 'account_id must not have leading or trailing whitespace';
  }
  if (!RegExp(r'^[A-Za-z0-9._@-]+$').hasMatch(accountId)) {
    return 'account_id may only contain letters, digits, and . _ @ -';
  }
  if (isReservedAccountId(accountId)) {
    return 'account_id is reserved';
  }
  return null;
}
