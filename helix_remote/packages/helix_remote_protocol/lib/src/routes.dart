/// The v2 REST route catalog: the single source of truth for every endpoint
/// (REST_V2.md documents each one). The server registers exactly these
/// routes (a parity test enforces it) and clients build URLs from them, so a
/// path can never drift between the two.
library;

enum HttpMethod { get, post, put, patch, delete, head }

/// Who may call a route.
enum RouteAccess {
  /// No session. The server must give every public route a rate limit.
  public,

  /// A device access token.
  device,

  /// An admin token (operator console).
  admin,

  /// A signed server-to-server request (federation).
  s2s,
}

final class ApiRoute {
  const ApiRoute(
    this.method,
    this.path, {
    required this.module,
    required this.access,
  });

  final HttpMethod method;

  /// Path template, e.g. `/v1/groups/{group_id}/members/{account}`.
  final String path;

  /// The server module that owns the route (ADR-026).
  final String module;
  final RouteAccess access;

  static final RegExp _param = RegExp(r'\{([a-z_]+)\}');

  /// Names of the path parameters, in order.
  List<String> get parameters => [
    for (final match in _param.allMatches(path)) match.group(1)!,
  ];

  /// Fills the path parameters. Values are percent-encoded.
  String expand([Map<String, String> values = const {}]) {
    final missing = parameters.where((p) => !values.containsKey(p)).toList();
    if (missing.isNotEmpty) {
      throw ArgumentError('missing path parameters $missing for $path');
    }
    return path.replaceAllMapped(
      _param,
      (m) => Uri.encodeComponent(values[m.group(1)!]!),
    );
  }

  @override
  String toString() => '${method.name.toUpperCase()} $path';
}

const _pub = RouteAccess.public;
const _dev = RouteAccess.device;
const _adm = RouteAccess.admin;
const _s2s = RouteAccess.s2s;
const _get = HttpMethod.get;
const _post = HttpMethod.post;
const _put = HttpMethod.put;
const _patch = HttpMethod.patch;
const _delete = HttpMethod.delete;
const _head = HttpMethod.head;

/// Every v2 route, grouped by module.
abstract final class Routes {
  // ---------------------------------------------------------------- identity
  static const phoneChallenge = ApiRoute(
    _post,
    '/v1/auth/phone/challenges',
    module: 'identity',
    access: _pub,
  );
  static const phoneVerify = ApiRoute(
    _post,
    '/v1/auth/phone/verify',
    module: 'identity',
    access: _pub,
  );
  static const inviteLookup = ApiRoute(
    _post,
    '/v1/auth/invites/lookup',
    module: 'identity',
    access: _pub,
  );
  static const inviteSelfIssue = ApiRoute(
    _post,
    '/v1/auth/invites/self-issue',
    module: 'identity',
    access: _pub,
  );
  static const register = ApiRoute(
    _post,
    '/v1/auth/register',
    module: 'identity',
    access: _pub,
  );
  static const passwordParams = ApiRoute(
    _post,
    '/v1/auth/password/params',
    module: 'identity',
    access: _pub,
  );
  static const passwordSignIn = ApiRoute(
    _post,
    '/v1/auth/password/sign-in',
    module: 'identity',
    access: _pub,
  );
  static const linkCreate = ApiRoute(
    _post,
    '/v1/auth/links',
    module: 'identity',
    access: _pub,
  );
  static const linkPoll = ApiRoute(
    _get,
    '/v1/auth/links/{link_id}',
    module: 'identity',
    access: _pub,
  );
  static const addDevice = ApiRoute(
    _post,
    '/v1/auth/devices',
    module: 'identity',
    access: _pub,
  );
  static const deviceChallenge = ApiRoute(
    _post,
    '/v1/auth/challenges',
    module: 'identity',
    access: _pub,
  );
  static const deviceSignIn = ApiRoute(
    _post,
    '/v1/auth/sessions',
    module: 'identity',
    access: _pub,
  );
  static const refreshSession = ApiRoute(
    _post,
    '/v1/auth/sessions/refresh',
    module: 'identity',
    access: _pub,
  );
  static const recoveryLookup = ApiRoute(
    _post,
    '/v1/auth/recovery/lookup',
    module: 'identity',
    access: _pub,
  );
  static const recoveryRedeem = ApiRoute(
    _post,
    '/v1/auth/recovery/redeem',
    module: 'identity',
    access: _pub,
  );
  static const signOut = ApiRoute(
    _delete,
    '/v1/auth/sessions/current',
    module: 'identity',
    access: _dev,
  );
  static const account = ApiRoute(
    _get,
    '/v1/account',
    module: 'identity',
    access: _dev,
  );
  static const setPassword = ApiRoute(
    _put,
    '/v1/account/password',
    module: 'identity',
    access: _dev,
  );
  static const setHelixName = ApiRoute(
    _put,
    '/v1/account/helix-name',
    module: 'identity',
    access: _dev,
  );
  static const clearHelixName = ApiRoute(
    _delete,
    '/v1/account/helix-name',
    module: 'identity',
    access: _dev,
  );
  static const securityEvents = ApiRoute(
    _get,
    '/v1/account/security-events',
    module: 'identity',
    access: _dev,
  );
  static const devices = ApiRoute(
    _get,
    '/v1/devices',
    module: 'identity',
    access: _dev,
  );
  static const renameDevice = ApiRoute(
    _patch,
    '/v1/devices/{device_id}',
    module: 'identity',
    access: _dev,
  );
  static const revokeDevice = ApiRoute(
    _delete,
    '/v1/devices/{device_id}',
    module: 'identity',
    access: _dev,
  );
  static const revokeOtherDevices = ApiRoute(
    _post,
    '/v1/devices/revoke-others',
    module: 'identity',
    access: _dev,
  );
  static const approveLink = ApiRoute(
    _post,
    '/v1/devices/links/{link_id}/approve',
    module: 'identity',
    access: _dev,
  );
  static const setPushToken = ApiRoute(
    _put,
    '/v1/devices/self/push-token',
    module: 'identity',
    access: _dev,
  );
  static const clearPushToken = ApiRoute(
    _delete,
    '/v1/devices/self/push-token',
    module: 'identity',
    access: _dev,
  );

  // -------------------------------------------------------------------- keys
  static const setSignedPrekey = ApiRoute(
    _put,
    '/v1/keys/signed-prekey',
    module: 'keys',
    access: _dev,
  );
  static const addOneTimePrekeys = ApiRoute(
    _post,
    '/v1/keys/one-time-prekeys',
    module: 'keys',
    access: _dev,
  );
  static const keyStatus = ApiRoute(
    _get,
    '/v1/keys/status',
    module: 'keys',
    access: _dev,
  );
  static const accountKeys = ApiRoute(
    _get,
    '/v1/keys/{account}',
    module: 'keys',
    access: _dev,
  );

  // --------------------------------------------------------------- messaging
  static const sendMessage = ApiRoute(
    _post,
    '/v1/messages',
    module: 'messaging',
    access: _dev,
  );
  static const mailbox = ApiRoute(
    _get,
    '/v1/mailbox',
    module: 'messaging',
    access: _dev,
  );
  static const ackMailbox = ApiRoute(
    _post,
    '/v1/mailbox/ack',
    module: 'messaging',
    access: _dev,
  );

  // ---------------------------------------------------------------- realtime
  static const websocket = ApiRoute(
    _get,
    '/v1/ws',
    module: 'realtime',
    access: _dev,
  );

  // ------------------------------------------------------------------ people
  static const discoverySalt = ApiRoute(
    _get,
    '/v1/people/discovery-salt',
    module: 'people',
    access: _dev,
  );
  static const discover = ApiRoute(
    _post,
    '/v1/people/discover',
    module: 'people',
    access: _dev,
  );
  static const findByName = ApiRoute(
    _get,
    '/v1/people/by-name/{name}',
    module: 'people',
    access: _dev,
  );
  static const profile = ApiRoute(
    _get,
    '/v1/people/{account}/profile',
    module: 'people',
    access: _dev,
  );
  static const presence = ApiRoute(
    _get,
    '/v1/people/{account}/presence',
    module: 'people',
    access: _dev,
  );
  static const setOwnProfile = ApiRoute(
    _put,
    '/v1/profile',
    module: 'people',
    access: _dev,
  );
  static const blocks = ApiRoute(
    _get,
    '/v1/people/blocks',
    module: 'people',
    access: _dev,
  );
  static const block = ApiRoute(
    _put,
    '/v1/people/blocks/{account}',
    module: 'people',
    access: _dev,
  );
  static const unblock = ApiRoute(
    _delete,
    '/v1/people/blocks/{account}',
    module: 'people',
    access: _dev,
  );
  static const privacy = ApiRoute(
    _get,
    '/v1/people/privacy',
    module: 'people',
    access: _dev,
  );
  static const setPrivacy = ApiRoute(
    _put,
    '/v1/people/privacy',
    module: 'people',
    access: _dev,
  );
  static const setContacts = ApiRoute(
    _put,
    '/v1/people/contacts',
    module: 'people',
    access: _dev,
  );
  static const report = ApiRoute(
    _post,
    '/v1/people/reports',
    module: 'people',
    access: _dev,
  );

  // ------------------------------------------------------------------ groups
  static const createGroup = ApiRoute(
    _post,
    '/v1/groups',
    module: 'groups',
    access: _dev,
  );
  static const myGroups = ApiRoute(
    _get,
    '/v1/groups',
    module: 'groups',
    access: _dev,
  );
  static const group = ApiRoute(
    _get,
    '/v1/groups/{group_id}',
    module: 'groups',
    access: _dev,
  );
  static const deleteGroup = ApiRoute(
    _delete,
    '/v1/groups/{group_id}',
    module: 'groups',
    access: _dev,
  );
  static const setGroupState = ApiRoute(
    _put,
    '/v1/groups/{group_id}/state',
    module: 'groups',
    access: _dev,
  );
  static const setGroupSettings = ApiRoute(
    _put,
    '/v1/groups/{group_id}/settings',
    module: 'groups',
    access: _dev,
  );
  static const addGroupMembers = ApiRoute(
    _post,
    '/v1/groups/{group_id}/members',
    module: 'groups',
    access: _dev,
  );
  static const removeGroupMember = ApiRoute(
    _delete,
    '/v1/groups/{group_id}/members/{account}',
    module: 'groups',
    access: _dev,
  );
  static const setGroupRole = ApiRoute(
    _put,
    '/v1/groups/{group_id}/members/{account}/role',
    module: 'groups',
    access: _dev,
  );
  static const banFromGroup = ApiRoute(
    _put,
    '/v1/groups/{group_id}/bans/{account}',
    module: 'groups',
    access: _dev,
  );
  static const unbanFromGroup = ApiRoute(
    _delete,
    '/v1/groups/{group_id}/bans/{account}',
    module: 'groups',
    access: _dev,
  );
  static const createInviteLink = ApiRoute(
    _post,
    '/v1/groups/{group_id}/invite-links',
    module: 'groups',
    access: _dev,
  );
  static const revokeInviteLink = ApiRoute(
    _delete,
    '/v1/groups/{group_id}/invite-links/{link_id}',
    module: 'groups',
    access: _dev,
  );
  static const previewInviteLink = ApiRoute(
    _post,
    '/v1/groups/invite-links/preview',
    module: 'groups',
    access: _dev,
  );
  static const joinGroup = ApiRoute(
    _post,
    '/v1/groups/join',
    module: 'groups',
    access: _dev,
  );
  static const joinRequests = ApiRoute(
    _get,
    '/v1/groups/{group_id}/join-requests',
    module: 'groups',
    access: _dev,
  );
  static const resolveJoinRequest = ApiRoute(
    _post,
    '/v1/groups/{group_id}/join-requests/{request_id}',
    module: 'groups',
    access: _dev,
  );
  static const sendGroupMessage = ApiRoute(
    _post,
    '/v1/groups/{group_id}/messages',
    module: 'groups',
    access: _dev,
  );

  // ------------------------------------------------------------------- calls
  static const turnCredentials = ApiRoute(
    _get,
    '/v1/calls/turn',
    module: 'calls',
    access: _dev,
  );
  static const sendCallSignal = ApiRoute(
    _post,
    '/v1/calls/{call_id}/signals',
    module: 'calls',
    access: _dev,
  );
  static const setCallState = ApiRoute(
    _put,
    '/v1/calls/{call_id}/state',
    module: 'calls',
    access: _dev,
  );
  static const pendingCalls = ApiRoute(
    _get,
    '/v1/calls/pending',
    module: 'calls',
    access: _dev,
  );
  static const callMetrics = ApiRoute(
    _post,
    '/v1/calls/metrics',
    module: 'calls',
    access: _dev,
  );

  // ------------------------------------------------------------------- media
  static const createUpload = ApiRoute(
    _post,
    '/v1/media',
    module: 'media',
    access: _dev,
  );
  static const uploadContent = ApiRoute(
    _put,
    '/v1/media/{media_id}/content',
    module: 'media',
    access: _dev,
  );
  static const uploadStatus = ApiRoute(
    _head,
    '/v1/media/{media_id}/content',
    module: 'media',
    access: _dev,
  );
  static const downloadContent = ApiRoute(
    _get,
    '/v1/media/{media_id}/content',
    module: 'media',
    access: _dev,
  );
  static const deleteMedia = ApiRoute(
    _delete,
    '/v1/media/{media_id}',
    module: 'media',
    access: _dev,
  );

  // ------------------------------------------------------------------ backup
  static const putHistoryBackup = ApiRoute(
    _put,
    '/v1/backups/history',
    module: 'backup',
    access: _dev,
  );
  static const getHistoryBackup = ApiRoute(
    _get,
    '/v1/backups/history',
    module: 'backup',
    access: _dev,
  );
  static const deleteHistoryBackup = ApiRoute(
    _delete,
    '/v1/backups/history',
    module: 'backup',
    access: _dev,
  );
  static const putFullBackup = ApiRoute(
    _put,
    '/v1/backups/full',
    module: 'backup',
    access: _dev,
  );
  static const getFullBackup = ApiRoute(
    _get,
    '/v1/backups/full',
    module: 'backup',
    access: _dev,
  );
  static const deleteFullBackup = ApiRoute(
    _delete,
    '/v1/backups/full',
    module: 'backup',
    access: _dev,
  );

  // --------------------------------------------------------------------- ops
  static const live = ApiRoute(
    _get,
    '/v1/health/live',
    module: 'ops',
    access: _pub,
  );
  static const ready = ApiRoute(
    _get,
    '/v1/health/ready',
    module: 'ops',
    access: _pub,
  );
  static const serverInfo = ApiRoute(
    _get,
    '/v1/server',
    module: 'ops',
    access: _pub,
  );
  static const legal = ApiRoute(
    _get,
    '/v1/server/legal',
    module: 'ops',
    access: _pub,
  );
  static const crashReport = ApiRoute(
    _post,
    '/v1/telemetry/crash',
    module: 'ops',
    access: _dev,
  );
  static const metrics = ApiRoute(
    _get,
    '/v1/ops/metrics',
    module: 'ops',
    access: _adm,
  );

  // -------------------------------------------------------------- compliance
  static const exportData = ApiRoute(
    _get,
    '/v1/account/export',
    module: 'compliance',
    access: _dev,
  );
  static const deleteAccount = ApiRoute(
    _delete,
    '/v1/account',
    module: 'compliance',
    access: _dev,
  );

  // -------------------------------------------------------------- federation
  static const serverIdentity = ApiRoute(
    _get,
    '/.well-known/helix-server',
    module: 'federation',
    access: _pub,
  );
  static const s2sMessages = ApiRoute(
    _post,
    '/v1/s2s/messages',
    module: 'federation',
    access: _s2s,
  );
  static const s2sKeys = ApiRoute(
    _get,
    '/v1/s2s/keys/{account}',
    module: 'federation',
    access: _s2s,
  );
  static const s2sGroupMessages = ApiRoute(
    _post,
    '/v1/s2s/groups/{group_id}/messages',
    module: 'federation',
    access: _s2s,
  );
  static const s2sGroup = ApiRoute(
    _get,
    '/v1/s2s/groups/{group_id}',
    module: 'federation',
    access: _s2s,
  );
  static const s2sGroupActions = ApiRoute(
    _post,
    '/v1/s2s/groups/{group_id}/actions',
    module: 'federation',
    access: _s2s,
  );
  static const s2sGroupSync = ApiRoute(
    _post,
    '/v1/s2s/groups/{group_id}/sync',
    module: 'federation',
    access: _s2s,
  );
  static const s2sCallSignals = ApiRoute(
    _post,
    '/v1/s2s/calls/{call_id}/signals',
    module: 'federation',
    access: _s2s,
  );

  // ------------------------------------------------------------- app links
  static const assetLinks = ApiRoute(
    _get,
    '/.well-known/assetlinks.json',
    module: 'ops',
    access: _pub,
  );
  static const openLink = ApiRoute(_get, '/open', module: 'ops', access: _pub);

  // ------------------------------------------------------------------- admin
  static const adminSetupStatus = ApiRoute(
    _get,
    '/v1/admin/setup',
    module: 'admin',
    access: _pub,
  );
  static const adminSetup = ApiRoute(
    _post,
    '/v1/admin/setup',
    module: 'admin',
    access: _pub,
  );
  static const adminSignIn = ApiRoute(
    _post,
    '/v1/admin/sessions',
    module: 'admin',
    access: _pub,
  );
  static const adminPassword = ApiRoute(
    _put,
    '/v1/admin/password',
    module: 'admin',
    access: _adm,
  );
  static const adminAccounts = ApiRoute(
    _get,
    '/v1/admin/accounts',
    module: 'admin',
    access: _adm,
  );
  static const adminAccount = ApiRoute(
    _get,
    '/v1/admin/accounts/{account}',
    module: 'admin',
    access: _adm,
  );
  static const adminSuspend = ApiRoute(
    _put,
    '/v1/admin/accounts/{account}/suspension',
    module: 'admin',
    access: _adm,
  );
  static const adminUnsuspend = ApiRoute(
    _delete,
    '/v1/admin/accounts/{account}/suspension',
    module: 'admin',
    access: _adm,
  );
  static const adminBan = ApiRoute(
    _post,
    '/v1/admin/accounts/{account}/ban',
    module: 'admin',
    access: _adm,
  );
  static const adminDeleteAccount = ApiRoute(
    _delete,
    '/v1/admin/accounts/{account}',
    module: 'admin',
    access: _adm,
  );
  static const adminRevokeDevice = ApiRoute(
    _delete,
    '/v1/admin/accounts/{account}/devices/{device_id}',
    module: 'admin',
    access: _adm,
  );
  static const adminRecoveryCode = ApiRoute(
    _post,
    '/v1/admin/accounts/{account}/recovery-codes',
    module: 'admin',
    access: _adm,
  );
  static const adminInvites = ApiRoute(
    _get,
    '/v1/admin/invites',
    module: 'admin',
    access: _adm,
  );
  static const adminCreateInvite = ApiRoute(
    _post,
    '/v1/admin/invites',
    module: 'admin',
    access: _adm,
  );
  static const adminCancelInvite = ApiRoute(
    _delete,
    '/v1/admin/invites/{invite_id}',
    module: 'admin',
    access: _adm,
  );
  static const adminReports = ApiRoute(
    _get,
    '/v1/admin/reports',
    module: 'admin',
    access: _adm,
  );
  static const adminResolveReport = ApiRoute(
    _put,
    '/v1/admin/reports/{report_id}',
    module: 'admin',
    access: _adm,
  );
  static const adminAudit = ApiRoute(
    _get,
    '/v1/admin/audit',
    module: 'admin',
    access: _adm,
  );
  static const adminConfig = ApiRoute(
    _get,
    '/v1/admin/config',
    module: 'admin',
    access: _adm,
  );
  static const adminSetConfig = ApiRoute(
    _patch,
    '/v1/admin/config',
    module: 'admin',
    access: _adm,
  );
  static const adminFeatureFlags = ApiRoute(
    _get,
    '/v1/admin/feature-flags',
    module: 'admin',
    access: _adm,
  );
  static const adminSetFeatureFlag = ApiRoute(
    _put,
    '/v1/admin/feature-flags/{name}',
    module: 'admin',
    access: _adm,
  );
  static const adminLogs = ApiRoute(
    _get,
    '/v1/admin/logs',
    module: 'admin',
    access: _adm,
  );
  static const adminLogStream = ApiRoute(
    _get,
    '/v1/admin/logs/stream',
    module: 'admin',
    access: _adm,
  );
  static const adminPurge = ApiRoute(
    _post,
    '/v1/admin/purge',
    module: 'admin',
    access: _adm,
  );

  /// Every route above. Order is documentation order.
  static const List<ApiRoute> all = [
    phoneChallenge, phoneVerify, inviteLookup, inviteSelfIssue, register, //
    passwordParams, passwordSignIn, linkCreate, linkPoll, addDevice,
    deviceChallenge, deviceSignIn, refreshSession, recoveryLookup,
    recoveryRedeem, signOut, account, setPassword, setHelixName,
    clearHelixName, securityEvents, devices, renameDevice, revokeDevice,
    revokeOtherDevices, approveLink, setPushToken, clearPushToken,
    setSignedPrekey, addOneTimePrekeys, keyStatus, accountKeys, //
    sendMessage, mailbox, ackMailbox, websocket, //
    discoverySalt, discover, findByName, profile, presence, setOwnProfile,
    blocks, block, unblock, privacy, setPrivacy, setContacts, report, //
    createGroup, myGroups, group, deleteGroup, setGroupState,
    setGroupSettings, addGroupMembers, removeGroupMember, setGroupRole,
    banFromGroup, unbanFromGroup, createInviteLink, revokeInviteLink,
    previewInviteLink, joinGroup, joinRequests, resolveJoinRequest,
    sendGroupMessage, //
    turnCredentials, sendCallSignal, setCallState, pendingCalls,
    callMetrics, //
    createUpload, uploadContent, uploadStatus, downloadContent, deleteMedia,
    putHistoryBackup, getHistoryBackup, deleteHistoryBackup, putFullBackup,
    getFullBackup, deleteFullBackup, //
    live, ready, serverInfo, legal, crashReport, metrics, assetLinks,
    openLink, //
    exportData, deleteAccount, //
    serverIdentity, s2sMessages, s2sKeys, s2sGroupMessages, s2sGroup,
    s2sGroupActions, s2sGroupSync, s2sCallSignals, //
    adminSetupStatus, adminSetup, adminSignIn, adminPassword, adminAccounts,
    adminAccount, adminSuspend, adminUnsuspend, adminBan, adminDeleteAccount,
    adminRevokeDevice, adminRecoveryCode, adminInvites, adminCreateInvite,
    adminCancelInvite, adminReports, adminResolveReport, adminAudit,
    adminConfig, adminSetConfig, adminFeatureFlags, adminSetFeatureFlag,
    adminLogs, adminLogStream, adminPurge,
  ];
}
