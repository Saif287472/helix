import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// Every client route in the catalog is sent by exactly one client method,
/// and S2S routes by none (the client-side counterpart of the server's
/// route registry check).
void main() {
  final clientRoutes = [
    for (final r in Routes.all)
      if (r.access != RouteAccess.s2s) r,
  ];

  final bytes = Uint8List(32);
  final now = DateTime.utc(2026);
  const id = '01890000-0000-7000-8000-000000000000';
  final prekey = SignedPrekey(id: 1, publicKey: bytes, signature: bytes);
  final registration = DeviceRegistration(
    deviceId: id,
    name: 'n',
    platform: DevicePlatform.cli,
    identityKey: bytes,
    signingKey: bytes,
    certificate: DeviceCertificate(createdAt: now, signature: bytes),
    proof: bytes,
  );
  final prekeys = PrekeyUpload(signedPrekey: prekey, oneTimePrekeys: const []);
  final password = PasswordSetup(
    kdf: const KdfParams(),
    salt: bytes,
    authKey: bytes,
    wrappedIdentityKey: WrappedKey(nonce: bytes, ciphertext: bytes),
  );

  /// Calls one client method for each route.
  Map<ApiRoute, FutureOr<void> Function(Clients c)> table() => {
    // identity
    Routes.phoneChallenge: (c) => c.identity.phoneChallenge(
      const PhoneChallengeRequest(
        phoneNumber: '+1',
        purpose: PhonePurpose.register,
      ),
    ),
    Routes.phoneVerify: (c) => c.identity.phoneVerify(
      const PhoneVerifyRequest(challengeId: 'c', code: '1'),
    ),
    Routes.inviteLookup: (c) => c.identity.inviteLookup('code'),
    Routes.inviteSelfIssue: (c) => c.identity.inviteSelfIssue(),
    Routes.register: (c) => c.identity.register(
      RegisterRequest(
        accountId: id,
        identityKey: bytes,
        device: registration,
        prekeys: prekeys,
      ),
    ),
    Routes.passwordParams: (c) => c.identity.passwordParams('+1'),
    Routes.passwordSignIn: (c) => c.identity.passwordSignIn(
      PasswordSignInRequest(phoneNumber: '+1', authKey: bytes),
    ),
    Routes.linkCreate: (c) =>
        c.identity.createLink(LinkCreateRequest(ephemeralKey: bytes)),
    Routes.linkPoll: (c) => c.identity.pollLink(id, pollToken: 'p'),
    Routes.addDevice: (c) => c.identity.addDevice(
      AddDeviceRequest(device: registration, prekeys: prekeys),
    ),
    Routes.deviceChallenge: (c) => c.identity.deviceChallenge(
      const DeviceChallengeRequest(accountId: id, deviceId: id),
    ),
    Routes.deviceSignIn: (c) => c.identity.deviceSignIn(
      DeviceSignInRequest(
        accountId: id,
        deviceId: id,
        challengeId: 'c',
        challenge: bytes,
        signature: bytes,
      ),
    ),
    Routes.refreshSession: (c) => c.identity.refresh('r'),
    Routes.recoveryLookup: (c) => c.identity.recoveryLookup('code'),
    Routes.recoveryRedeem: (c) => c.identity.recoveryRedeem(
      RecoveryRedeemRequest(
        recoveryCode: 'code',
        identityKey: bytes,
        device: registration,
        prekeys: prekeys,
      ),
    ),
    Routes.signOut: (c) => c.identity.signOut(),
    Routes.account: (c) => c.identity.account(),
    Routes.setPassword: (c) =>
        c.identity.setPassword(SetPasswordRequest(password: password)),
    Routes.setHelixName: (c) => c.identity.setHelixName('alice'),
    Routes.clearHelixName: (c) => c.identity.clearHelixName(),
    Routes.securityEvents: (c) => c.identity.securityEvents(),
    Routes.devices: (c) => c.identity.devices(),
    Routes.renameDevice: (c) => c.identity.renameDevice(id, 'n'),
    Routes.revokeDevice: (c) => c.identity.revokeDevice(id),
    Routes.revokeOtherDevices: (c) => c.identity.revokeOtherDevices(),
    Routes.approveLink: (c) =>
        c.identity.approveLink(id, LinkApproveRequest(provision: bytes)),
    Routes.setPushToken: (c) =>
        c.identity.setPushToken(const PushTokenRequest(token: 'p')),
    Routes.clearPushToken: (c) => c.identity.clearPushToken(),
    // keys
    Routes.setSignedPrekey: (c) => c.keys.setSignedPrekey(prekey),
    Routes.addOneTimePrekeys: (c) => c.keys.addOneTimePrekeys(const []),
    Routes.keyStatus: (c) => c.keys.status(),
    Routes.accountKeys: (c) => c.keys.accountKeys(id),
    // messaging
    Routes.sendMessage: (c) =>
        c.messaging.send(const SendMessageRequest(id: id, recipients: [])),
    Routes.mailbox: (c) => c.messaging.mailbox(),
    Routes.ackMailbox: (c) => c.messaging.ack(1),
    // realtime
    Routes.websocket: (c) {
      c.realtime.start();
    },
    // people
    Routes.discoverySalt: (c) => c.people.discoverySalt(),
    Routes.discover: (c) =>
        c.people.discover(const DiscoverRequest(phoneHashes: [])),
    Routes.findByName: (c) => c.people.findByName('alice'),
    Routes.profile: (c) => c.people.profile(id),
    Routes.presence: (c) => c.people.presence(id),
    Routes.setOwnProfile: (c) =>
        c.people.setOwnProfile(EncryptedProfile(version: 1, ciphertext: bytes)),
    Routes.blocks: (c) => c.people.blocks(),
    Routes.block: (c) => c.people.block(id),
    Routes.unblock: (c) => c.people.unblock(id),
    Routes.privacy: (c) => c.people.privacy(),
    Routes.setPrivacy: (c) => c.people.setPrivacy(const PrivacySettings()),
    Routes.setContacts: (c) => c.people.setContacts(const []),
    Routes.report: (c) => c.people.report(
      const ReportRequest(account: id, category: ReportCategory.spam),
    ),
    // groups
    Routes.createGroup: (c) => c.groups.create(
      CreateGroupRequest(groupId: id, encryptedState: bytes, members: const []),
    ),
    Routes.myGroups: (c) => c.groups.list(),
    Routes.group: (c) => c.groups.get(id),
    Routes.deleteGroup: (c) => c.groups.delete(id),
    Routes.setGroupState: (c) => c.groups.setState(
      id,
      SetGroupStateRequest(encryptedState: bytes, expectedVersion: 1),
    ),
    Routes.setGroupSettings: (c) =>
        c.groups.setSettings(id, const GroupSettings()),
    Routes.addGroupMembers: (c) => c.groups.addMembers(id, const []),
    Routes.removeGroupMember: (c) => c.groups.removeMember(id, id),
    Routes.setGroupRole: (c) => c.groups.setRole(id, id, GroupRole.admin),
    Routes.banFromGroup: (c) => c.groups.ban(id, id),
    Routes.unbanFromGroup: (c) => c.groups.unban(id, id),
    Routes.createInviteLink: (c) => c.groups.createInviteLink(
      id,
      CreateInviteLinkRequest(encryptedPreview: bytes),
    ),
    Routes.revokeInviteLink: (c) => c.groups.revokeInviteLink(id, id),
    Routes.previewInviteLink: (c) => c.groups.previewInviteLink('t'),
    Routes.joinGroup: (c) => c.groups.join('t'),
    Routes.joinRequests: (c) => c.groups.joinRequests(id),
    Routes.resolveJoinRequest: (c) =>
        c.groups.resolveJoinRequest(id, id, approve: true),
    Routes.sendGroupMessage: (c) => c.groups.sendMessage(
      id,
      GroupMessageRequest(id: id, payload: bytes, devicesDigest: bytes),
    ),
    // calls
    Routes.turnCredentials: (c) => c.calls.turnCredentials(),
    Routes.sendCallSignal: (c) => c.calls.sendSignal(
      id,
      const CallSignalRequest(kind: CallSignalKind.offer, recipients: []),
    ),
    Routes.setCallState: (c) => c.calls.setState(id, CallState.answered),
    Routes.pendingCalls: (c) => c.calls.pending(),
    Routes.callMetrics: (c) =>
        c.calls.sendMetrics(const CallMetricsRequest(callId: id)),
    // media
    Routes.createUpload: (c) =>
        c.media.createUpload(const CreateUploadRequest(size: 1)),
    Routes.uploadContent: (c) => c.media.uploadContent(id, const [1]),
    Routes.uploadStatus: (c) => c.media.uploadStatus(id),
    Routes.downloadContent: (c) => c.media.download(id),
    Routes.deleteMedia: (c) => c.media.delete(id),
    // backup
    Routes.putHistoryBackup: (c) =>
        c.backup.putHistory(HistoryBackup(version: 1, data: bytes)),
    Routes.getHistoryBackup: (c) => c.backup.history(),
    Routes.deleteHistoryBackup: (c) => c.backup.deleteHistory(),
    Routes.putFullBackup: (c) => c.backup.putFull(
      const FullBackup(backupId: id, version: 1, envelope: {}),
    ),
    Routes.getFullBackup: (c) => c.backup.full(),
    Routes.deleteFullBackup: (c) => c.backup.deleteFull(),
    // ops
    Routes.live: (c) => c.ops.live(),
    Routes.ready: (c) => c.ops.ready(),
    Routes.serverInfo: (c) => c.ops.serverInfo(),
    Routes.legal: (c) => c.ops.legal(),
    Routes.crashReport: (c) => c.ops.crashReport(const CrashReport(name: 'x')),
    Routes.metrics: (c) => c.admin.metrics(),
    Routes.assetLinks: (c) => c.ops.assetLinks(),
    Routes.openLink: (c) => c.ops.openPage(),
    // compliance
    Routes.exportData: (c) => c.compliance.export(),
    Routes.deleteAccount: (c) => c.compliance.deleteAccount(),
    // federation
    Routes.serverIdentity: (c) => c.federation.serverIdentity(),
    // admin
    Routes.adminSetupStatus: (c) => c.admin.setupStatus(),
    Routes.adminSetup: (c) => c.admin.setup('password'),
    Routes.adminSignIn: (c) => c.admin.signIn('password'),
    Routes.adminPassword: (c) =>
        c.admin.changePassword(current: 'a', next: 'b'),
    Routes.adminAccounts: (c) => c.admin.accounts(),
    Routes.adminAccount: (c) => c.admin.account(id),
    Routes.adminSuspend: (c) => c.admin.suspend(id),
    Routes.adminUnsuspend: (c) => c.admin.unsuspend(id),
    Routes.adminBan: (c) => c.admin.ban(id),
    Routes.adminDeleteAccount: (c) => c.admin.deleteAccount(id),
    Routes.adminRevokeDevice: (c) => c.admin.revokeDevice(id, id),
    Routes.adminRecoveryCode: (c) => c.admin.createRecoveryCode(id),
    Routes.adminInvites: (c) => c.admin.invites(),
    Routes.adminCreateInvite: (c) => c.admin.createInvite(),
    Routes.adminCancelInvite: (c) => c.admin.cancelInvite(id),
    Routes.adminReports: (c) => c.admin.reports(),
    Routes.adminResolveReport: (c) =>
        c.admin.resolveReport(id, ReportStatus.resolved),
    Routes.adminAudit: (c) => c.admin.audit(),
    Routes.adminConfig: (c) => c.admin.config(),
    Routes.adminSetConfig: (c) =>
        c.admin.updateConfig(const AdminConfigPatch(maintenance: true)),
    Routes.adminFeatureFlags: (c) => c.admin.featureFlags(),
    Routes.adminSetFeatureFlag: (c) =>
        c.admin.setFeatureFlag('group_calls', enabled: true),
    Routes.adminLogs: (c) => c.admin.logs(),
    Routes.adminLogStream: (c) => c.admin.logStream().listen(null),
    Routes.adminPurge: (c) => c.admin.purge(),
  };

  test('the table names every client route once and no S2S route', () {
    final covered = table().keys.map((r) => r.toString()).toList();
    expect(covered.toSet(), hasLength(covered.length));
    expect(covered.toSet(), {for (final r in clientRoutes) r.toString()});
  });

  for (final MapEntry(key: route, value: invoke) in table().entries) {
    test('$route is sent by its client method', () async {
      final c = Clients();
      try {
        await invoke(c);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      } on HelixApiException {
        // The fake server answers 204 to everything; decoding may fail.
      }
      final requests = [
        for (final s in c.http.seen) (s.method, s.url.path),
        for (final u in c.sockets.uris) ('GET', u.path),
      ];
      expect(requests, hasLength(1), reason: '$route sent $requests');
      final (method, path) = requests.single;
      expect(method, route.method.name.toUpperCase());
      expect(path, matches(_template(route)));
      await c.close();
    });
  }

  test('each route is named by exactly one place in the client sources, in '
      'the client of its module', () {
    final names = _catalogNames();
    final uses = <String, List<String>>{};
    final dir = Directory('lib/src/v2');
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final name = file.uri.pathSegments.last;
      for (final m in RegExp(
        r'\bRoutes\.(\w+)',
      ).allMatches(file.readAsStringSync())) {
        if (m.group(1) == 'all') continue;
        uses.putIfAbsent(m.group(1)!, () => []).add(name);
      }
    }
    for (final MapEntry(key: field, value: route) in names.entries) {
      final files = uses[field] ?? const [];
      if (route.access == RouteAccess.s2s) {
        expect(files, isEmpty, reason: '$route is server-to-server');
        continue;
      }
      expect(files, hasLength(1), reason: '$route used in $files');
      final expected = switch (route) {
        Routes.websocket => 'realtime_client.dart',
        Routes.metrics => 'admin_client.dart', // ops route, admin audience
        _ => '${route.module}_client.dart',
      };
      expect(files.single, expected, reason: '$route');
    }
  });
}

/// The `static const` field name of every catalog route, matched to the
/// route by method and path.
Map<String, ApiRoute> _catalogNames() {
  final source = File(
    '../helix_remote_protocol/lib/src/routes.dart',
  ).readAsStringSync();
  final byKey = {for (final r in Routes.all) r.toString(): r};
  final names = {
    for (final m in RegExp(
      r"static const (\w+) = ApiRoute\(\s*_(\w+),\s*'([^']+)'",
    ).allMatches(source))
      m.group(1)!: byKey['${m.group(2)!.toUpperCase()} ${m.group(3)!}']!,
  };
  expect(names, hasLength(Routes.all.length));
  return names;
}

RegExp _template(ApiRoute route) => RegExp(
  '^${route.path.replaceAll(RegExp(r'\{[a-z_]+\}'), '[^/]+').replaceAll('.', r'\.')}\$',
);

/// One of each client on fake transports.
final class Clients {
  Clients() {
    device = HelixTransport(
      baseUrl: Uri.parse('https://helix.test'),
      client: http.client,
      auth: CountingAuth(),
      retry: RetryPolicy.none,
    );
    adminTransport = HelixTransport(
      baseUrl: Uri.parse('https://helix.test'),
      client: http.client,
      auth: AdminTokenAuth(
        session: AdminSession(
          token: 'admin',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      ),
      retry: RetryPolicy.none,
    );
    http.handler = (_) => noContent();
  }

  final FakeHttp http = FakeHttp();
  final FakeSockets sockets = FakeSockets();
  late final HelixTransport device;
  late final HelixTransport adminTransport;

  late final identity = IdentityClient(device);
  late final keys = KeysClient(device);
  late final messaging = MessagingClient(device);
  late final people = PeopleClient(device);
  late final groups = GroupsClient(device);
  late final calls = CallsClient(device);
  late final media = MediaClient(device);
  late final backup = BackupClient(device);
  late final ops = OpsClient(device);
  late final compliance = ComplianceClient(device);
  late final federation = FederationClient(device);
  late final admin = AdminClient(adminTransport, sockets: sockets.connect);
  late final realtime = RealtimeClient(
    baseUrl: device.baseUrl,
    auth: CountingAuth(),
    connect: sockets.connect,
  );

  Future<void> close() => realtime.dispose();
}
