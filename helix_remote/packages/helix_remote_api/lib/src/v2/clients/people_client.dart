import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `people` module: discovery, encrypted profiles, presence, blocks,
/// privacy, the contacts list used for "contacts" audiences, and reports.
final class PeopleClient {
  const PeopleClient(this._t);

  final HelixTransport _t;

  Future<DiscoverySalt> discoverySalt() =>
      _t.call(Routes.discoverySalt, DiscoverySalt.fromJson);

  /// Matches phone hashes (at most [DiscoverRequest.maxBatch] per call).
  Future<DiscoverResponse> discover(DiscoverRequest request) => _t.call(
    Routes.discover,
    DiscoverResponse.fromJson,
    json: request.toJson(),
  );

  /// Exact `~name` lookup.
  Future<FindByNameResponse> findByName(String name) => _t.call(
    Routes.findByName,
    FindByNameResponse.fromJson,
    params: {'name': name},
  );

  Future<EncryptedProfile> profile(String account) => _t.call(
    Routes.profile,
    EncryptedProfile.fromJson,
    params: {'account': account},
  );

  Future<PresenceResponse> presence(String account) => _t.call(
    Routes.presence,
    PresenceResponse.fromJson,
    params: {'account': account},
  );

  /// Publishes this account's profile; `version` must increase.
  Future<void> setOwnProfile(EncryptedProfile profile) =>
      _t.empty(Routes.setOwnProfile, json: profile.toJson());

  Future<BlockList> blocks() => _t.call(Routes.blocks, BlockList.fromJson);

  Future<void> block(String account) =>
      _t.empty(Routes.block, params: {'account': account});

  Future<void> unblock(String account) =>
      _t.empty(Routes.unblock, params: {'account': account});

  Future<PrivacySettings> privacy() =>
      _t.call(Routes.privacy, PrivacySettings.fromJson);

  Future<void> setPrivacy(PrivacySettings settings) =>
      _t.empty(Routes.setPrivacy, json: settings.toJson());

  /// Replaces the uploaded contact list (accounts only, no numbers).
  Future<void> setContacts(List<String> accounts) => _t.empty(
    Routes.setContacts,
    json: SetContactsRequest(accounts: accounts).toJson(),
  );

  Future<ReportResponse> report(ReportRequest request) =>
      _t.call(Routes.report, ReportResponse.fromJson, json: request.toJson());
}
