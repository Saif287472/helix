import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

DeviceRegistration _device() => DeviceRegistration(
  deviceId: deviceA1,
  name: 'Pixel 9',
  platform: DevicePlatform.android,
  identityKey: bytes(32, 1),
  signingKey: bytes(32, 2),
  certificate: DeviceCertificate(createdAt: t0, signature: bytes(64, 3)),
  proof: bytes(64, 4),
);

PrekeyUpload _prekeys() => PrekeyUpload(
  signedPrekey: SignedPrekey(
    id: 7,
    publicKey: bytes(32, 5),
    signature: bytes(64, 6),
  ),
  oneTimePrekeys: [
    OneTimePrekey(id: 1, publicKey: bytes(32, 7)),
    OneTimePrekey(id: 2, publicKey: bytes(32, 8)),
  ],
);

PasswordSetup _password() => PasswordSetup(
  kdf: const KdfParams(),
  salt: bytes(16, 9),
  authKey: bytes(32, 10),
  wrappedIdentityKey: WrappedKey(
    nonce: bytes(12, 11),
    ciphertext: bytes(48, 12),
  ),
);

Session _session() => Session(
  accountId: accountA,
  deviceId: deviceA1,
  accessToken: 'access.jwt',
  accessExpiresAt: t0.add(const Duration(minutes: 15)),
  refreshToken: 'refresh.jwt',
  refreshExpiresAt: t0.add(const Duration(days: 60)),
);

void main() {
  group('identity', () {
    test('registration and sessions', () {
      expectRoundTrip(
        RegisterRequest(
          accountId: accountA,
          identityKey: bytes(32, 13),
          device: _device(),
          prekeys: _prekeys(),
          verificationToken: 'vt',
          password: _password(),
          termsVersion: '2026-09',
          replaceExisting: true,
        ),
        (v) => v.toJson(),
        RegisterRequest.fromJson,
      );
      expectRoundTrip(
        RegisterResponse(session: _session(), replacedExisting: true),
        (v) => v.toJson(),
        RegisterResponse.fromJson,
      );
      expectRoundTrip(
        AddDeviceRequest(
          device: _device(),
          prekeys: _prekeys(),
          linkToken: 'lt',
        ),
        (v) => v.toJson(),
        AddDeviceRequest.fromJson,
      );
      expectRoundTrip(
        RecoveryRedeemRequest(
          recoveryCode: 'rc',
          identityKey: bytes(32),
          device: _device(),
          prekeys: _prekeys(),
        ),
        (v) => v.toJson(),
        RecoveryRedeemRequest.fromJson,
      );
      expectRoundTrip(
        const RecoveryLookupResponse(
          valid: true,
          verificationRequired: true,
          serverName: 'Helix Global',
          accountId: accountA,
        ),
        (v) => v.toJson(),
        RecoveryLookupResponse.fromJson,
      );
    });

    test('a recovery lookup that predates account_id still parses', () {
      final old = RecoveryLookupResponse.fromJson(
        JsonReader.of({'valid': true, 'verification_required': true}),
      );
      expect(old.valid, isTrue);
      expect(old.accountId, isNull);
      expect(const RecoveryLookupResponse(valid: false).toJson(), {
        'valid': false,
        'verification_required': false,
      });
    });

    test('phone, password, links, challenges', () {
      expectRoundTrip(
        const PhoneChallengeRequest(
          phoneNumber: '+8801700000000',
          purpose: PhonePurpose.signIn,
        ),
        (v) => v.toJson(),
        PhoneChallengeRequest.fromJson,
      );
      expectRoundTrip(
        PhoneVerifyResponse(
          verificationToken: 'vt',
          expiresAt: t0,
          accountExists: true,
          hasPassword: false,
        ),
        (v) => v.toJson(),
        PhoneVerifyResponse.fromJson,
      );
      expectRoundTrip(
        PasswordSignInResponse(
          accountId: accountA,
          identityKey: bytes(32),
          wrappedIdentityKey: WrappedKey(
            nonce: bytes(12),
            ciphertext: bytes(48),
          ),
          signInToken: 'st',
          expiresAt: t0,
        ),
        (v) => v.toJson(),
        PasswordSignInResponse.fromJson,
      );
      expectRoundTrip(
        SetPasswordRequest(password: _password(), currentAuthKey: bytes(32)),
        (v) => v.toJson(),
        SetPasswordRequest.fromJson,
      );
      expectRoundTrip(
        LinkPollResponse(
          status: LinkStatus.approved,
          provision: bytes(90),
          linkToken: 'lt',
        ),
        (v) => v.toJson(),
        LinkPollResponse.fromJson,
      );
      expectRoundTrip(
        DeviceSignInRequest(
          accountId: accountA,
          deviceId: deviceA1,
          challengeId: 'c7a1b0e2-0000-7000-8000-000000000001',
          challenge: bytes(32),
          signature: bytes(64),
        ),
        (v) => v.toJson(),
        DeviceSignInRequest.fromJson,
      );
      expectRoundTrip(
        DeviceChallengeResponse(
          challengeId: 'c7a1b0e2-0000-7000-8000-000000000001',
          challenge: bytes(32),
          expiresAt: t0,
        ),
        (v) => v.toJson(),
        DeviceChallengeResponse.fromJson,
      );
      expectRoundTrip(
        DeviceList(
          devices: [
            DeviceInfo(
              deviceId: deviceA1,
              name: 'Pixel',
              platform: DevicePlatform.android,
              createdAt: t0,
              lastSeenOn: t0,
              current: true,
            ),
          ],
        ),
        (v) => v.toJson(),
        DeviceList.fromJson,
      );
    });

    test('weak KDF parameters are flagged, foreign algorithms refused', () {
      expect(const KdfParams().isAcceptable, isTrue);
      expect(const KdfParams(memoryKib: 1024).isAcceptable, isFalse);
      expect(
        () => KdfParams.fromJson(JsonReader.decode('{"alg":"pbkdf2"}')),
        throwsA(isA<ProtocolFormatException>()),
      );
    });

    test('secrets are redacted from toString', () {
      expect(_session().toString(), isNot(contains('jwt')));
      expect(
        const PhoneChallengeRequest(
          phoneNumber: '+8801700000000',
          purpose: PhonePurpose.register,
        ).toString(),
        isNot(contains('1700')),
      );
      expect(
        const RefreshRequest(refreshToken: 'secret-token').toString(),
        isNot(contains('secret')),
      );
    });

    test('helix names', () {
      expect(SetHelixNameRequest.pattern.hasMatch('alice_99'), isTrue);
      expect(SetHelixNameRequest.pattern.hasMatch('Alice'), isFalse);
      expect(SetHelixNameRequest.pattern.hasMatch('9lives'), isFalse);
      expect(SetHelixNameRequest.pattern.hasMatch('ab'), isFalse);
    });
  });

  group('keys', () {
    test('bundles', () {
      expectRoundTrip(
        AccountKeys(
          account: accountB,
          identityKey: bytes(32),
          devices: [
            DeviceBundle(
              deviceId: deviceB1,
              identityKey: bytes(32, 2),
              signingKey: bytes(32, 3),
              certificate: DeviceCertificate(
                createdAt: t0,
                signature: bytes(64),
              ),
              signedPrekey: SignedPrekey(
                id: 1,
                publicKey: bytes(32),
                signature: bytes(64),
              ),
              oneTimePrekey: OneTimePrekey(id: 9, publicKey: bytes(32)),
            ),
          ],
        ),
        (v) => v.toJson(),
        AccountKeys.fromJson,
      );
      expectRoundTrip(
        KeyStatus(
          oneTimeRemaining: 3,
          signedPrekeyId: 2,
          signedPrekeyUpdatedAt: t0,
        ),
        (v) => v.toJson(),
        KeyStatus.fromJson,
      );
    });

    test('signed byte strings are fixed-layout and domain-separated', () {
      final body = deviceCertificateBody(
        accountId: accountA,
        deviceId: deviceA1,
        identityKey: bytes(32),
        signingKey: bytes(32, 2),
        createdAt: t0,
      );
      // label(20) + version(1) + 2 uuids(32) + 2 keys(64) + time(8)
      expect(body.length, 20 + 1 + 32 + 64 + 8);
      expect(String.fromCharCodes(body.sublist(0, 20)), 'helix.v2.device-cert');
      expect(signedPrekeySignatureBody(1, bytes(32)).length, 12 + 4 + 32);
      expect(
        () => signedPrekeySignatureBody(1, bytes(31)),
        throwsArgumentError,
      );
    });
  });

  group('messaging', () {
    test('send, mailbox, ack, group send', () {
      final recipient = Recipient(
        account: accountB,
        devices: [DevicePayload(device: deviceB1, payload: bytes(100))],
      );
      expectRoundTrip(
        SendMessageRequest(
          id: messageM,
          recipients: [recipient],
          urgent: false,
        ),
        (v) => v.toJson(),
        SendMessageRequest.fromJson,
      );
      expectRoundTrip(
        MailboxPage(
          envelopes: [
            Envelope(
              id: messageM,
              kind: EnvelopeKind.message,
              sentAt: t0,
              seq: 41,
              from: const EnvelopeSender(account: accountA, device: deviceA1),
              payload: bytes(64),
              urgent: true,
            ),
          ],
          lastSeq: 41,
          more: false,
        ),
        (v) => v.toJson(),
        MailboxPage.fromJson,
      );
      expectRoundTrip(
        GroupMessageRequest(
          id: messageM,
          payload: bytes(80),
          devicesDigest: bytes(32),
          distributions: [recipient],
        ),
        (v) => v.toJson(),
        GroupMessageRequest.fromJson,
      );
    });

    test('urgent defaults to true, ephemeral to false', () {
      final decoded = SendMessageRequest.fromJson(
        JsonReader.decode('{"id":"x","recipients":[]}'),
      );
      expect(decoded.urgent, isTrue);
      expect(decoded.ephemeral, isFalse);
    });

    test('membersDigest is order independent and content sensitive', () {
      final a = membersDigest({
        accountA: [deviceA1],
        accountB: [deviceB1, 'b2'],
      });
      final b = membersDigest({
        accountB: ['b2', deviceB1],
        accountA: [deviceA1],
      });
      final c = membersDigest({
        accountB: [deviceB1],
        accountA: [deviceA1],
      });
      expect(a, b);
      expect(a, isNot(c));
      expect(a.length, 32);
    });
  });

  group('people, groups, calls, media, backup, ops', () {
    test('round trips', () {
      expectRoundTrip(
        const DiscoverResponse(
          matches: [DiscoverMatch(phoneHash: 'ab', account: accountB)],
          remainingToday: 4000,
        ),
        (v) => v.toJson(),
        DiscoverResponse.fromJson,
      );
      expectRoundTrip(
        EncryptedProfile(
          account: accountA,
          version: 3,
          ciphertext: bytes(60),
          updatedAt: t0,
        ),
        (v) => v.toJson(),
        EncryptedProfile.fromJson,
      );
      expectRoundTrip(
        const PrivacySettings(
          lastSeen: Audience.contacts,
          groupAdd: Audience.nobody,
        ),
        (v) => v.toJson(),
        PrivacySettings.fromJson,
      );
      expectRoundTrip(
        Group(
          groupId: groupG,
          epoch: 2,
          stateVersion: 5,
          encryptedState: bytes(70),
          settings: const GroupSettings(addMembers: GroupPermission.everyone),
          members: [
            GroupMember(account: accountA, role: GroupRole.owner, joinedAt: t0),
          ],
          createdAt: t0,
        ),
        (v) => v.toJson(),
        Group.fromJson,
      );
      expectRoundTrip(
        const AddMembersResponse(
          added: [accountB],
          rejected: {'x': AddMemberRejection.privacy},
          epoch: 2,
        ),
        (v) => v.toJson(),
        AddMembersResponse.fromJson,
      );
      expectRoundTrip(
        CallSignalRequest(
          kind: CallSignalKind.offer,
          recipients: [
            Recipient(
              account: accountB,
              devices: [DevicePayload(device: deviceB1, payload: bytes(300))],
            ),
          ],
        ),
        (v) => v.toJson(),
        CallSignalRequest.fromJson,
      );
      expectRoundTrip(
        PendingCallList(
          calls: [
            PendingCall(
              callId: 'c1',
              from: const EnvelopeSender(account: accountA, device: deviceA1),
              createdAt: t0,
              expiresAt: t0.add(const Duration(minutes: 1)),
              payload: bytes(40),
            ),
          ],
        ),
        (v) => v.toJson(),
        PendingCallList.fromJson,
      );
      expectRoundTrip(
        UploadTarget(
          mediaId: 'm1',
          url: 'https://s3.example/obj?sig=1',
          headers: const {'x-amz-acl': 'private'},
          expiresAt: t0,
          resumable: false,
        ),
        (v) => v.toJson(),
        UploadTarget.fromJson,
      );
      expectRoundTrip(
        HistoryBackup(version: 9, data: bytes(500), updatedAt: t0),
        (v) => v.toJson(),
        HistoryBackup.fromJson,
      );
      expectRoundTrip(
        const ServerInfo(
          name: 'Helix Global',
          version: '2.0.0',
          registration: RegistrationMode.phone,
          maxAttachmentBytes: 100 << 20,
          termsVersion: '2026-09',
          privacyVersion: '2026-09',
        ),
        (v) => v.toJson(),
        ServerInfo.fromJson,
      );
      expectRoundTrip(
        const ReadyResponse(
          ready: false,
          checks: {'database': true, 'event_bus': false},
        ),
        (v) => v.toJson(),
        ReadyResponse.fromJson,
      );
    });

    test('unknown call signal kinds decode as unknown', () {
      final decoded = CallSignalRequest.fromJson(
        JsonReader.decode('{"kind":"hologram","recipients":[]}'),
      );
      expect(decoded.kind, CallSignalKind.unknown);
      expect(decoded.ttl, const Duration(seconds: 60));
    });

    test('sealed call signal plaintext round trips and stays bounded', () {
      final offer = expectRoundTrip(
        const CallSignalPayload(
          type: CallSignalType.offer,
          callId: 'call-0192a4f0',
          media: CallMedia.video,
          sdp: 'v=0',
        ),
        (v) => v.toJson(),
        CallSignalPayload.fromJson,
      );
      expect(offer.type.routedAs, CallSignalKind.offer);
      final ice = expectRoundTrip(
        const CallSignalPayload(
          type: CallSignalType.ice,
          callId: 'call-0192a4f0',
          candidates: [
            IceCandidatePayload(
              candidate: 'candidate:1 1 udp 1 10.0.0.1 9 typ host',
              sdpMid: '0',
              sdpMLineIndex: 0,
            ),
          ],
        ),
        (v) => v.toJson(),
        CallSignalPayload.fromJson,
      );
      expect(ice.type.routedAs, CallSignalKind.update);
      final end = CallSignalPayload.decode(
        const CallSignalPayload(
          type: CallSignalType.end,
          callId: 'call-0192a4f0',
          reason: CallEndReason.answeredElsewhere,
        ).encode(),
      );
      expect(end.reason, CallEndReason.answeredElsewhere);
      expect(end.type.routedAs, CallSignalKind.end);

      // Newer peers: unknown types and reasons decode, never throw.
      final future = CallSignalPayload.fromJson(
        JsonReader.decode(
          '{"v":2,"type":"hologram","call_id":"c","reason":"vapor"}',
        ),
      );
      expect(future.type, CallSignalType.unknown);
      expect(future.reason, CallEndReason.unknown);

      expect(
        () => CallSignalPayload.fromJson(
          JsonReader.of({
            'type': 'offer',
            'call_id': 'c',
            'sdp': 'x' * (CallSignalPayload.maxSdpLength + 1),
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => CallSignalPayload.fromJson(
          JsonReader.of({
            'type': 'ice',
            'call_id': 'c',
            'candidates': [
              for (var i = 0; i <= CallSignalPayload.maxCandidates; i++)
                {'candidate': 'c$i'},
            ],
          }),
        ),
        throwsFormatException,
      );
      // Nothing secret in a stringified signal.
      expect(offer.toString(), isNot(contains('v=0')));
    });
  });

  group('errors', () {
    test('round trip with details and retry', () {
      final error = expectRoundTrip(
        ApiError(
          ErrorCode.deviceListStale,
          message: 'device list changed',
          details: const StaleDevices(
            accounts: [
              StaleAccountDevices(account: accountB, missing: [deviceB1]),
            ],
          ).toJson(),
          retryAfter: const Duration(seconds: 5),
        ),
        (v) => v.toJson(),
        ApiError.fromJson,
      );
      expect(error.status, 409);
      final stale = StaleDevices.fromJson(JsonReader(error.details!));
      expect(stale.accounts.single.missing, [deviceB1]);
    });

    test('unknown codes map to unknown, wire values are unique', () {
      expect(ErrorCode.fromWire('nope'), ErrorCode.unknown);
      final wires = ErrorCode.values.map((c) => c.wire).toList();
      expect(wires.toSet().length, wires.length);
      expect(ErrorCode.rateLimited.isRetryable, isTrue);
      expect(ErrorCode.forbidden.isRetryable, isFalse);
    });
  });
}
