import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Golden wire fixtures in `helix_remote/contracts/v2/fixtures/`. They pin the
/// exact JSON both ends exchange, so an accidental wire change fails here.
/// After an intended change, regenerate with `HELIX_UPDATE_FIXTURES=1 dart test`
/// and review the diff.

DeviceRegistration _deviceRegistration() => DeviceRegistration(
  deviceId: deviceA1,
  name: 'Pixel 9',
  platform: DevicePlatform.android,
  identityKey: bytes(32, 40),
  signingKey: bytes(32, 41),
  certificate: DeviceCertificate(createdAt: t0, signature: bytes(64, 42)),
  proof: bytes(64, 43),
);

PrekeyUpload _prekeys() => PrekeyUpload(
  signedPrekey: SignedPrekey(
    id: 7,
    publicKey: bytes(32, 44),
    signature: bytes(64, 45),
  ),
  oneTimePrekeys: [
    OneTimePrekey(id: 1, publicKey: bytes(32, 46)),
    OneTimePrekey(id: 2, publicKey: bytes(32, 47)),
  ],
);

PasswordSetup _passwordSetup() => PasswordSetup(
  kdf: const KdfParams(),
  salt: bytes(16, 48),
  authKey: bytes(32, 49),
  wrappedIdentityKey: WrappedKey(
    nonce: bytes(12, 50),
    ciphertext: bytes(48, 51),
  ),
);

Session _session() => Session(
  accountId: accountA,
  deviceId: deviceA1,
  accessToken: 'access.jwt.example',
  accessExpiresAt: t0.add(const Duration(minutes: 15)),
  refreshToken: 'refresh.jwt.example',
  refreshExpiresAt: t0.add(const Duration(days: 60)),
);

MediaPointer _avatarPointer() => MediaPointer(
  id: '0192a4f0-0000-7000-8000-0000000000f0',
  key: bytes(32, 52),
  digest: bytes(32, 53),
  size: 48210,
  mime: 'image/png',
  name: 'avatar.png',
);

Recipient _recipientB() => Recipient(
  account: accountB,
  devices: [DevicePayload(device: deviceB1, payload: bytes(96, 55))],
);

Group _groupFixture() => Group(
  groupId: groupG,
  epoch: 3,
  stateVersion: 4,
  encryptedState: bytes(80, 54),
  settings: const GroupSettings(
    addMembers: GroupPermission.everyone,
    editInfo: GroupPermission.admins,
  ),
  members: [
    GroupMember(
      account: accountA,
      role: GroupRole.owner,
      joinedAt: t0.subtract(const Duration(days: 30)),
    ),
    GroupMember(
      account: accountB,
      role: GroupRole.member,
      joinedAt: t0.subtract(const Duration(days: 2)),
    ),
  ],
  createdAt: t0.subtract(const Duration(days: 30)),
  homeServer: 'helix-a.example',
);

/// A full content message in the direct chat with [accountB]; [body] is the
/// part under test.
ContentMessage _message(
  ContentBody body, {
  required String id,
  MessageRef? reply,
  int? expireSeconds,
  bool viewOnce = false,
}) => ContentMessage(
  id: id,
  sentAt: t0,
  conversation: const DirectConversation(to: accountB),
  body: body,
  reply: reply,
  expireSeconds: expireSeconds,
  profileKey: bytes(32, 3),
  viewOnce: viewOnce,
);

/// A fixture entry that decodes the stored JSON with [decode] and re-encodes
/// with [encode], so the test's second assertion stays lossless.
(Object, JsonMap Function(JsonReader)) _dto<T extends Object>(
  T value,
  JsonMap Function(T value) encode,
  T Function(JsonReader json) decode,
) => (value, (json) => encode(decode(json)));

(Object, JsonMap Function(JsonReader)) _content(ContentMessage message) =>
    _dto(message, (v) => v.toJson(), ContentMessage.fromJson);

(Object, JsonMap Function(JsonReader)) _serverFrame(ServerFrame frame) =>
    (frame, (json) => ServerFrame.decode(jsonEncode(json.json)).toJson());

(Object, JsonMap Function(JsonReader)) _clientFrame(ClientFrame frame) =>
    (frame, (json) => ClientFrame.decode(jsonEncode(json.json)).toJson());

/// A literal JSON object passed through unchanged.
(Object, JsonMap Function(JsonReader)) _raw(JsonMap map) =>
    (map, (json) => json.json);

/// The WebSocket close codes, written out. `main` checks them against
/// [RealtimeCloseCode], so renumbering one in `realtime.dart` fails the test.
const _closeCodes = <String, int>{
  'unauthorized': 4001,
  'device_revoked': 4003,
  'suspended': 4004,
  'superseded': 4008,
  'rate_limited': 4029,
  'idle_timeout': 4010,
  'protocol_error': 4400,
  'going_away': 4503,
};

/// Content types covered by a fixture whose name is not `content_<type>`.
const _contentFixtureNames = <String, String>{
  'text': 'content_text',
  'media': 'content_group_media_view_once',
  'reaction': 'content_reaction',
};

final _fixtures = <String, (Object, JsonMap Function(JsonReader))>{
  'content_text': (
    ContentMessage(
      id: messageM,
      sentAt: t0,
      conversation: const DirectConversation(to: accountB),
      body: const TextBody(text: 'Hello Bob'),
      profileKey: bytes(32, 3),
    ),
    (j) => ContentMessage.fromJson(j).toJson(),
  ),
  'content_group_media_view_once': (
    ContentMessage(
      id: messageM,
      sentAt: t0,
      conversation: const GroupConversation(group: groupG),
      body: MediaBody(
        items: [
          MediaItem(
            kind: MediaItemKind.image,
            media: MediaPointer(
              id: '0192a4f0-0000-7000-8000-0000000000ee',
              key: bytes(32, 4),
              digest: bytes(32, 5),
              size: 52311,
              mime: 'image/jpeg',
              blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
            ),
            width: 1280,
            height: 720,
          ),
        ],
      ),
      viewOnce: true,
      expireSeconds: 604800,
    ),
    (j) => ContentMessage.fromJson(j).toJson(),
  ),
  'content_reaction': (
    ContentMessage(
      id: '0192a4f0-0000-7000-8000-0000000000ef',
      sentAt: t0,
      conversation: const DirectConversation(to: accountA),
      body: const ReactionBody(
        target: MessageRef(id: messageM, author: accountA),
        emoji: '👍',
      ),
    ),
    (j) => ContentMessage.fromJson(j).toJson(),
  ),
  'envelope_message': (
    Envelope(
      id: messageM,
      kind: EnvelopeKind.message,
      sentAt: t0,
      seq: 1042,
      from: const EnvelopeSender(account: accountA, device: deviceA1),
      payload: bytes(48, 6),
      urgent: true,
    ),
    (j) => Envelope.fromJson(j).toJson(),
  ),
  'envelope_roster_change': (
    Envelope(
      id: messageM,
      kind: EnvelopeKind.rosterChange,
      sentAt: t0,
      seq: 1043,
      groupId: groupG,
      data: const RosterChangeEvent(
        groupId: groupG,
        change: RosterChangeKind.added,
        epoch: 2,
        actor: accountA,
        members: [accountB],
      ).toJson(),
    ),
    (j) => Envelope.fromJson(j).toJson(),
  ),
  'sealed_prekey_message': (
    PrekeyMessage(
      senderIdentityKey: bytes(32, 7),
      ephemeralKey: bytes(32, 8),
      signedPrekeyId: 3,
      oneTimePrekeyId: 77,
      header: RatchetHeader(
        ratchetKey: bytes(32, 9),
        previousCount: 0,
        count: 0,
      ),
      ciphertext: bytes(176, 10),
    ),
    (j) => PrekeyMessage.fromJson(j).toJson(),
  ),
  'send_message_request': (
    SendMessageRequest(
      id: messageM,
      recipients: [
        Recipient(
          account: accountB,
          devices: [DevicePayload(device: deviceB1, payload: bytes(24, 11))],
        ),
      ],
    ),
    (j) => SendMessageRequest.fromJson(j).toJson(),
  ),
  'error_device_list_stale': (
    const ApiError(
      ErrorCode.deviceListStale,
      message: 'The recipient has new devices.',
      details: {
        'accounts': [
          {
            'account': accountB,
            'missing': [deviceB1],
            'extra': <String>[],
          },
        ],
      },
    ),
    (j) => ApiError.fromJson(j).toJson(),
  ),

  // ------------------------------------------------------- content types
  'content_text_mentions': _content(
    _message(
      TextBody(
        text: '@Bob the build is green',
        mentions: const [Mention(account: accountB, start: 0, length: 4)],
        linkPreview: LinkPreview(
          url: 'https://helix.agiletechbd.com/builds/42',
          title: 'Build 42',
          description: 'All checks passed.',
          image: _avatarPointer(),
        ),
      ),
      id: '0192a4f0-0000-7000-8000-0000000000f9',
      reply: const MessageRef(id: messageM, author: accountB),
      expireSeconds: 86400,
    ),
  ),
  'content_sticker': _content(
    _message(
      StickerBody(
        packId: 'orbit-basics',
        stickerId: 'wave-01',
        media: MediaPointer(
          id: '0192a4f0-0000-7000-8000-0000000000f0',
          key: bytes(32, 4),
          digest: bytes(32, 5),
          size: 18840,
          mime: 'image/webp',
          name: 'wave-01.webp',
        ),
        emoji: '👋',
      ),
      id: '0192a4f0-0000-7000-8000-0000000000e2',
    ),
  ),
  'content_location': _content(
    _message(
      const LocationBody(
        latE7: 237777000,
        lngE7: 904000000,
        accuracyM: 12,
        label: 'Home',
        address: 'House 12, Road 5, Dhaka',
      ),
      id: '0192a4f0-0000-7000-8000-0000000000e3',
    ),
  ),
  'content_live_location': _content(
    _message(
      LiveLocationBody(
        sessionId: '0192a4f0-0000-7000-8000-0000000000e4',
        state: LiveLocationState.update,
        latE7: 237778000,
        lngE7: 904010000,
        accuracyM: 8,
        expiresAt: t0.add(const Duration(minutes: 15)),
      ),
      id: '0192a4f0-0000-7000-8000-0000000000e4',
    ),
  ),
  'content_contact': _content(
    _message(
      const ContactBody(
        name: 'Carol',
        numbers: ['+8801712345678'],
        account: accountB,
      ),
      id: '0192a4f0-0000-7000-8000-0000000000e5',
    ),
  ),
  'content_poll': _content(
    _message(
      PollBody(
        question: 'Where should we eat on Friday?',
        options: const [
          PollOption(id: 'o1', text: 'Dhaba'),
          PollOption(id: 'o2', text: 'Thai place'),
          PollOption(id: 'o3', text: 'Cook at home'),
        ],
        multiple: true,
        closesAt: t0.add(const Duration(days: 1)),
      ),
      id: '0192a4f0-0000-7000-8000-0000000000e6',
    ),
  ),
  'content_event': _content(
    _message(
      EventBody(
        title: 'Team dinner',
        startsAt: t0.add(const Duration(days: 3)),
        endsAt: t0.add(const Duration(days: 3, hours: 2)),
        timeZone: 'Asia/Dhaka',
        locationText: 'Gulshan 2',
        plusOneAllowed: true,
      ),
      id: '0192a4f0-0000-7000-8000-0000000000e7',
    ),
  ),
  'content_system': _content(
    _message(
      const SystemBody(kind: 'timer_changed', fields: {'seconds': 86400}),
      id: '0192a4f0-0000-7000-8000-0000000000e8',
    ),
  ),
  'content_call_log': _content(
    _message(
      const CallLogBody(
        callId: '0192a4f0-0000-7000-8000-0000000000e9',
        media: CallMedia.video,
        outcome: CallOutcome.answered,
        durationS: 95,
      ),
      id: '0192a4f0-0000-7000-8000-0000000000e9',
    ),
  ),
  'content_edit': _content(
    _message(
      const EditBody(
        target: MessageRef(id: messageM, author: accountA),
        text: 'Hello Bob, edited',
      ),
      id: '0192a4f0-0000-7000-8000-0000000000ea',
    ),
  ),
  'content_delete': _content(
    _message(
      const DeleteBody(
        target: MessageRef(id: messageM, author: accountA),
      ),
      id: '0192a4f0-0000-7000-8000-0000000000eb',
    ),
  ),
  'content_poll_vote': _content(
    _message(
      const PollVoteBody(
        target: MessageRef(id: messageM, author: accountB),
        optionIds: ['o1', 'o3'],
      ),
      id: '0192a4f0-0000-7000-8000-0000000000ec',
    ),
  ),
  'content_rsvp': _content(
    _message(
      const RsvpBody(
        target: MessageRef(id: messageM, author: accountB),
        state: RsvpState.maybe,
        plusOne: true,
      ),
      id: '0192a4f0-0000-7000-8000-0000000000ed',
    ),
  ),
  'content_receipt': _content(
    _message(
      const ReceiptBody(
        kind: ReceiptKind.viewed,
        ids: [messageM, '0192a4f0-0000-7000-8000-0000000000ee'],
      ),
      id: '0192a4f0-0000-7000-8000-0000000000ee',
    ),
  ),
  'content_typing': _content(
    _message(
      const TypingBody(state: TypingState.stopped),
      id: '0192a4f0-0000-7000-8000-0000000000f1',
    ),
  ),
  'content_sender_key_distribution': _content(
    _message(
      SenderKeyDistributionBody(
        groupId: groupG,
        distributionId: '0192a4f0-0000-7000-8000-0000000000f2',
        iteration: 7,
        chainKey: bytes(32, 56),
        signingKey: bytes(32, 57),
      ),
      id: '0192a4f0-0000-7000-8000-0000000000f2',
    ),
  ),
  'content_group_key': _content(
    _message(
      GroupKeyBody(groupId: groupG, epoch: 4, key: bytes(32, 58)),
      id: '0192a4f0-0000-7000-8000-0000000000f3',
    ),
  ),
  'content_profile_key_update': _content(
    _message(
      ProfileKeyUpdateBody(key: bytes(32, 59), version: 2),
      id: '0192a4f0-0000-7000-8000-0000000000f4',
    ),
  ),
  'content_decryption_error': _content(
    _message(
      const DecryptionErrorBody(messageId: messageM, senderDevice: deviceB1),
      id: '0192a4f0-0000-7000-8000-0000000000f5',
    ),
  ),
  'content_resend_request': _content(
    _message(
      const ResendRequestBody(ids: [messageM]),
      id: '0192a4f0-0000-7000-8000-0000000000f6',
    ),
  ),
  'content_contact_sync': _content(
    _message(
      const ContactSyncBody(
        entries: [
          ContactSyncEntry(account: accountB, nickname: 'Bobby'),
          ContactSyncEntry(account: accountA),
        ],
      ),
      id: '0192a4f0-0000-7000-8000-0000000000f7',
    ),
  ),
  'content_device_transfer_offer': _content(
    _message(
      const DeviceTransferOfferBody(
        transferId: '0192a4f0-0000-7000-8000-0000000000f8',
        state: DeviceTransferState.cancelled,
        devices: [deviceA1],
      ),
      id: '0192a4f0-0000-7000-8000-0000000000f8',
    ),
  ),

  // ------------------------------------------------------- realtime frames
  'realtime_hello': (
    HelloFrame(
      serverTime: t0,
      heartbeatSeconds: 25,
      window: 100,
      lastSeq: 1041,
      seqHead: 1041,
    ),
    (j) => ServerFrame.decode(jsonEncode(j.json)).toJson(),
  ),
  'realtime_envelope_frame': _serverFrame(
    EnvelopeFrame(
      Envelope(
        id: '0192a4f0-0000-7000-8000-0000000000e1',
        kind: EnvelopeKind.groupMessage,
        sentAt: t0,
        seq: 1042,
        from: const EnvelopeSender(account: accountA, device: deviceA1),
        groupId: groupG,
        payload: bytes(192, 90),
        urgent: true,
      ),
    ),
  ),
  'realtime_wake_frame': _serverFrame(const WakeFrame()),
  'realtime_pong_frame': _serverFrame(const PongFrame(nonce: 'probe-42')),
  'realtime_error_frame': _serverFrame(
    const ErrorFrame(
      code: 'rate_limited',
      message: 'Too many connection attempts.',
    ),
  ),
  'realtime_client_ack_frame': _clientFrame(const AckFrame(seq: 1042)),
  'realtime_client_ping_frame': _clientFrame(
    const PingFrame(nonce: 'heartbeat-1'),
  ),
  'realtime_unknown_server_frame': _serverFrame(
    const UnknownServerFrame(type: 'presence_update', seq: 77),
  ),
  'realtime_close_codes': _raw(_closeCodes),

  // ------------------------------------------------------------- identity
  'identity_register_request': _dto(
    RegisterRequest(
      accountId: accountA,
      identityKey: bytes(32, 60),
      device: _deviceRegistration(),
      prekeys: _prekeys(),
      verificationToken: 'verify-token',
      password: _passwordSetup(),
      termsVersion: '2026-10',
      replaceExisting: true,
    ),
    (v) => v.toJson(),
    RegisterRequest.fromJson,
  ),
  'identity_register_response': _dto(
    RegisterResponse(session: _session(), replacedExisting: true),
    (v) => v.toJson(),
    RegisterResponse.fromJson,
  ),
  'identity_session': _dto(_session(), (v) => v.toJson(), Session.fromJson),
  'identity_phone_challenge_request': _dto(
    const PhoneChallengeRequest(
      phoneNumber: '+8801700000000',
      purpose: PhonePurpose.signIn,
    ),
    (v) => v.toJson(),
    PhoneChallengeRequest.fromJson,
  ),
  'identity_phone_challenge_response': _dto(
    PhoneChallengeResponse(
      challengeId: '0192a4f0-0000-7000-8000-0000000000d0',
      expiresAt: t0.add(const Duration(minutes: 5)),
      resendAfter: const Duration(seconds: 30),
    ),
    (v) => v.toJson(),
    PhoneChallengeResponse.fromJson,
  ),
  'identity_phone_verify_request': _dto(
    const PhoneVerifyRequest(
      challengeId: '0192a4f0-0000-7000-8000-0000000000d0',
      code: '402913',
    ),
    (v) => v.toJson(),
    PhoneVerifyRequest.fromJson,
  ),
  'identity_phone_verify_response': _dto(
    PhoneVerifyResponse(
      verificationToken: 'verified-token',
      expiresAt: t0.add(const Duration(minutes: 10)),
      accountExists: true,
      hasPassword: true,
      accountId: accountA,
    ),
    (v) => v.toJson(),
    PhoneVerifyResponse.fromJson,
  ),
  'identity_account_status_request': _dto(
    const AccountStatusRequest(phoneNumber: '+8801700000000'),
    (v) => v.toJson(),
    AccountStatusRequest.fromJson,
  ),
  'identity_account_status_response': _dto(
    const AccountStatusResponse(accountExists: true, hasPassword: true),
    (v) => v.toJson(),
    AccountStatusResponse.fromJson,
  ),
  'identity_invite_lookup_request': _dto(
    const InviteLookupRequest(inviteCode: 'HLX-INV-7f3a9c'),
    (v) => v.toJson(),
    InviteLookupRequest.fromJson,
  ),
  'identity_invite_lookup_response': _dto(
    const InviteLookupResponse(valid: true, serverName: 'Helix Global'),
    (v) => v.toJson(),
    InviteLookupResponse.fromJson,
  ),
  'identity_invite_self_issue_response': _dto(
    InviteSelfIssueResponse(
      inviteCode: 'HLX-SELF-2b81d4',
      expiresAt: t0.add(const Duration(days: 7)),
    ),
    (v) => v.toJson(),
    InviteSelfIssueResponse.fromJson,
  ),
  'identity_password_params_request': _dto(
    const PasswordParamsRequest(phoneNumber: '+8801700000000'),
    (v) => v.toJson(),
    PasswordParamsRequest.fromJson,
  ),
  'identity_password_params_response': _dto(
    PasswordParamsResponse(
      kdf: const KdfParams(memoryKib: 65536, iterations: 3, parallelism: 2),
      salt: bytes(16, 61),
    ),
    (v) => v.toJson(),
    PasswordParamsResponse.fromJson,
  ),
  'identity_password_sign_in_request': _dto(
    PasswordSignInRequest(
      phoneNumber: '+8801700000000',
      authKey: bytes(32, 62),
    ),
    (v) => v.toJson(),
    PasswordSignInRequest.fromJson,
  ),
  'identity_password_sign_in_response': _dto(
    PasswordSignInResponse(
      accountId: accountA,
      identityKey: bytes(32, 60),
      wrappedIdentityKey: WrappedKey(
        nonce: bytes(12, 50),
        ciphertext: bytes(48, 51),
      ),
      signInToken: 'sign-in-token',
      expiresAt: t0.add(const Duration(minutes: 5)),
    ),
    (v) => v.toJson(),
    PasswordSignInResponse.fromJson,
  ),
  'identity_set_password_request': _dto(
    SetPasswordRequest(
      password: _passwordSetup(),
      currentAuthKey: bytes(32, 63),
    ),
    (v) => v.toJson(),
    SetPasswordRequest.fromJson,
  ),
  'identity_link_create_request': _dto(
    LinkCreateRequest(ephemeralKey: bytes(32, 64)),
    (v) => v.toJson(),
    LinkCreateRequest.fromJson,
  ),
  'identity_link_create_response': _dto(
    LinkCreateResponse(
      linkId: '0192a4f0-0000-7000-8000-0000000000d1',
      pollToken: 'poll-token',
      expiresAt: t0.add(const Duration(minutes: 2)),
    ),
    (v) => v.toJson(),
    LinkCreateResponse.fromJson,
  ),
  'identity_link_approve_request': _dto(
    LinkApproveRequest(provision: bytes(120, 65)),
    (v) => v.toJson(),
    LinkApproveRequest.fromJson,
  ),
  'identity_link_poll_response': _dto(
    LinkPollResponse(
      status: LinkStatus.approved,
      provision: bytes(120, 66),
      linkToken: 'link-token',
    ),
    (v) => v.toJson(),
    LinkPollResponse.fromJson,
  ),
  'identity_add_device_request': _dto(
    AddDeviceRequest(
      device: _deviceRegistration(),
      prekeys: _prekeys(),
      signInToken: 'sign-in-token',
    ),
    (v) => v.toJson(),
    AddDeviceRequest.fromJson,
  ),
  'identity_device_challenge_request': _dto(
    const DeviceChallengeRequest(accountId: accountA, deviceId: deviceA1),
    (v) => v.toJson(),
    DeviceChallengeRequest.fromJson,
  ),
  'identity_device_challenge_response': _dto(
    DeviceChallengeResponse(
      challengeId: '0192a4f0-0000-7000-8000-0000000000d2',
      challenge: bytes(32, 67),
      expiresAt: t0.add(const Duration(minutes: 5)),
    ),
    (v) => v.toJson(),
    DeviceChallengeResponse.fromJson,
  ),
  'identity_device_sign_in_request': _dto(
    DeviceSignInRequest(
      accountId: accountA,
      deviceId: deviceA1,
      challengeId: '0192a4f0-0000-7000-8000-0000000000d2',
      challenge: bytes(32, 68),
      signature: bytes(64, 69),
    ),
    (v) => v.toJson(),
    DeviceSignInRequest.fromJson,
  ),
  'identity_refresh_request': _dto(
    const RefreshRequest(refreshToken: 'refresh.jwt.example'),
    (v) => v.toJson(),
    RefreshRequest.fromJson,
  ),
  'identity_recovery_lookup_request': _dto(
    const RecoveryLookupRequest(recoveryCode: 'HLX-REC-4c8e71'),
    (v) => v.toJson(),
    RecoveryLookupRequest.fromJson,
  ),
  'identity_recovery_lookup_response': _dto(
    const RecoveryLookupResponse(
      valid: true,
      verificationRequired: true,
      serverName: 'Helix Global',
      accountId: accountA,
    ),
    (v) => v.toJson(),
    RecoveryLookupResponse.fromJson,
  ),
  'identity_recovery_redeem_request': _dto(
    RecoveryRedeemRequest(
      recoveryCode: 'HLX-REC-4c8e71',
      identityKey: bytes(32, 60),
      device: _deviceRegistration(),
      prekeys: _prekeys(),
      verificationToken: 'verified-token',
    ),
    (v) => v.toJson(),
    RecoveryRedeemRequest.fromJson,
  ),
  'identity_account_info': _dto(
    AccountInfo(
      accountId: accountA,
      identityKey: bytes(32, 60),
      createdAt: t0.subtract(const Duration(days: 120)),
      hasPassword: true,
      helixName: 'alice',
      phoneLast4: '0000',
      passwordUpdatedAt: t0.subtract(const Duration(days: 7)),
    ),
    (v) => v.toJson(),
    AccountInfo.fromJson,
  ),
  'identity_set_phone_number_request': _dto(
    const SetPhoneNumberRequest(phoneNumber: '+8801700000000'),
    (v) => v.toJson(),
    SetPhoneNumberRequest.fromJson,
  ),
  'identity_set_helix_name_request': _dto(
    const SetHelixNameRequest(name: 'alice_99'),
    (v) => v.toJson(),
    SetHelixNameRequest.fromJson,
  ),
  'identity_device_list': _dto(
    DeviceList(
      devices: [
        DeviceInfo(
          deviceId: deviceA1,
          name: 'Pixel 9',
          platform: DevicePlatform.android,
          createdAt: t0.subtract(const Duration(days: 60)),
          lastSeenOn: t0.subtract(const Duration(hours: 3)),
          current: true,
        ),
        DeviceInfo(
          deviceId: '0192a4f0-0000-7000-8000-0000000000a2',
          name: 'Workstation',
          platform: DevicePlatform.windows,
          createdAt: t0.subtract(const Duration(days: 10)),
          lastSeenOn: t0.subtract(const Duration(days: 1)),
          current: false,
        ),
      ],
    ),
    (v) => v.toJson(),
    DeviceList.fromJson,
  ),
  'identity_rename_device_request': _dto(
    const RenameDeviceRequest(name: 'Alice laptop'),
    (v) => v.toJson(),
    RenameDeviceRequest.fromJson,
  ),
  'identity_revoke_others_response': _dto(
    const RevokeOthersResponse(revoked: 2),
    (v) => v.toJson(),
    RevokeOthersResponse.fromJson,
  ),
  'identity_push_token_request': _dto(
    const PushTokenRequest(
      token: 'apns-token-example',
      kind: PushTokenKind.apnsVoip,
    ),
    (v) => v.toJson(),
    PushTokenRequest.fromJson,
  ),
  'identity_security_event': _dto(
    SecurityEvent(
      kind: SecurityEventKind.deviceRevoked,
      at: t0.subtract(const Duration(hours: 5)),
      deviceId: deviceB1,
      deviceName: 'Bob phone',
    ),
    (v) => v.toJson(),
    SecurityEvent.fromJson,
  ),

  // ----------------------------------------------------------------- keys
  'keys_signed_prekey': _dto(
    SignedPrekey(id: 8, publicKey: bytes(32, 70), signature: bytes(64, 71)),
    (v) => v.toJson(),
    SignedPrekey.fromJson,
  ),
  'keys_add_one_time_prekeys_request': _dto(
    AddOneTimePrekeysRequest(
      keys: [
        OneTimePrekey(id: 100, publicKey: bytes(32, 72)),
        OneTimePrekey(id: 101, publicKey: bytes(32, 73)),
      ],
    ),
    (v) => v.toJson(),
    AddOneTimePrekeysRequest.fromJson,
  ),
  'keys_status': _dto(
    KeyStatus(
      oneTimeRemaining: 18,
      signedPrekeyId: 8,
      signedPrekeyUpdatedAt: t0.subtract(const Duration(days: 4)),
    ),
    (v) => v.toJson(),
    KeyStatus.fromJson,
  ),
  'keys_account_keys': _dto(
    AccountKeys(
      account: accountB,
      identityKey: bytes(32, 74),
      devices: [
        DeviceBundle(
          deviceId: deviceB1,
          identityKey: bytes(32, 75),
          signingKey: bytes(32, 76),
          certificate: DeviceCertificate(
            createdAt: t0.subtract(const Duration(days: 20)),
            signature: bytes(64, 77),
          ),
          signedPrekey: SignedPrekey(
            id: 8,
            publicKey: bytes(32, 70),
            signature: bytes(64, 71),
          ),
          oneTimePrekey: OneTimePrekey(id: 9, publicKey: bytes(32, 78)),
        ),
      ],
    ),
    (v) => v.toJson(),
    AccountKeys.fromJson,
  ),

  // ------------------------------------------------------------ messaging
  'messaging_send_message_response': _dto(
    SendMessageResponse(acceptedAt: t0, replayed: true, blockedBy: [accountB]),
    (v) => v.toJson(),
    SendMessageResponse.fromJson,
  ),
  'messaging_mailbox_page': _dto(
    MailboxPage(
      envelopes: [
        Envelope(
          id: '0192a4f0-0000-7000-8000-0000000000e1',
          kind: EnvelopeKind.message,
          sentAt: t0,
          seq: 1042,
          from: const EnvelopeSender(account: accountB, device: deviceB1),
          payload: bytes(160, 79),
          urgent: true,
        ),
      ],
      lastSeq: 1042,
      more: true,
      seqHead: 1050,
    ),
    (v) => v.toJson(),
    MailboxPage.fromJson,
  ),
  'messaging_ack_request': _dto(
    const AckRequest(seq: 1042),
    (v) => v.toJson(),
    AckRequest.fromJson,
  ),
  'messaging_ack_response': _dto(
    const AckResponse(deleted: 3),
    (v) => v.toJson(),
    AckResponse.fromJson,
  ),
  'messaging_group_message_request': _dto(
    GroupMessageRequest(
      id: messageM,
      payload: bytes(200, 80),
      devicesDigest: bytes(32, 81),
      distributions: [_recipientB()],
      urgent: true,
      ephemeral: false,
    ),
    (v) => v.toJson(),
    GroupMessageRequest.fromJson,
  ),

  // --------------------------------------------------------------- people
  'people_discovery_salt': _dto(
    DiscoverySalt(salt: bytes(32, 82), version: 1),
    (v) => v.toJson(),
    DiscoverySalt.fromJson,
  ),
  'people_discover_request': _dto(
    const DiscoverRequest(
      phoneHashes: ['a1b2c3d4e5f60718', '0918273645abcdef'],
      fullSync: true,
    ),
    (v) => v.toJson(),
    DiscoverRequest.fromJson,
  ),
  'people_discover_response': _dto(
    const DiscoverResponse(
      matches: [
        DiscoverMatch(phoneHash: 'a1b2c3d4e5f60718', account: accountB),
      ],
      remainingToday: 998,
    ),
    (v) => v.toJson(),
    DiscoverResponse.fromJson,
  ),
  'people_find_by_name_response': _dto(
    const FindByNameResponse(account: accountB, name: 'bob'),
    (v) => v.toJson(),
    FindByNameResponse.fromJson,
  ),
  'people_encrypted_profile': _dto(
    EncryptedProfile(
      account: accountA,
      version: 4,
      ciphertext: bytes(96, 83),
      updatedAt: t0.subtract(const Duration(days: 1)),
    ),
    (v) => v.toJson(),
    EncryptedProfile.fromJson,
  ),
  'people_presence_response': _dto(
    PresenceResponse(
      account: accountB,
      online: true,
      lastSeenAt: t0.subtract(const Duration(minutes: 2)),
    ),
    (v) => v.toJson(),
    PresenceResponse.fromJson,
  ),
  'people_set_own_name_request': _dto(
    const SetOwnNameRequest(name: 'Alice Rahman'),
    (v) => v.toJson(),
    SetOwnNameRequest.fromJson,
  ),
  'people_block_list': _dto(
    const BlockList(accounts: [accountB]),
    (v) => v.toJson(),
    BlockList.fromJson,
  ),
  'people_privacy_settings': _dto(
    const PrivacySettings(
      discoverableByPhone: false,
      discoverableByName: true,
      lastSeen: Audience.contacts,
      online: Audience.nobody,
      groupAdd: Audience.contacts,
      phoneNumber: '+8801700000000',
    ),
    (v) => v.toJson(),
    PrivacySettings.fromJson,
  ),
  'people_set_contacts_request': _dto(
    const SetContactsRequest(accounts: [accountB, accountA]),
    (v) => v.toJson(),
    SetContactsRequest.fromJson,
  ),
  'people_report_request': _dto(
    const ReportRequest(
      account: accountB,
      category: ReportCategory.impersonation,
      note: 'Pretends to be my bank.',
    ),
    (v) => v.toJson(),
    ReportRequest.fromJson,
  ),
  'people_report_response': _dto(
    const ReportResponse(reportId: '0192a4f0-0000-7000-8000-0000000000d3'),
    (v) => v.toJson(),
    ReportResponse.fromJson,
  ),

  // --------------------------------------------------------------- groups
  'groups_group': _dto(_groupFixture(), (v) => v.toJson(), Group.fromJson),
  'groups_group_state_content': _dto(
    GroupStateContent(
      name: 'Weekend crew',
      description: 'People who actually show up.',
      avatar: _avatarPointer().toJson(),
    ),
    (v) => v.toJson(),
    GroupStateContent.fromJson,
  ),
  'groups_create_group_request': _dto(
    CreateGroupRequest(
      groupId: groupG,
      encryptedState: bytes(120, 84),
      members: const [accountB],
      settings: const GroupSettings(
        addMembers: GroupPermission.everyone,
        sendMessages: GroupPermission.everyone,
      ),
    ),
    (v) => v.toJson(),
    CreateGroupRequest.fromJson,
  ),
  'groups_group_summary': _dto(
    const GroupSummary(groupId: groupG, epoch: 3, stateVersion: 4),
    (v) => v.toJson(),
    GroupSummary.fromJson,
  ),
  'groups_group_list': _dto(
    const GroupList(
      groups: [
        GroupSummary(groupId: groupG, epoch: 3, stateVersion: 4),
        GroupSummary(
          groupId: '0192a4f0-0000-7000-8000-0000000000cd',
          epoch: 1,
          stateVersion: 2,
        ),
      ],
    ),
    (v) => v.toJson(),
    GroupList.fromJson,
  ),
  'groups_set_group_state_request': _dto(
    SetGroupStateRequest(encryptedState: bytes(140, 85), expectedVersion: 4),
    (v) => v.toJson(),
    SetGroupStateRequest.fromJson,
  ),
  'groups_group_version_response': _dto(
    const GroupVersionResponse(epoch: 4, stateVersion: 5),
    (v) => v.toJson(),
    GroupVersionResponse.fromJson,
  ),
  'groups_add_members_request': _dto(
    const AddMembersRequest(accounts: [accountB]),
    (v) => v.toJson(),
    AddMembersRequest.fromJson,
  ),
  'groups_add_members_response': _dto(
    const AddMembersResponse(
      added: [accountB],
      rejected: {
        '0192a4f0-0000-7000-8000-0000000000ce': AddMemberRejection.privacy,
        '0192a4f0-0000-7000-8000-0000000000cf': AddMemberRejection.banned,
      },
      epoch: 4,
    ),
    (v) => v.toJson(),
    AddMembersResponse.fromJson,
  ),
  'groups_set_role_request': _dto(
    const SetRoleRequest(role: GroupRole.admin),
    (v) => v.toJson(),
    SetRoleRequest.fromJson,
  ),
  'groups_create_invite_link_request': _dto(
    CreateInviteLinkRequest(
      encryptedPreview: bytes(100, 86),
      requiresApproval: true,
      expiresAt: t0.add(const Duration(days: 14)),
    ),
    (v) => v.toJson(),
    CreateInviteLinkRequest.fromJson,
  ),
  'groups_invite_link': _dto(
    InviteLink(
      linkId: '0192a4f0-0000-7000-8000-0000000000d4',
      token: 'grp_7c2f1e9a4b',
      requiresApproval: true,
      createdAt: t0.subtract(const Duration(days: 1)),
      expiresAt: t0.add(const Duration(days: 13)),
    ),
    (v) => v.toJson(),
    InviteLink.fromJson,
  ),
  'groups_invite_token_request': _dto(
    const InviteTokenRequest(token: 'grp_7c2f1e9a4b'),
    (v) => v.toJson(),
    InviteTokenRequest.fromJson,
  ),
  'groups_invite_preview': _dto(
    InvitePreview(
      groupId: groupG,
      memberCount: 6,
      requiresApproval: true,
      encryptedPreview: bytes(100, 86),
    ),
    (v) => v.toJson(),
    InvitePreview.fromJson,
  ),
  'groups_join_group_response': _dto(
    const JoinGroupResponse(groupId: groupG, status: JoinStatus.pending),
    (v) => v.toJson(),
    JoinGroupResponse.fromJson,
  ),
  'groups_join_request': _dto(
    JoinRequest(
      requestId: '0192a4f0-0000-7000-8000-0000000000d5',
      account: accountB,
      createdAt: t0.subtract(const Duration(hours: 6)),
    ),
    (v) => v.toJson(),
    JoinRequest.fromJson,
  ),
  'groups_invite_link_list': _dto(
    InviteLinkList(
      links: [
        InviteLinkSummary(
          linkId: '0192a4f0-0000-7000-8000-0000000000d4',
          requiresApproval: true,
          createdAt: t0.subtract(const Duration(days: 1)),
          createdBy: accountA,
          expiresAt: t0.add(const Duration(days: 13)),
        ),
      ],
    ),
    (v) => v.toJson(),
    InviteLinkList.fromJson,
  ),
  'groups_join_request_list': _dto(
    JoinRequestList(
      requests: [
        JoinRequest(
          requestId: '0192a4f0-0000-7000-8000-0000000000d5',
          account: accountB,
          createdAt: t0.subtract(const Duration(hours: 6)),
        ),
      ],
    ),
    (v) => v.toJson(),
    JoinRequestList.fromJson,
  ),
  'groups_resolve_join_request': _dto(
    const ResolveJoinRequest(approve: false),
    (v) => v.toJson(),
    ResolveJoinRequest.fromJson,
  ),

  // ---------------------------------------------------------------- calls
  'calls_turn_credentials': _dto(
    TurnCredentials(
      urls: const [
        'turn:turn.helix.example:3478?transport=udp',
        'turns:turn.helix.example:5349?transport=tcp',
      ],
      username: '1759280000:0192a4f0',
      credential: 'turn-credential-example',
      expiresAt: t0.add(const Duration(hours: 1)),
    ),
    (v) => v.toJson(),
    TurnCredentials.fromJson,
  ),
  'calls_call_signal_request': _dto(
    CallSignalRequest(
      kind: CallSignalKind.offer,
      recipients: [_recipientB()],
      ttl: const Duration(seconds: 90),
    ),
    (v) => v.toJson(),
    CallSignalRequest.fromJson,
  ),
  'calls_call_signal_response': _dto(
    const CallSignalResponse(
      delivered: [deviceB1],
      pending: ['0192a4f0-0000-7000-8000-0000000000b2'],
    ),
    (v) => v.toJson(),
    CallSignalResponse.fromJson,
  ),
  'calls_call_state_request': _dto(
    const CallStateRequest(state: CallState.answered),
    (v) => v.toJson(),
    CallStateRequest.fromJson,
  ),
  'calls_pending_call_list': _dto(
    PendingCallList(
      calls: [
        PendingCall(
          callId: '0192a4f0-0000-7000-8000-0000000000e9',
          from: const EnvelopeSender(account: accountB, device: deviceB1),
          createdAt: t0,
          expiresAt: t0.add(const Duration(seconds: 60)),
          payload: bytes(320, 87),
        ),
      ],
    ),
    (v) => v.toJson(),
    PendingCallList.fromJson,
  ),

  // ---------------------------------------------------------------- media
  'media_create_upload_request': _dto(
    const CreateUploadRequest(size: 52311, kind: MediaKind.persistent),
    (v) => v.toJson(),
    CreateUploadRequest.fromJson,
  ),
  'media_upload_target': _dto(
    UploadTarget(
      mediaId: '0192a4f0-0000-7000-8000-0000000000d6',
      url: '/v1/media/0192a4f0-0000-7000-8000-0000000000d6/content',
      method: 'PUT',
      headers: const {
        'upload-offset': '0',
        'content-type': 'application/octet-stream',
      },
      expiresAt: t0.add(const Duration(minutes: 30)),
      resumable: false,
    ),
    (v) => v.toJson(),
    UploadTarget.fromJson,
  ),

  // --------------------------------------------------------------- backup
  'backup_history_backup': _dto(
    HistoryBackup(
      version: 7,
      data: bytes(400, 88),
      updatedAt: t0.subtract(const Duration(hours: 2)),
    ),
    (v) => v.toJson(),
    HistoryBackup.fromJson,
  ),
  'backup_full_backup': _dto(
    FullBackup(
      backupId: '0192a4f0-0000-7000-8000-0000000000d7',
      version: 3,
      envelope: {
        'v': 3,
        'salt': encodeBytes(bytes(16, 89)),
        'nonce': encodeBytes(bytes(12, 90)),
        'ct': encodeBytes(bytes(512, 91)),
      },
      mediaIds: const ['0192a4f0-0000-7000-8000-0000000000d8'],
      updatedAt: t0.subtract(const Duration(days: 1)),
    ),
    (v) => v.toJson(),
    FullBackup.fromJson,
  ),
  'backup_full_backup_meta': _dto(
    FullBackupMeta(
      exists: true,
      updatedAt: t0.subtract(const Duration(days: 1)),
    ),
    (v) => v.toJson(),
    FullBackupMeta.fromJson,
  ),

  // ------------------------------------------------------------------ ops
  'ops_live_response': _dto(
    LiveResponse(time: t0),
    (v) => v.toJson(),
    LiveResponse.fromJson,
  ),
  'ops_ready_response': _dto(
    const ReadyResponse(
      ready: true,
      checks: {'database': true, 'event_bus': true, 'storage': false},
    ),
    (v) => v.toJson(),
    ReadyResponse.fromJson,
  ),
  'ops_server_info': _dto(
    const ServerInfo(
      name: 'Helix Global',
      version: '2.4.0',
      registration: RegistrationMode.phone,
      maxAttachmentBytes: 4294967296,
      termsVersion: '2026-10',
      privacyVersion: '2026-10',
      federationDomain: 'helix.agiletechbd.com',
      features: {'calls': true, 'federation': false},
    ),
    (v) => v.toJson(),
    ServerInfo.fromJson,
  ),
  'ops_legal_documents': _dto(
    const LegalDocuments(
      termsVersion: '2026-10',
      termsTitle: 'Terms of Service',
      terms: 'Use Helix lawfully.\nKeep your recovery code safe.',
      privacyVersion: '2026-10',
      privacyTitle: 'Privacy Policy',
      privacy: 'We store what delivery needs.\nNothing is read by the server.',
    ),
    (v) => v.toJson(),
    LegalDocuments.fromJson,
  ),
  'ops_orbit_pack_list': _dto(
    OrbitPackList(
      packs: [
        OrbitPackEntry(
          id: 'orbit-night',
          revision: 3,
          manifestBytes: 912,
          totalBytes: 184320,
          updatedAt: t0.subtract(const Duration(days: 5)),
        ),
      ],
    ),
    (v) => v.toJson(),
    OrbitPackList.fromJson,
  ),
  'ops_crash_report': _dto(
    const CrashReport(
      name: 'StateError',
      fields: {'route': '/chats', 'stage': 'build'},
    ),
    (v) => v.toJson(),
    CrashReport.fromJson,
  ),
  'ops_anomaly_report': _dto(
    AnomalyReport(
      appVersion: '2.4.0 (42)',
      platform: 'windows',
      debug: false,
      entries: [
        Anomaly(
          at: t0.subtract(const Duration(minutes: 1)),
          kind: 'request',
          where: 'POST /v1/messages',
          message: 'upstream unavailable',
          stack: '#0 ApiClient.send (api.dart:210)',
          fields: const {'status': '503'},
        ),
      ],
    ),
    (v) => v.toJson(),
    AnomalyReport.fromJson,
  ),
  'ops_account_export': _dto(
    AccountExport(
      accountId: accountA,
      exportedAt: t0,
      sections: {
        'identity': {
          'account_id': accountA,
          'has_password': true,
          'helix_name': 'alice',
        },
        'messaging': {'mailbox_envelopes': 0},
        'devices': [
          {'device_id': deviceA1, 'platform': 'android'},
        ],
      },
    ),
    (v) => v.toJson(),
    AccountExport.fromJson,
  ),
  'ops_device_key_proof': _dto(
    DeviceKeyProof(
      challengeId: '0192a4f0-0000-7000-8000-0000000000d2',
      challenge: bytes(32, 92),
      signature: bytes(64, 93),
    ),
    (v) => v.toJson(),
    DeviceKeyProof.fromJson,
  ),
  'ops_delete_account_request': _dto(
    DeleteAccountRequest(
      verificationToken: 'verified-token',
      deviceProof: DeviceKeyProof(
        challengeId: '0192a4f0-0000-7000-8000-0000000000d2',
        challenge: bytes(32, 92),
        signature: bytes(64, 93),
      ),
    ),
    (v) => v.toJson(),
    DeleteAccountRequest.fromJson,
  ),
  'ops_server_identity_document': _dto(
    ServerIdentityDocument(
      serverId: 'helix-a.example',
      publicKey: encodeBytes(bytes(32, 94)),
      apiBase: 'https://helix-a.example',
    ),
    (v) => v.toJson(),
    ServerIdentityDocument.fromJson,
  ),

  // ---------------------------------------------------------------- admin
  'admin_setup_status': _dto(
    const AdminSetupStatus(configured: true),
    (v) => v.toJson(),
    AdminSetupStatus.fromJson,
  ),
  'admin_password_request': _dto(
    const AdminPasswordRequest(password: 'correct horse battery staple'),
    (v) => v.toJson(),
    AdminPasswordRequest.fromJson,
  ),
  'admin_session': _dto(
    AdminSession(
      token: 'admin.jwt.example',
      expiresAt: t0.add(const Duration(days: 7)),
    ),
    (v) => v.toJson(),
    AdminSession.fromJson,
  ),
  'admin_change_password_request': _dto(
    const ChangeAdminPasswordRequest(
      currentPassword: 'correct horse battery staple',
      newPassword: 'a longer replacement passphrase',
    ),
    (v) => v.toJson(),
    ChangeAdminPasswordRequest.fromJson,
  ),
  'admin_account_detail': _dto(
    AdminAccountDetail(
      account: AdminAccount(
        accountId: accountB,
        status: AccountStatus.active,
        createdAt: t0.subtract(const Duration(days: 200)),
        activeDevices: 2,
        helixName: 'bob',
        phoneLast4: '0000',
        phoneNumber: '+8801700000000',
        displayName: 'Bob Rahman',
        lastSeenOn: t0.subtract(const Duration(hours: 1)),
      ),
      devices: [
        AdminDevice(
          deviceId: deviceB1,
          name: 'Bob phone',
          platform: DevicePlatform.android,
          active: true,
          createdAt: t0.subtract(const Duration(days: 200)),
          lastSeenOn: t0.subtract(const Duration(hours: 1)),
        ),
        AdminDevice(
          deviceId: '0192a4f0-0000-7000-8000-0000000000b2',
          name: 'Bob old tablet',
          platform: DevicePlatform.other,
          active: false,
          createdAt: t0.subtract(const Duration(days: 300)),
          revokedAt: t0.subtract(const Duration(days: 30)),
        ),
      ],
      hasPassword: true,
      openReports: 2,
    ),
    (v) => v.toJson(),
    AdminAccountDetail.fromJson,
  ),
  'admin_action_request': _dto(
    const AdminActionRequest(reason: 'Repeated spam reports.'),
    (v) => v.toJson(),
    AdminActionRequest.fromJson,
  ),
  'admin_recovery_code': _dto(
    AdminRecoveryCode(
      recoveryCode: 'HLX-ADM-91c2e8',
      expiresAt: t0.add(const Duration(hours: 24)),
    ),
    (v) => v.toJson(),
    AdminRecoveryCode.fromJson,
  ),
  'admin_invite': _dto(
    AdminInvite(
      inviteId: '0192a4f0-0000-7000-8000-0000000000d9',
      issuer: 'admin',
      status: InviteStatus.used,
      createdAt: t0.subtract(const Duration(days: 10)),
      expiresAt: t0.add(const Duration(days: 4)),
      redeemedBy: accountB,
    ),
    (v) => v.toJson(),
    AdminInvite.fromJson,
  ),
  'admin_created_invite': _dto(
    CreatedInvite(
      inviteId: '0192a4f0-0000-7000-8000-0000000000d9',
      inviteCode: 'HLX-INV-7f3a9c',
      expiresAt: t0.add(const Duration(days: 14)),
    ),
    (v) => v.toJson(),
    CreatedInvite.fromJson,
  ),
  'admin_report': _dto(
    AdminReport(
      reportId: '0192a4f0-0000-7000-8000-0000000000da',
      reporter: accountA,
      subject: accountB,
      category: ReportCategory.spam,
      status: ReportStatus.open,
      createdAt: t0.subtract(const Duration(hours: 8)),
      note: 'Sends unsolicited links.',
      reporterName: 'Alice Rahman',
      reporterPhone: '+8801712345678',
      subjectName: 'Bob Rahman',
      subjectPhone: '+8801700000000',
    ),
    (v) => v.toJson(),
    AdminReport.fromJson,
  ),
  'admin_resolve_report_request': _dto(
    const ResolveReportRequest(status: ReportStatus.resolved),
    (v) => v.toJson(),
    ResolveReportRequest.fromJson,
  ),
  'admin_audit_entry': _dto(
    AuditEntry(
      id: '0192a4f0-0000-7000-8000-0000000000db',
      action: 'account.suspend',
      at: t0.subtract(const Duration(hours: 8)),
      target: accountB,
      details: const {'reason': 'spam', 'report_id': '0192a4f0'},
    ),
    (v) => v.toJson(),
    AuditEntry.fromJson,
  ),
  'admin_integrations': _dto(
    const AdminIntegrations(
      push: AdminIntegrationStatus(configured: true, provider: 'fcm'),
      sms: AdminIntegrationStatus(configured: true, provider: 'bulksmsbd'),
      turn: AdminIntegrationStatus(configured: true, count: 2),
    ),
    (v) => v.toJson(),
    AdminIntegrations.fromJson,
  ),
  'admin_config': _dto(
    const AdminConfig(
      serverName: 'Helix Global',
      version: '2.4.0',
      registration: RegistrationMode.phone,
      maintenance: false,
      federationEnabled: true,
      maxAttachmentBytes: 4294967296,
      nodeId: 'node-a',
      federationDomain: 'helix.agiletechbd.com',
      integrations: AdminIntegrations(
        push: AdminIntegrationStatus(configured: true, provider: 'fcm'),
        sms: AdminIntegrationStatus(configured: true, provider: 'bulksmsbd'),
        turn: AdminIntegrationStatus(configured: true, count: 2),
      ),
    ),
    (v) => v.toJson(),
    AdminConfig.fromJson,
  ),
  'admin_config_patch': _dto(
    const AdminConfigPatch(
      serverName: 'Helix Global (beta)',
      maintenance: true,
      federationEnabled: false,
    ),
    (v) => v.toJson(),
    AdminConfigPatch.fromJson,
  ),
  'admin_feature_flags': _dto(
    const FeatureFlags(flags: {'calls': true, 'anomaly_upload': false}),
    (v) => v.toJson(),
    FeatureFlags.fromJson,
  ),
  'admin_set_feature_flag_request': _dto(
    const SetFeatureFlagRequest(enabled: true),
    (v) => v.toJson(),
    SetFeatureFlagRequest.fromJson,
  ),
  'admin_log_lines': _dto(
    const AdminLogLines(
      lines: [
        '{"level":"info","msg":"server ready"}',
        '{"level":"warn","msg":"slow send"}',
      ],
    ),
    (v) => v.toJson(),
    AdminLogLines.fromJson,
  ),
  'admin_purge_result': _dto(
    const PurgeResult(removed: {'mailbox_envelopes': 12, 'media_objects': 3}),
    (v) => v.toJson(),
    PurgeResult.fromJson,
  ),

  // ----------------------------------------------------------- federation
  'federation_s2s_message_batch': _dto(
    S2SMessageBatch(
      id: messageM,
      sender: '$accountA@helix-a.example',
      senderDevice: deviceA1,
      recipients: [_recipientB()],
      urgent: true,
      ephemeral: false,
    ),
    (v) => v.toJson(),
    S2SMessageBatch.fromJson,
  ),
  'federation_s2s_call_signal': _dto(
    S2SCallSignal(
      sender: '$accountA@helix-a.example',
      senderDevice: deviceA1,
      signal: CallSignalRequest(
        kind: CallSignalKind.update,
        recipients: [_recipientB()],
        ttl: const Duration(seconds: 30),
      ),
    ),
    (v) => v.toJson(),
    S2SCallSignal.fromJson,
  ),
  'federation_s2s_group_action': _dto(
    const S2SGroupAction(
      actor: '$accountA@helix-a.example',
      actorDevice: deviceA1,
      action: 'add_members',
      params: {'group_id': groupG},
      body: {
        'accounts': [accountB],
      },
    ),
    (v) => v.toJson(),
    S2SGroupAction.fromJson,
  ),
  'federation_s2s_group_action_result': _dto(
    const S2SGroupActionResult(
      status: 200,
      body: {
        'added': [accountB],
        'rejected': <String, Object?>{},
        'epoch': 4,
      },
    ),
    (v) => v.toJson(),
    S2SGroupActionResult.fromJson,
  ),
  'federation_s2s_group_sync': _dto(
    S2SGroupSync(
      rosterVersion: 7,
      group: _groupFixture(),
      event: const RosterChangeEvent(
        groupId: groupG,
        change: RosterChangeKind.added,
        epoch: 3,
        actor: accountA,
        members: [accountB],
      ),
      notify: const [accountB],
    ),
    (v) => v.toJson(),
    S2SGroupSync.fromJson,
  ),
  'federation_s2s_group_sync_response': _dto(
    const S2SGroupSyncResponse(
      devices: {
        accountA: [deviceA1],
        accountB: [deviceB1],
      },
      rejected: ['0192a4f0-0000-7000-8000-0000000000ce'],
    ),
    (v) => v.toJson(),
    S2SGroupSyncResponse.fromJson,
  ),
  'federation_s2s_group_message': _dto(
    S2SGroupMessage(
      id: messageM,
      sender: '$accountA@helix-a.example',
      senderDevice: deviceA1,
      payload: bytes(240, 95),
      devices: const [deviceB1],
      distributions: [DevicePayload(device: deviceB1, payload: bytes(96, 55))],
      urgent: true,
      ephemeral: false,
    ),
    (v) => v.toJson(),
    S2SGroupMessage.fromJson,
  ),
};

JsonMap _encode(Object value) => switch (value) {
  final ContentMessage v => v.toJson(),
  final Envelope v => v.toJson(),
  final SealedPayload v => v.toJson(),
  final SendMessageRequest v => v.toJson(),
  final ApiError v => v.toJson(),
  final ServerFrame v => v.toJson(),
  final ClientFrame v => v.toJson(),
  final JsonMap v => v,
  final RegisterRequest v => v.toJson(),
  final RegisterResponse v => v.toJson(),
  final Session v => v.toJson(),
  final PhoneChallengeRequest v => v.toJson(),
  final PhoneChallengeResponse v => v.toJson(),
  final PhoneVerifyRequest v => v.toJson(),
  final PhoneVerifyResponse v => v.toJson(),
  final AccountStatusRequest v => v.toJson(),
  final AccountStatusResponse v => v.toJson(),
  final InviteLookupRequest v => v.toJson(),
  final InviteLookupResponse v => v.toJson(),
  final InviteSelfIssueResponse v => v.toJson(),
  final PasswordParamsRequest v => v.toJson(),
  final PasswordParamsResponse v => v.toJson(),
  final PasswordSignInRequest v => v.toJson(),
  final PasswordSignInResponse v => v.toJson(),
  final SetPasswordRequest v => v.toJson(),
  final LinkCreateRequest v => v.toJson(),
  final LinkCreateResponse v => v.toJson(),
  final LinkApproveRequest v => v.toJson(),
  final LinkPollResponse v => v.toJson(),
  final AddDeviceRequest v => v.toJson(),
  final DeviceChallengeRequest v => v.toJson(),
  final DeviceChallengeResponse v => v.toJson(),
  final DeviceSignInRequest v => v.toJson(),
  final RefreshRequest v => v.toJson(),
  final RecoveryLookupRequest v => v.toJson(),
  final RecoveryLookupResponse v => v.toJson(),
  final RecoveryRedeemRequest v => v.toJson(),
  final AccountInfo v => v.toJson(),
  final SetPhoneNumberRequest v => v.toJson(),
  final SetHelixNameRequest v => v.toJson(),
  final DeviceList v => v.toJson(),
  final RenameDeviceRequest v => v.toJson(),
  final RevokeOthersResponse v => v.toJson(),
  final PushTokenRequest v => v.toJson(),
  final SecurityEvent v => v.toJson(),
  final SignedPrekey v => v.toJson(),
  final AddOneTimePrekeysRequest v => v.toJson(),
  final KeyStatus v => v.toJson(),
  final AccountKeys v => v.toJson(),
  final SendMessageResponse v => v.toJson(),
  final MailboxPage v => v.toJson(),
  final AckRequest v => v.toJson(),
  final AckResponse v => v.toJson(),
  final GroupMessageRequest v => v.toJson(),
  final DiscoverySalt v => v.toJson(),
  final DiscoverRequest v => v.toJson(),
  final DiscoverResponse v => v.toJson(),
  final FindByNameResponse v => v.toJson(),
  final EncryptedProfile v => v.toJson(),
  final PresenceResponse v => v.toJson(),
  final SetOwnNameRequest v => v.toJson(),
  final BlockList v => v.toJson(),
  final PrivacySettings v => v.toJson(),
  final SetContactsRequest v => v.toJson(),
  final ReportRequest v => v.toJson(),
  final ReportResponse v => v.toJson(),
  final Group v => v.toJson(),
  final GroupStateContent v => v.toJson(),
  final CreateGroupRequest v => v.toJson(),
  final GroupSummary v => v.toJson(),
  final GroupList v => v.toJson(),
  final SetGroupStateRequest v => v.toJson(),
  final GroupVersionResponse v => v.toJson(),
  final AddMembersRequest v => v.toJson(),
  final AddMembersResponse v => v.toJson(),
  final SetRoleRequest v => v.toJson(),
  final CreateInviteLinkRequest v => v.toJson(),
  final InviteLink v => v.toJson(),
  final InviteTokenRequest v => v.toJson(),
  final InvitePreview v => v.toJson(),
  final JoinGroupResponse v => v.toJson(),
  final JoinRequest v => v.toJson(),
  final InviteLinkList v => v.toJson(),
  final JoinRequestList v => v.toJson(),
  final ResolveJoinRequest v => v.toJson(),
  final TurnCredentials v => v.toJson(),
  final CallSignalRequest v => v.toJson(),
  final CallSignalResponse v => v.toJson(),
  final CallStateRequest v => v.toJson(),
  final PendingCallList v => v.toJson(),
  final CreateUploadRequest v => v.toJson(),
  final UploadTarget v => v.toJson(),
  final HistoryBackup v => v.toJson(),
  final FullBackup v => v.toJson(),
  final FullBackupMeta v => v.toJson(),
  final LiveResponse v => v.toJson(),
  final ReadyResponse v => v.toJson(),
  final ServerInfo v => v.toJson(),
  final LegalDocuments v => v.toJson(),
  final OrbitPackList v => v.toJson(),
  final CrashReport v => v.toJson(),
  final AnomalyReport v => v.toJson(),
  final AccountExport v => v.toJson(),
  final DeviceKeyProof v => v.toJson(),
  final DeleteAccountRequest v => v.toJson(),
  final ServerIdentityDocument v => v.toJson(),
  final AdminSetupStatus v => v.toJson(),
  final AdminPasswordRequest v => v.toJson(),
  final AdminSession v => v.toJson(),
  final ChangeAdminPasswordRequest v => v.toJson(),
  final AdminAccountDetail v => v.toJson(),
  final AdminActionRequest v => v.toJson(),
  final AdminRecoveryCode v => v.toJson(),
  final AdminInvite v => v.toJson(),
  final CreatedInvite v => v.toJson(),
  final AdminReport v => v.toJson(),
  final ResolveReportRequest v => v.toJson(),
  final AuditEntry v => v.toJson(),
  final AdminIntegrations v => v.toJson(),
  final AdminConfig v => v.toJson(),
  final AdminConfigPatch v => v.toJson(),
  final FeatureFlags v => v.toJson(),
  final SetFeatureFlagRequest v => v.toJson(),
  final AdminLogLines v => v.toJson(),
  final PurgeResult v => v.toJson(),
  final S2SMessageBatch v => v.toJson(),
  final S2SCallSignal v => v.toJson(),
  final S2SGroupAction v => v.toJson(),
  final S2SGroupActionResult v => v.toJson(),
  final S2SGroupSync v => v.toJson(),
  final S2SGroupSyncResponse v => v.toJson(),
  final S2SGroupMessage v => v.toJson(),
  _ => throw ArgumentError('no encoder for ${value.runtimeType}'),
};

void main() {
  final dir = Directory('../../contracts/v2/fixtures');
  final update = Platform.environment['HELIX_UPDATE_FIXTURES'] == '1';
  const encoder = JsonEncoder.withIndent('  ');

  for (final entry in _fixtures.entries) {
    test('fixture ${entry.key}', () {
      final file = File('${dir.path}/${entry.key}.json');
      final (value, redecode) = entry.value;
      final encoded = encoder.convert(_encode(value));
      if (update) {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync('$encoded\n');
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run with HELIX_UPDATE_FIXTURES=1',
      );
      // Normalise line endings: a Windows checkout may convert to CRLF.
      final stored = file.readAsStringSync().replaceAll('\r\n', '\n').trim();
      expect(stored, encoded, reason: 'wire format of ${entry.key} changed');
      // Decoding the stored fixture and encoding again is lossless.
      expect(encoder.convert(redecode(JsonReader.decode(stored))), stored);
    });
  }

  test('every content type has a fixture and is known to ContentBody', () {
    expect(
      ContentBody.knownTypes.toSet(),
      hasLength(ContentBody.knownTypes.length),
      reason: 'ContentBody.knownTypes names a type twice',
    );
    for (final type in ContentBody.knownTypes) {
      final name = _contentFixtureNames[type] ?? 'content_$type';
      expect(
        _fixtures.containsKey(name),
        isTrue,
        reason: 'no fixture for content type $type',
      );
      // A known type reaches its body's decoder and fails on the empty
      // object; a type missing from the switch would come back as UnknownBody
      // without throwing.
      expect(
        () =>
            ContentBody.decode(type, JsonReader.of(const <String, Object?>{})),
        throwsA(isA<ProtocolFormatException>()),
        reason: '$type fell through to UnknownBody',
      );
    }
  });

  test('every realtime frame has a fixture', () {
    const frames = <String, String>{
      'hello': 'realtime_hello',
      'envelope': 'realtime_envelope_frame',
      'wake': 'realtime_wake_frame',
      'pong': 'realtime_pong_frame',
      'error': 'realtime_error_frame',
      'ack': 'realtime_client_ack_frame',
      'ping': 'realtime_client_ping_frame',
    };
    for (final entry in frames.entries) {
      expect(
        _fixtures.containsKey(entry.value),
        isTrue,
        reason: 'no fixture for realtime frame ${entry.key}',
      );
    }
    expect(
      _fixtures.containsKey('realtime_unknown_server_frame'),
      isTrue,
      reason: 'no fixture pinning forward-compatible unknown frames',
    );
  });

  test('the pinned close codes still match RealtimeCloseCode', () {
    expect(_closeCodes, {
      'unauthorized': RealtimeCloseCode.unauthorized,
      'device_revoked': RealtimeCloseCode.deviceRevoked,
      'suspended': RealtimeCloseCode.suspended,
      'superseded': RealtimeCloseCode.superseded,
      'rate_limited': RealtimeCloseCode.rateLimited,
      'idle_timeout': RealtimeCloseCode.idleTimeout,
      'protocol_error': RealtimeCloseCode.protocolError,
      'going_away': RealtimeCloseCode.goingAway,
    });
  });
}
