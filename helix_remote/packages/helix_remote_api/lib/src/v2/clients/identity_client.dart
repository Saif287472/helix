import 'package:helix_remote_api/src/v2/transport/retry.dart';
import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `identity` module: registration, phone codes, invites, password and
/// device-key sign-in, QR linking, refresh, recovery, account, devices,
/// `~Helix names` and push tokens (REST_V2.md "identity").
///
/// Sign-in routes return a [Session]; the caller stores it
/// (`DeviceSessionAuth.signedIn`). Nothing here keeps state.
final class IdentityClient {
  const IdentityClient(this._t);

  final HelixTransport _t;

  // ---------------------------------------------------------- public routes

  /// Texts a code to the number (Helix Global only).
  Future<PhoneChallengeResponse> phoneChallenge(
    PhoneChallengeRequest request,
  ) => _t.call(
    Routes.phoneChallenge,
    PhoneChallengeResponse.fromJson,
    json: request.toJson(),
  );

  Future<PhoneVerifyResponse> phoneVerify(PhoneVerifyRequest request) =>
      _t.call(
        Routes.phoneVerify,
        PhoneVerifyResponse.fromJson,
        json: request.toJson(),
      );

  Future<InviteLookupResponse> inviteLookup(String inviteCode) => _t.call(
    Routes.inviteLookup,
    InviteLookupResponse.fromJson,
    json: InviteLookupRequest(inviteCode: inviteCode).toJson(),
  );

  Future<InviteSelfIssueResponse> inviteSelfIssue() =>
      _t.call(Routes.inviteSelfIssue, InviteSelfIssueResponse.fromJson);

  /// Creates the account and its first device.
  Future<RegisterResponse> register(RegisterRequest request) => _t.call(
    Routes.register,
    RegisterResponse.fromJson,
    json: request.toJson(),
  );

  Future<PasswordParamsResponse> passwordParams(String phoneNumber) => _t.call(
    Routes.passwordParams,
    PasswordParamsResponse.fromJson,
    json: PasswordParamsRequest(phoneNumber: phoneNumber).toJson(),
  );

  /// Step one of password sign-in; step two is [addDevice] with the
  /// returned `sign_in_token`.
  Future<PasswordSignInResponse> passwordSignIn(
    PasswordSignInRequest request,
  ) => _t.call(
    Routes.passwordSignIn,
    PasswordSignInResponse.fromJson,
    json: request.toJson(),
  );

  /// A new device starts QR linking.
  Future<LinkCreateResponse> createLink(LinkCreateRequest request) => _t.call(
    Routes.linkCreate,
    LinkCreateResponse.fromJson,
    json: request.toJson(),
  );

  /// Long-polls the link for up to [wait] (at most 30 s) with the private
  /// poll token.
  Future<LinkPollResponse> pollLink(
    String linkId, {
    required String pollToken,
    Duration wait = const Duration(seconds: 25),
    CancellationToken? cancel,
  }) {
    final seconds = wait.inSeconds.clamp(0, 30);
    return _t.call(
      Routes.linkPoll,
      LinkPollResponse.fromJson,
      params: {'link_id': linkId},
      query: {'wait_s': '$seconds'},
      bearer: pollToken,
      cancel: cancel,
      timeout: _t.timeout + Duration(seconds: seconds),
    );
  }

  /// Adds a device after password sign-in or an approved link.
  Future<Session> addDevice(AddDeviceRequest request) =>
      _t.call(Routes.addDevice, Session.fromJson, json: request.toJson());

  /// Device-key sign-in, step one (refresh token lapsed).
  Future<DeviceChallengeResponse> deviceChallenge(
    DeviceChallengeRequest request,
  ) => _t.call(
    Routes.deviceChallenge,
    DeviceChallengeResponse.fromJson,
    json: request.toJson(),
  );

  /// Device-key sign-in, step two: the DSK signature over
  /// `signInSignatureBody(challenge)`.
  Future<Session> deviceSignIn(DeviceSignInRequest request) =>
      _t.call(Routes.deviceSignIn, Session.fromJson, json: request.toJson());

  /// Rotates the refresh token. `DeviceSessionAuth` calls this; it is never
  /// retried automatically (a repeat would look like reuse).
  Future<Session> refresh(String refreshToken) => _t.call(
    Routes.refreshSession,
    Session.fromJson,
    json: RefreshRequest(refreshToken: refreshToken).toJson(),
  );

  /// Checks a recovery code. A valid one answers whether the redeem needs a
  /// phone verification and the account id the new device must certify
  /// (`RecoveryLookupResponse.accountId`); an invalid one only `valid: false`.
  Future<RecoveryLookupResponse> recoveryLookup(String recoveryCode) => _t.call(
    Routes.recoveryLookup,
    RecoveryLookupResponse.fromJson,
    json: RecoveryLookupRequest(recoveryCode: recoveryCode).toJson(),
  );

  /// Moves the account to this device with a new AIK.
  Future<Session> recoveryRedeem(RecoveryRedeemRequest request) =>
      _t.call(Routes.recoveryRedeem, Session.fromJson, json: request.toJson());

  // ---------------------------------------------------------- device routes

  /// Ends this device's tokens (the device stays registered).
  Future<void> signOut() => _t.empty(Routes.signOut);

  Future<AccountInfo> account() =>
      _t.call(Routes.account, AccountInfo.fromJson);

  Future<void> setPassword(SetPasswordRequest request) =>
      _t.empty(Routes.setPassword, json: request.toJson());

  Future<void> setHelixName(String name) => _t.empty(
    Routes.setHelixName,
    json: SetHelixNameRequest(name: name).toJson(),
  );

  Future<void> clearHelixName() => _t.empty(Routes.clearHelixName);

  Future<Page<SecurityEvent>> securityEvents({
    PageRequest page = const PageRequest(),
  }) => _t.call(
    Routes.securityEvents,
    (json) => Page.fromJson(json, SecurityEvent.fromJson),
    query: page.toQuery(),
  );

  Future<DeviceList> devices() => _t.call(Routes.devices, DeviceList.fromJson);

  Future<void> renameDevice(String deviceId, String name) => _t.empty(
    Routes.renameDevice,
    params: {'device_id': deviceId},
    json: RenameDeviceRequest(name: name).toJson(),
  );

  /// Revokes a device (this one signs out). [lost] records why.
  Future<void> revokeDevice(String deviceId, {bool lost = false}) => _t.empty(
    Routes.revokeDevice,
    params: {'device_id': deviceId},
    query: {if (lost) 'reason': 'lost'},
  );

  Future<RevokeOthersResponse> revokeOtherDevices() =>
      _t.call(Routes.revokeOtherDevices, RevokeOthersResponse.fromJson);

  /// Approves a scanned link with the provisioning message sealed to the
  /// new device.
  Future<void> approveLink(String linkId, LinkApproveRequest request) =>
      _t.empty(
        Routes.approveLink,
        params: {'link_id': linkId},
        json: request.toJson(),
      );

  Future<void> setPushToken(PushTokenRequest request) =>
      _t.empty(Routes.setPushToken, json: request.toJson());

  Future<void> clearPushToken() => _t.empty(Routes.clearPushToken);
}
