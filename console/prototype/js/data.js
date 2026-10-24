/*
  Sample data for the Helix Admin prototype. Fixed to one morning (22 Oct
  2026, ~11:42) so every screen tells the same story. Shapes follow the admin
  API the console already consumes: accounts, reports, audit, invites, logs,
  configuration and readiness.
*/
const DATA = (() => {
  const server = {
    name: 'Helix Global',
    address: 'https://helix.agiletechbd.com',
    nodeId: 'node_bd_01',
    version: '2.4.1',
    registration: 'phone',
    latencyMs: 42,
    signedInUntil: '2026-10-22 19:38',
  };

  // GET /v1/ops/metrics. Every count is this node's lifetime and starts again
  // at a restart - which is why nothing here is a trend or a time series.
  const metrics = {
    requests: 1248902,
    serverErrors: 5004,
    clientErrors: 22480,
    websocketsOpen: 312,
    websocketConnections: 41,
    mailboxBacklog: 47,
    deadJobs: 2,
    crashReports: 12,
    jobsFinished: { ok: 12455, retry: 23, dead: 2 },
    serverErrorShare: 0.004,
    startedAt: '2026-10-22 04:12',
    database: true,
  };

  const health = {
    database: true,
    storage: true,
  };

  const integrations = {
    push: { configured: true, provider: 'fcm' },
    sms: { configured: true, provider: 'bulksmsbd' },
    turn: { configured: true, count: 4 },
  };

  const accounts = [
    {
      id: 'acc_7N2K9Q', helixName: 'tanvir', displayName: 'Tanvir Ahmed',
      phone: '+8801712345678', last4: '5678', status: 'active',
      activeDevices: 2, openReports: 1, createdAt: '2025-03-12', lastSeenOn: '2026-10-22', color: 2,
    },
    {
      id: 'acc_3M8Q1D', helixName: 'quickcash', displayName: 'QuickCash Promo',
      phone: '+8801555011002', last4: '1002', status: 'suspended',
      activeDevices: 1, openReports: 1, createdAt: '2026-09-02', lastSeenOn: '2026-10-20', color: 3,
    },
    {
      id: 'acc_5R7T2B', helixName: 'rafiul.h', displayName: 'Rafiul H.',
      phone: '+8801933776655', last4: '6655', status: 'active',
      activeDevices: 2, openReports: 1, createdAt: '2026-07-03', lastSeenOn: '2026-10-22', color: 5,
    },
    {
      id: 'acc_1F9A4R', helixName: 'nilu', displayName: 'Nilufar Yasmin',
      phone: '+8801811902233', last4: '2233', status: 'active',
      activeDevices: 1, openReports: 0, createdAt: '2025-01-08', lastSeenOn: '2026-10-22', color: 1,
    },
    {
      id: 'acc_6C2D8S', helixName: 'rakib', displayName: 'Rakib Hasan',
      phone: '+8801677400812', last4: '0812', status: 'active',
      activeDevices: 3, openReports: 0, createdAt: '2024-11-19', lastSeenOn: '2026-10-22', color: 4,
    },
    {
      id: 'acc_8P3V5K', helixName: 'sabrina', displayName: 'Sabrina Chowdhury',
      phone: '+8801522661188', last4: '1188', status: 'active',
      activeDevices: 1, openReports: 0, createdAt: '2026-02-27', lastSeenOn: '2026-10-22', color: 0,
    },
    {
      id: 'acc_9W4L6E', helixName: 'shopdeal', displayName: 'ShopDeal BD',
      phone: '+8801644220099', last4: '0099', status: 'active',
      activeDevices: 2, openReports: 0, createdAt: '2026-05-05', lastSeenOn: '2026-10-21', color: 6,
    },
    {
      id: 'acc_4K8N2M', helixName: 'imran.k', displayName: null,
      phone: '+8801700334455', last4: '4455', status: 'active',
      activeDevices: 0, openReports: 0, createdAt: '2024-04-14', lastSeenOn: null, color: 7,
    },
  ];

  const devices = {
    acc_7N2K9Q: [
      { id: 'dev_9K2E', name: 'Pixel 8', platform: 'android', active: true, lastSeenOn: '2026-10-22', revokedAt: null },
      { id: 'dev_4J1C', name: 'Windows PC', platform: 'windows', active: true, lastSeenOn: '2026-10-20', revokedAt: null },
    ],
    acc_3M8Q1D: [
      { id: 'dev_2A7F', name: 'Redmi Note 13', platform: 'android', active: true, lastSeenOn: '2026-10-20', revokedAt: null },
      { id: 'dev_8D4H', name: 'Galaxy A14', platform: 'android', active: false, lastSeenOn: '2026-10-11', revokedAt: '2026-10-20' },
    ],
    acc_5R7T2B: [
      { id: 'dev_7C3A', name: 'Galaxy S24', platform: 'android', active: true, lastSeenOn: '2026-10-22', revokedAt: null },
      { id: 'dev_2B9F', name: 'MacBook Air', platform: 'macos', active: true, lastSeenOn: '2026-10-16', revokedAt: null },
    ],
    acc_1F9A4R: [
      { id: 'dev_6Q1P', name: 'iPhone 14', platform: 'ios', active: true, lastSeenOn: '2026-10-22', revokedAt: null },
    ],
    acc_6C2D8S: [
      { id: 'dev_5M8R', name: 'Pixel 9', platform: 'android', active: true, lastSeenOn: '2026-10-22', revokedAt: null },
      { id: 'dev_3T7W', name: 'Dell XPS', platform: 'windows', active: true, lastSeenOn: '2026-10-21', revokedAt: null },
      { id: 'dev_9B2N', name: 'helix-cli', platform: 'cli', active: true, lastSeenOn: '2026-10-19', revokedAt: null },
    ],
    acc_8P3V5K: [
      { id: 'dev_4V6X', name: 'Windows PC', platform: 'windows', active: true, lastSeenOn: '2026-10-22', revokedAt: null },
    ],
    acc_9W4L6E: [
      { id: 'dev_1K5L', name: 'Vivo V30', platform: 'android', active: true, lastSeenOn: '2026-10-21', revokedAt: null },
      { id: 'dev_7P3E', name: 'Windows PC', platform: 'windows', active: true, lastSeenOn: '2026-10-20', revokedAt: null },
    ],
    acc_4K8N2M: [],
  };

  const accountDetails = {
    acc_7N2K9Q: { hasPassword: true, openReports: 1 },
    acc_3M8Q1D: { hasPassword: true, openReports: 1 },
    acc_5R7T2B: { hasPassword: true, openReports: 1 },
    acc_1F9A4R: { hasPassword: true, openReports: 0 },
    acc_6C2D8S: { hasPassword: true, openReports: 0 },
    acc_8P3V5K: { hasPassword: false, openReports: 0 },
    acc_9W4L6E: { hasPassword: true, openReports: 0 },
    acc_4K8N2M: { hasPassword: true, openReports: 0 },
  };

  const reports = [
    {
      id: 'rep_1042', category: 'abuse', status: 'open',
      subject: 'acc_7N2K9Q', reporter: 'acc_8P3V5K',
      createdAt: '2026-10-22 11:24',
      note: 'Kept messaging me after I asked them to stop. Fourteen messages in a row last night, and three more this morning.',
    },
    {
      id: 'rep_1041', category: 'spam', status: 'open',
      subject: 'acc_3M8Q1D', reporter: 'acc_6C2D8S',
      createdAt: '2026-10-22 09:38',
      note: 'Four messages in an hour, all with a loan link. I never gave them my number.',
    },
    {
      id: 'rep_1040', category: 'impersonation', status: 'open',
      subject: 'acc_5R7T2B', reporter: 'acc_1F9A4R',
      createdAt: '2026-10-22 06:47',
      note: 'The photo and name copy a public figure, and they are asking my relatives for money.',
    },
    {
      id: 'rep_1039', category: 'spam', status: 'resolved',
      subject: 'acc_9W4L6E', reporter: 'acc_6C2D8S',
      createdAt: '2026-10-21 16:12',
      note: 'They sent the same discount code to several people I know.',
    },
    {
      id: 'rep_1038', category: 'other', status: 'dismissed',
      subject: 'acc_1F9A4R', reporter: 'acc_8P3V5K',
      createdAt: '2026-10-21 12:30',
      note: 'A disagreement between two people who know each other.',
    },
  ];

  const audit = [
    { id: 'aud_24391', action: 'admin.sign_in', at: '2026-10-22 11:38', target: null, details: { method: 'password' } },
    { id: 'aud_24390', action: 'report.resolve', at: '2026-10-22 11:02', target: 'rep_1039', details: { status: 'resolved' } },
    { id: 'aud_24389', action: 'account.suspend', at: '2026-10-22 10:58', target: 'acc_3M8Q1D', details: { reason: 'Spam reports' } },
    { id: 'aud_24388', action: 'device.revoke', at: '2026-10-22 10:47', target: 'dev_8D4H', details: { account: 'acc_3M8Q1D' } },
    { id: 'aud_24387', action: 'invite.create', at: '2026-10-22 09:15', target: 'inv_7F2KQP9D', details: { issuer: 'admin' } },
    { id: 'aud_24386', action: 'account.recovery_code', at: '2026-10-21 22:40', target: 'acc_1F9A4R', details: { expires: '2026-10-23 22:40' } },
    { id: 'aud_24385', action: 'report.dismiss', at: '2026-10-21 17:03', target: 'rep_1038', details: { status: 'dismissed' } },
    { id: 'aud_24384', action: 'config.update', at: '2026-10-20 14:08', target: 'server_name', details: { from: 'Helix BD', to: 'Helix Global' } },
    { id: 'aud_24383', action: 'feature_flag.update', at: '2026-10-20 09:30', target: 'group_calls', details: { enabled: 'false' } },
    { id: 'aud_24382', action: 'backup.complete', at: '2026-10-20 04:12', target: 'backup_01J9', details: { size: '1.9 GB' } },
    { id: 'aud_24381', action: 'admin.password_change', at: '2026-10-19 18:21', target: null, details: { sessions_ended: '2' } },
    { id: 'aud_24380', action: 'account.suspend', at: '2026-10-19 11:04', target: 'acc_9W4L6E', details: { reason: 'Bulk messaging' } },
    { id: 'aud_24379', action: 'account.resume', at: '2026-10-19 10:20', target: 'acc_9W4L6E', details: {} },
    { id: 'aud_24378', action: 'invite.cancel', at: '2026-10-18 16:45', target: 'inv_6B1N8TRE', details: {} },
    { id: 'aud_24377', action: 'admin.sign_in', at: '2026-10-18 08:02', target: null, details: { method: 'password' } },
  ];

  const invites = [
    { id: 'inv_7F2KQP9D', status: 'open', issuer: 'admin', createdAt: '2026-10-18 09:12', expiresAt: '2026-10-25 09:12', redeemedBy: null },
    { id: 'inv_3M8Q1DPA', status: 'open', issuer: 'admin', createdAt: '2026-10-21 10:05', expiresAt: '2026-10-24 10:05', redeemedBy: null },
    { id: 'inv_9Q4M2XKD', status: 'used', issuer: 'admin', createdAt: '2026-10-12 14:20', expiresAt: '2026-10-19 14:20', redeemedBy: 'acc_8P3V5K' },
    { id: 'inv_6B1N8TRE', status: 'cancelled', issuer: 'admin', createdAt: '2026-10-20 08:10', expiresAt: '2026-10-28 08:10', redeemedBy: null },
    { id: 'inv_2V7C5LMA', status: 'expired', issuer: 'self', createdAt: '2026-09-25 16:00', expiresAt: '2026-10-02 16:00', redeemedBy: null },
  ];

  const flags = {
    crash_reporting_upload: true,
    minimal_analytics: true,
    group_calls: false,
  };

  const config = {
    serverName: 'Helix Global',
    address: 'https://helix.agiletechbd.com',
    nodeId: 'node_bd_01',
    version: '2.4.1',
    registration: 'phone',
    maxAttachment: '50 MB',
    signedInUntil: '2026-10-22 19:38',
    federation: false,
    federationDomain: null,
    maintenance: false,
    appLock: false,
  };

  // Newest last, as the server returns them; the console shows newest first
  // on screen while following the tail.
  const logs = [
    { at: '11:41:02.332', level: 'debug', event: 'outbox.job', msg: 'job drained queue=push count=14 took=38ms' },
    { at: '11:41:08.610', level: 'info', event: 'calls.turn', msg: 'allocation created relay=turn-bd-2 proto=udp ttl=600' },
    { at: '11:41:12.027', level: 'info', event: 'messaging.group', msg: 'sender key distributed group=g_71V2 members=9 epoch=14' },
    { at: '11:41:18.902', level: 'warn', event: 'storage.disk', msg: 'disk usage 8.5% free=73.2GB threshold=85%' },
    { at: '11:41:21.553', level: 'info', event: 'identity.session', msg: 'session revoked dev_77c2 by=owner' },
    { at: '11:41:26.208', level: 'info', event: 'audit.write', msg: 'entry appended actor=admin action=report.resolve target=rep_1039' },
    { at: '11:41:29.414', level: 'error', event: 'media.thumbnail', msg: 'thumbnail failed key=4d/19/4d19c2e8 reason=decode timeout retry=1' },
    { at: '11:41:33.771', level: 'debug', event: 'federation.peer', msg: 'peer heartbeat node=helix-eu-1 rtt=62ms' },
    { at: '11:41:38.050', level: 'info', event: 'realtime.ws', msg: 'socket opened dev_91ab ip=37.111.22.8' },
    { at: '11:41:41.663', level: 'info', event: 'keys.prekeys', msg: 'prekey bundle served acct=acc_6C2D8S devices=3' },
    { at: '11:41:44.118', level: 'info', event: 'messaging.send', msg: 'message delivered chat=c_2aQ7 recipient=dev_41cc bytes=214' },
    { at: '11:41:47.309', level: 'warn', event: 'postgres.pool', msg: 'pool waited 120ms waiting=3 total=12/100' },
    { at: '11:41:51.872', level: 'info', event: 'media.object', msg: 'object stored bucket=media key=8c/2f/8c2f91a0 size=1.2MB' },
    { at: '11:41:55.441', level: 'info', event: 'identity.session', msg: 'session issued acct=acc_7N2K9Q dev=dev_9K2E ttl=30d' },
    { at: '11:41:58.020', level: 'debug', event: 'outbox.job', msg: 'job drained queue=push count=14 took=38ms' },
    { at: '11:42:03.557', level: 'error', event: 'push.fcm', msg: 'push rejected device=dev_77c2 reason=UNREGISTERED retry=0' },
    { at: '11:42:05.101', level: 'info', event: 'messaging.send', msg: 'message delivered chat=c_8fJ2 recipient=dev_91ab bytes=486' },
    { at: '11:42:06.902', level: 'warn', event: 'rate.limit', msg: 'throttled login attempts ip=103.108.44.21 bucket=auth retry=30s' },
    { at: '11:42:07.214', level: 'info', event: 'realtime.ws', msg: 'socket closed dev_2f91 code=1000 reason=client left' },
  ];

  return {
    server, metrics, health, integrations, accounts, devices, accountDetails,
    reports, audit, invites, flags, config, logs,
  };
})();
