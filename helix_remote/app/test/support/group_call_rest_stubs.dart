import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';

/// Default no-op implementations of the group-call, call-link and
/// scheduled-call methods on [HelixRemoteRestClient].
///
/// Eleven test fakes `implements HelixRemoteRestClient`, and every one of them
/// broke the moment a method was added to that interface - the compiler demands
/// all ~60 members even when a test has nothing to do with calls. This mixin
/// carries the group-call half of that surface so a fake only has to override
/// what its test actually asserts on.
///
/// Applied as `class _Fake implements HelixRemoteRestClient with
/// GroupCallRestStubs`. The defaults fail loudly rather than returning empty
/// data, because a silent `return true` here would let a test pass while the
/// feature it thinks it covers does nothing.
mixin GroupCallRestStubs {
  Never _groupCallsNotStubbed(String method) => throw UnimplementedError(
    'HelixRemoteRestClient.$method was called but this test does not stub '
    'group calls. Override it in the fake if the test is meant to cover it.',
  );
  Future<CallRoom> createGroupCallRoom({
    required bool isVideo,
    String? scheduledCallId,
  }) async => _groupCallsNotStubbed('createGroupCallRoom');
  Future<CallRoom> getGroupCallRoom(String roomId) async =>
      _groupCallsNotStubbed('getGroupCallRoom');
  Future<void> joinGroupCallRoom(String roomId) async =>
      _groupCallsNotStubbed('joinGroupCallRoom');
  Future<void> leaveGroupCallRoom(String roomId) async =>
      _groupCallsNotStubbed('leaveGroupCallRoom');
  Future<void> endGroupCallRoom(String roomId) async =>
      _groupCallsNotStubbed('endGroupCallRoom');
  Future<void> kickGroupCallParticipant(String roomId, String deviceId) async =>
      _groupCallsNotStubbed('kickGroupCallParticipant');
  Future<void> deliverGroupCallRoomKey({
    required String roomId,
    required String keyId,
    required int epoch,
    required List<Map<String, String>> keys,
  }) async => _groupCallsNotStubbed('deliverGroupCallRoomKey');
  Future<void> setGroupCallScreenSharing(
    String roomId, {
    required bool active,
  }) async => _groupCallsNotStubbed('setGroupCallScreenSharing');
  Future<CallLink> createGroupCallLink({
    String? roomId,
    bool requiresApproval = false,
    int maxUses = 0,
  }) async => _groupCallsNotStubbed('createGroupCallLink');
  Future<CallLinkResolution> resolveGroupCallLink(String token) async =>
      _groupCallsNotStubbed('resolveGroupCallLink');
  Future<void> revokeGroupCallLink(String token) async =>
      _groupCallsNotStubbed('revokeGroupCallLink');
  Future<String> createScheduledGroupCall({
    required String title,
    required DateTime scheduledAt,
    required List<String> attendeeIds,
  }) async => _groupCallsNotStubbed('createScheduledGroupCall');
  Future<List<ScheduledCall>> listScheduledGroupCalls() async =>
      _groupCallsNotStubbed('listScheduledGroupCalls');
  Future<void> rsvpScheduledGroupCall(
    String scheduledCallId, {
    required bool yes,
  }) async => _groupCallsNotStubbed('rsvpScheduledGroupCall');
  Future<void> cancelScheduledGroupCall(String scheduledCallId) async =>
      _groupCallsNotStubbed('cancelScheduledGroupCall');
}
