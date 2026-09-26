/// Response header the auth middleware sets on every response to a suspended
/// account, so the client can show the suspension notice from its very first
/// request after launch rather than only after attempting a blocked action.
/// Absent for an account in good standing, which is how a client notices an
/// admin lifting the suspension.
const kAccountStatusHeader = 'X-Helix-Account-Status';

/// Whether a suspended account is refused this request.
///
/// Suspension limits what an account can *do* to other people - send, edit or
/// react to messages, start conversations, send or accept contact requests,
/// place or answer calls, act in groups, upload attachments, change its
/// profile. Everything else still works: reading and receiving, refreshing
/// the session, managing its own devices and push token, declining calls and
/// requests, blocking and reporting, exporting or deleting its own data. That
/// is a deny-list on purpose: an allow-list would silently break message
/// delivery the first time a new passive route was added.
///
/// [path] is the request path relative to the server root, as the auth
/// middleware sees it (`api/v1/messages/send`).
bool isSuspendedActivity(String method, String path) {
  if (method == 'GET' || method == 'HEAD' || method == 'OPTIONS') return false;
  final route = path.startsWith('/') ? path.substring(1) : path;
  const prefix = 'api/v1/';
  if (!route.startsWith(prefix)) return false;
  final p = route.substring(prefix.length);

  const exact = {
    'messages/send',
    'messages/edit',
    'messages/delete',
    'messages/reactions',
    'messages/typing',
    'messages/conversations/create',
    'contacts/requests',
    'contacts/requests/accept',
    'contacts/add',
    'accounts/profile',
    'calls/signal',
    'attachments/upload',
    'attachments/register-reference',
  };
  if (exact.contains(p)) return true;

  // Answering a call is activity; declining, cancelling or expiring one is not.
  if (p.startsWith('calls/pending/') && p.endsWith('/accept')) return true;
  if (p.startsWith('attachments/upload/')) return true;
  // Every group and group-call action except leaving a group.
  if (p.startsWith('groups/') && p != 'groups/leave') return true;
  if (p == 'group-calls' || p.startsWith('group-calls/')) return true;
  return false;
}
