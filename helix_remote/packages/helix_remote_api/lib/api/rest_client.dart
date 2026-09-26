import 'package:helix_remote_domain/models.dart';

abstract class HelixRemoteRestClient {
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String phoneHash,
    required String otpCode,
    String? otpChallengeId,
    // Helix Global signs up without invitations, so this is optional: when
    // omitted the server takes its invite-less phone-authenticated path.
    // Personal/self-hosted servers still reject an empty invite code.
    String? inviteCode,
    required String displayName,
    bool tosAccepted = false,
    String tosVersion = '',
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
    required String deviceName,
    // Last few digits of the phone number, display-only, never anything
    // that could be used to recover the full number. Optional so callers
    // that don't have it (or don't want to send it) need no changes.
    String phoneLast4 = '',
  });

  Future<Map<String, dynamic>> fetchDiscoverySalt();

  Future<Map<String, dynamic>> requestPhoneOtp({
    required String phoneHash,
    required String phoneNumber,
  });

  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phoneHash,
    required String otpCode,
    String? challengeId,
  });

  Future<Map<String, dynamic>> lookupInvite({required String inviteCode});

  Future<Map<String, dynamic>> autoIssueGlobalInvite();

  /// Server facts the signed-in user may be shown, currently just the
  /// admin-chosen `server_name` (empty when unnamed).
  Future<Map<String, dynamic>> getServerInfo();

  Future<Map<String, dynamic>> matchPhoneHashes(
    List<String> phoneHashes, {
    bool fullSync = false,
  });

  Future<Map<String, dynamic>> getChallenge({
    required String accountId,
    required String deviceId,
  });

  Future<Map<String, dynamic>> loginDevice({
    required String accountId,
    required String deviceId,
    required String signature,
  });

  Future<Map<String, dynamic>> refreshToken({required String refreshToken});

  Future<List<RemoteDevice>> listDevices();

  Future<Map<String, dynamic>> requestNewDeviceLink({
    required String accountId,
    required String deviceId,
    required String deviceName,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
  });

  Future<Map<String, dynamic>> approveDeviceLink({
    required String linkId,
    required String verificationCode,
  });

  Future<Map<String, dynamic>> rejectDeviceLink({
    required String linkId,
    required String verificationCode,
  });

  Future<Map<String, dynamic>> completeNewDeviceLink({
    required String linkId,
    required String signature,
  });

  Future<void> renameDevice({
    required String deviceId,
    required String deviceName,
  });

  Future<void> revokeDevice(String deviceId);

  Future<void> reportLostDevice(String deviceId);

  Future<List<Map<String, dynamic>>> getDeviceSecurityHistory(String deviceId);

  Future<void> uploadPreKeys({
    required int signedPrekeyId,
    required String signedPrekey,
    required String signedPrekeySignature,
    required List<Map<String, dynamic>> oneTimePrekeys,
  });

  Future<Map<String, dynamic>> getPreKeyBundle({required String accountId});

  Future<Map<String, dynamic>> sendContactRequest({
    required String peerAccountId,
  });

  Future<void> acceptContactRequest(String requestId);

  Future<Map<String, dynamic>> requestAttachmentUpload({
    required int fileSize,
    required String fileHash,
  });

  Future<Map<String, dynamic>> requestAttachmentDownload(String fileId);

  Future<void> requestAccountDeletion({required String confirmation});

  Future<Map<String, dynamic>> exportData();

  Future<Map<String, dynamic>> uploadBackup({
    required String backupId,
    required String backupData,
    required int version,
    required String kdf,
    required String salt,
    String backupKeyHint = '',
    int deletionWatermark = 0,
  });

  Future<Map<String, dynamic>> downloadBackup();

  Future<Map<String, dynamic>> requestBackupMediaUpload({
    required String objectId,
    required int byteSize,
    required String sha256,
  });

  Future<Map<String, dynamic>> getBackupMediaStatus(String objectId);

  Future<List<Map<String, dynamic>>> searchContacts(String query);

  Future<Map<String, dynamic>> getMyProfile();
  Future<Map<String, dynamic>> updateDisplayName(String displayName);

  Future<Map<String, dynamic>> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required Map<String, dynamic> payload,
    String? requestId,
  });

  Future<Map<String, dynamic>> getPendingCalls();
  Future<Map<String, dynamic>> acceptPendingCall(String callId);
  Future<Map<String, dynamic>> declinePendingCall(String callId);
  Future<Map<String, dynamic>> cancelPendingCall(String callId);

  // --- Group calls ---------------------------------------------------------
  //
  // The domain models ([CallRoom], [CallLink], [ScheduledCall]) already exist;
  // what was missing was the transport, which is why `GroupCallScreen` and
  // `CallLinkSheet` had no way to reach a room and nothing constructed a
  // `RemoteGroupCallService`.
  //
  // IMPORTANT - rooms are not yet joinable end to end. The server tracks room
  // membership and distributes room keys, but it has no route to relay a
  // room's SDP or ICE. `POST /calls/signal` validates a one-to-one `call_id`
  // and a `signal_type` from `{offer, answer, ice, ...}` against a pending-call
  // session, so the `{type: offer, room_id: ...}` frames
  // `RemoteGroupCallService` emits are rejected by it. A room can therefore be
  // created, joined and populated, but no two devices will ever exchange media
  // in it.
  //
  // Everything below is therefore correct and tested against the server's
  // actual routes, and the scheduled-call half is fully usable today (it is
  // plain CRUD plus RSVP plus a push). Exposing the call surfaces in the UI
  // needs a room-scoped signalling relay on the server first; see
  // `GroupCallSignallingGap` in the execution plan.

  /// Creates a room and returns it. The caller is the host, and is not a
  /// participant until it joins - the server does not add it implicitly.
  ///
  /// [scheduledCallId] links the room to an existing scheduled call, which is
  /// what lets the host start a scheduled call early.
  Future<CallRoom> createGroupCallRoom({
    required bool isVideo,
    String? scheduledCallId,
  });

  /// Room state plus the participant list. The server is authoritative for
  /// both, so this is how a late joiner learns who is already in the room.
  Future<CallRoom> getGroupCallRoom(String roomId);

  Future<void> joinGroupCallRoom(String roomId);
  Future<void> leaveGroupCallRoom(String roomId);

  /// Host-only. Ends the room for everyone; the server broadcasts
  /// `room_ended`.
  Future<void> endGroupCallRoom(String roomId);

  /// Host-only. Removes a participant and broadcasts `participant_kicked`.
  Future<void> kickGroupCallParticipant(String roomId, String deviceId);

  /// Host-only. Delivers the room key, wrapped per recipient device, for the
  /// current [epoch]. [keys] is one `{'device_id': ..., 'wrapped_key': ...}`
  /// entry per participant.
  Future<void> deliverGroupCallRoomKey({
    required String roomId,
    required String keyId,
    required int epoch,
    required List<Map<String, String>> keys,
  });

  /// Records this device's screen-share state so the other participants see
  /// the change. The media itself goes over the peer connection, not here.
  Future<void> setGroupCallScreenSharing(String roomId, {required bool active});

  // --- Call links ----------------------------------------------------------

  /// Creates a shareable link for [roomId], or for a room that does not exist
  /// yet when [roomId] is null (the link then creates the room on first use).
  Future<CallLink> createGroupCallLink({
    String? roomId,
    bool requiresApproval = false,
    int maxUses = 0,
  });

  /// Resolves a link token to the room it points at.
  ///
  /// Throws when the link is unknown, revoked (410), expired (410), or has
  /// used up its allowance, so a caller has to distinguish "no such link" from
  /// "this link is dead" rather than treating both as a miss.
  Future<CallLinkResolution> resolveGroupCallLink(String token);

  /// Creator-only. Irreversible - there is no un-revoke.
  Future<void> revokeGroupCallLink(String token);

  // --- Scheduled calls -----------------------------------------------------

  /// [scheduledAt] must be in the future; the server rejects a past one.
  ///
  /// Returns the new call's id rather than a [ScheduledCall]: the create
  /// response is an acknowledgement and the server exposes no GET-by-id, so
  /// the only authoritative record is [listScheduledGroupCalls]. Callers
  /// should refresh that list after creating.
  Future<String> createScheduledGroupCall({
    required String title,
    required DateTime scheduledAt,
    required List<String> attendeeIds,
  });

  /// Upcoming calls where this account is host or attendee.
  Future<List<ScheduledCall>> listScheduledGroupCalls();

  Future<void> rsvpScheduledGroupCall(String scheduledCallId, {required bool yes});

  /// Host-only. Broadcasts `scheduled_call_cancelled` to the attendees.
  Future<void> cancelScheduledGroupCall(String scheduledCallId);

  Future<Map<String, dynamic>> getTurnCredentials();

  /// Registers this device's push token so the server can wake a closed app
  /// for an incoming call. The server keys tokens by the device id in the
  /// access token, so re-registering replaces rather than duplicates.
  Future<Map<String, dynamic>> registerPushToken({
    required String pushToken,
    String tokenType = 'FCM',
  });

  /// Drops this device's push token. Called on sign-out, before the session
  /// credentials are purged - the endpoint is authenticated, so afterwards
  /// there is no way to reach it and the server would keep waking a device
  /// that is no longer signed in.
  Future<Map<String, dynamic>> deregisterPushToken();

  Future<Map<String, dynamic>> redeemRecovery({
    required String accountId,
    required String recoveryCode,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String deviceName,
    String? accountIdentityPublicKey,
    String? phoneHash,
  });

  Future<Map<String, dynamic>> fetchProfile();
  Future<List<Map<String, dynamic>>> fetchContacts();
  Future<List<Map<String, dynamic>>> fetchContactRequests();

  set accessToken(String? token);

  Future<void> close();
}
